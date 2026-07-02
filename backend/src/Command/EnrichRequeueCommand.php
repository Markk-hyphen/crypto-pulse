<?php

namespace App\Command;

use App\Message\EnrichItemMessage;
use App\Repository\NewsItemRepository;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Messenger\MessageBusInterface;

#[AsCommand(
    name: 'app:enrich:requeue-pending',
    description: 'Dispatch EnrichItemMessage for pending NewsItems whose message was likely lost (dual-write recovery)',
)]
class EnrichRequeueCommand extends Command
{
    public function __construct(
        private readonly NewsItemRepository $newsItemRepo,
        private readonly MessageBusInterface $bus,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this->addOption(
            'min-age',
            null,
            InputOption::VALUE_REQUIRED,
            'Only requeue items pending for at least this many minutes (0 = all pending). '
            . 'Guards against double-dispatching items whose message is still in the queue.',
            '10',
        );
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $minutes = max(0, (int) $input->getOption('min-age'));
        $items   = $this->newsItemRepo->findStalePending(new \DateInterval("PT{$minutes}M"));

        foreach ($items as $item) {
            $this->bus->dispatch(new EnrichItemMessage($item->getId()));
        }

        $output->writeln(\sprintf(
            '[%s] Requeued %d pending items (min-age %dm).',
            date('Y-m-d H:i:s'),
            \count($items),
            $minutes,
        ));

        return Command::SUCCESS;
    }
}
