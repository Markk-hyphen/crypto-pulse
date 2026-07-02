<?php

namespace App\Command;

use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;
use Symfony\Component\Messenger\Envelope;
use Symfony\Component\Messenger\Stamp\ErrorDetailsStamp;
use Symfony\Component\Messenger\Stamp\RedeliveryStamp;
use Symfony\Component\Messenger\Stamp\SentToFailureTransportStamp;

/**
 * Non-destructive peek into the `failed` queue (the pipeline's dead-letter
 * parking lot). Messages land there through Symfony Messenger's
 * failure_transport: a handler exhausted its retry_strategy, so the envelope
 * (with error/redelivery stamps) was re-published to the `failed` transport.
 * (The ingest/enrich queues deliberately have NO broker-level DLX — see
 * messenger.yaml — so this is the only path.)
 *
 * The command basic-gets up to --limit messages WITHOUT acking, prints what
 * it can decode, then nacks them back into the queue — nothing is consumed.
 * To actually reprocess, use `messenger:failed:retry -vv` (interactive) or
 * `messenger:failed:retry --force`; to drop poison messages, purge from the
 * RabbitMQ management UI (the AMQP failure transport is not listable, so
 * `messenger:failed:show`/`remove` do not work here).
 *
 * Side note: the nack-requeue sets the broker's `redelivered` flag on the
 * peeked messages. A later `messenger:failed:retry` routes redelivered AMQP
 * messages through the retry logic (an extra republish hop) — harmless, but
 * it shows up in the -vv output.
 */
#[AsCommand(
    name: 'app:failed:inspect',
    description: 'Peek messages parked in the failed queue (DLX) without consuming them',
)]
class FailedInspectCommand extends Command
{
    private const QUEUE = 'failed';

    public function __construct(private readonly string $rabbitmqDsn)
    {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this->addOption('limit', 'l', InputOption::VALUE_REQUIRED, 'Max messages to peek', '10');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io    = new SymfonyStyle($input, $output);
        $limit = max(1, (int) $input->getOption('limit'));

        $connection = $this->connect();
        $channel    = new \AMQPChannel($connection);
        $queue      = new \AMQPQueue($channel);
        $queue->setName(self::QUEUE);

        $rows = [];
        $tags = [];

        // Manual-ack gets: the messages stay "unacked" while we read them and
        // are returned to the queue by the nacks below — inspection, not
        // consumption.
        while (\count($rows) < $limit && ($amqpEnvelope = $queue->get()) instanceof \AMQPEnvelope) {
            $tags[] = $amqpEnvelope->getDeliveryTag();
            $rows[] = $this->describe(\count($rows) + 1, $amqpEnvelope->getBody());
        }

        foreach ($tags as $tag) {
            $queue->nack($tag, AMQP_REQUEUE);
        }
        $connection->disconnect();

        if ([] === $rows) {
            $io->success('The failed queue is empty.');

            return Command::SUCCESS;
        }

        $io->table(['#', 'Message', 'Retries', 'Error'], $rows);
        $io->text([
            \sprintf('Peeked %d message(s) — all requeued, nothing consumed.', \count($rows)),
            'Reprocess with: bin/console messenger:failed:retry -vv',
        ]);

        return Command::SUCCESS;
    }

    /** @return array{int, string, string, string} */
    private function describe(int $n, string $body): array
    {
        // Messenger's PhpSerializer wraps serialize() in addslashes() to keep
        // the body UTF-8 clean for the broker; undo it before unserializing.
        $envelope = @unserialize(stripslashes($body));

        if (!$envelope instanceof Envelope) {
            // Broker-level dead-letter: never went through the failure
            // transport, so there are no stamps to read.
            return [$n, '(undecodable — raw broker dead-letter)', '-', mb_substr($body, 0, 80)];
        }

        $error     = $envelope->last(ErrorDetailsStamp::class);
        $redelivery = $envelope->last(RedeliveryStamp::class);
        $origin    = $envelope->last(SentToFailureTransportStamp::class);

        $label = (new \ReflectionClass($envelope->getMessage()))->getShortName();
        if (null !== $origin) {
            $label .= ' (from ' . $origin->getOriginalReceiverName() . ')';
        }

        return [
            $n,
            $label,
            null !== $redelivery ? (string) $redelivery->getRetryCount() : '-',
            null !== $error ? mb_substr($error->getExceptionMessage(), 0, 120) : '-',
        ];
    }

    private function connect(): \AMQPConnection
    {
        $parts = parse_url($this->rabbitmqDsn);
        if (false === $parts) {
            throw new \RuntimeException('Could not parse RABBITMQ_DSN');
        }

        $connection = new \AMQPConnection([
            'host'     => $parts['host'] ?? 'localhost',
            'port'     => $parts['port'] ?? 5672,
            'login'    => $parts['user'] ?? 'guest',
            'password' => $parts['pass'] ?? 'guest',
            'vhost'    => urldecode(ltrim($parts['path'] ?? '/%2f', '/')),
        ]);
        $connection->connect();

        return $connection;
    }
}
