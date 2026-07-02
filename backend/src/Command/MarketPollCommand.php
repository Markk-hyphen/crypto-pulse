<?php

namespace App\Command;

use App\Entity\MarketSnapshot;
use App\Provider\MarketDataProviderInterface;
use App\Repository\MarketSnapshotRepository;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(name: 'app:market:poll', description: 'Poll market data providers and persist MarketSnapshot rows')]
class MarketPollCommand extends Command
{
    // Snapshots are context (impact score, "asset affected"), not a time
    // series product — no need to keep more than a day of history.
    private const RETENTION_HOURS = 24;

    public function __construct(
        private readonly MarketDataProviderInterface $provider,
        private readonly MarketSnapshotRepository $repo,
        private readonly EntityManagerInterface $em,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $persisted = 0;

        foreach ($this->provider->fetch() as $raw) {
            $snapshot = (new MarketSnapshot())
                ->setAsset($raw['asset'])
                ->setPriceUsd($raw['priceUsd'])
                ->setMarketCap($raw['marketCap'])
                ->setVolume24h($raw['volume24h'])
                ->setChangePct24h($raw['changePct24h'])
                ->setFetchedAt($raw['fetchedAt']);

            $this->em->persist($snapshot);
            ++$persisted;
        }

        $this->em->flush();

        $cutoff = (new \DateTimeImmutable())->modify(\sprintf('-%d hours', self::RETENTION_HOURS));
        $purged = $this->repo->deleteOlderThan($cutoff);

        $this->logger->info('Market poll complete', [
            'persisted' => $persisted,
            'purged'    => $purged,
        ]);
        $output->writeln(\sprintf(
            '[%s] Market poll: %d snapshots persisted, %d purged (retention %dh).',
            date('Y-m-d H:i:s'),
            $persisted,
            $purged,
            self::RETENTION_HOURS,
        ));

        return Command::SUCCESS;
    }
}
