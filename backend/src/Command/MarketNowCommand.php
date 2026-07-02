<?php

namespace App\Command;

use App\Api\MarketNowPayload;
use App\Entity\MarketNowSummary;
use App\Provider\MarketNowProviderInterface;
use App\Repository\MarketNowSummaryRepository;
use App\Repository\MarketSnapshotRepository;
use App\Repository\NewsItemRepository;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Mercure\HubInterface;
use Symfony\Component\Mercure\Update;

/**
 * 2.4 Market Now — one aggregate Sonnet call per scheduled run, never per
 * news item. See PLAN-MARKET-PULSE.md §2.4 for the full design rationale.
 */
#[AsCommand(name: 'app:market:now', description: 'Generate the Market Now aggregate summary and publish it via Mercure')]
class MarketNowCommand extends Command
{
    private const ITEMS_FOR_SUMMARY = 15;

    // Digests are cheap to keep but not worth unbounded growth — same
    // rationale as MarketSnapshotRepository's retention purge.
    private const RETENTION_HOURS = 24 * 7;

    public function __construct(
        private readonly NewsItemRepository $newsItemRepo,
        private readonly MarketSnapshotRepository $snapshotRepo,
        private readonly MarketNowSummaryRepository $summaryRepo,
        private readonly MarketNowProviderInterface $provider,
        private readonly EntityManagerInterface $em,
        private readonly HubInterface $hub,
        private readonly LoggerInterface $logger,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $items = $this->newsItemRepo->findRecentEnrichedForSummary(self::ITEMS_FOR_SUMMARY);
        $snapshots = $this->snapshotRepo->findLatestPerAsset();

        if ([] === $items && [] === $snapshots) {
            $output->writeln('[market:now] Nothing to summarize yet (no enriched items, no snapshots).');

            return Command::SUCCESS;
        }

        $sourceHash = $this->computeSourceHash($items, $snapshots);
        $latest = $this->summaryRepo->findLatest();

        if (null !== $latest && $latest->getSourceHash() === $sourceHash) {
            $output->writeln('[market:now] No change since last summary — skipping the LLM call.');
            $this->logger->info('MarketNowCommand: skipped, source unchanged', ['sourceHash' => $sourceHash]);

            return Command::SUCCESS;
        }

        $result = $this->provider->summarize($items, $snapshots);

        $summary = (new MarketNowSummary())
            ->setSummary($result->summary)
            ->setSourceHash($sourceHash)
            ->setModel($result->model)
            ->setTokens($result->totalTokens)
            ->setCostUsd($result->costUsd);

        $this->em->persist($summary);
        $this->em->flush();

        $cutoff = (new \DateTimeImmutable())->modify(sprintf('-%d hours', self::RETENTION_HOURS));
        $purged = $this->summaryRepo->deleteOlderThan($cutoff);

        // Same rationale as EnrichItemHandler: the summary is already
        // flushed, so a Mercure outage must not fail the command.
        try {
            $this->hub->publish(new Update(
                'crypto/market-now',
                json_encode(MarketNowPayload::from($summary)),
            ));
        } catch (\Throwable $e) {
            $this->logger->error('MarketNowCommand: Mercure publish failed (summary persisted, event dropped)', [
                'error' => $e->getMessage(),
            ]);
        }

        $this->logger->info('MarketNowCommand: summary generated', [
            'model'    => $result->model,
            'tokens'   => $result->totalTokens,
            'cost_usd' => $result->costUsd,
            'purged'   => $purged,
        ]);
        $output->writeln(sprintf(
            '[%s] Market Now: summary generated (model=%s, tokens=%d, cost=$%s, purged=%d).',
            date('Y-m-d H:i:s'),
            $result->model,
            $result->totalTokens,
            $result->costUsd,
            $purged,
        ));

        return Command::SUCCESS;
    }

    /**
     * @param list<\App\Entity\NewsItem> $items
     * @param array<string, \App\Entity\MarketSnapshot> $snapshots
     */
    private function computeSourceHash(array $items, array $snapshots): string
    {
        $itemIds = array_map(static fn ($item) => $item->getId(), $items);
        sort($itemIds);

        $snapshotParts = [];
        foreach ($snapshots as $asset => $snapshot) {
            $snapshotParts[] = $asset . ':' . $snapshot->getFetchedAt()->format(\DateTimeInterface::ATOM);
        }
        sort($snapshotParts);

        return hash('sha256', implode(',', $itemIds) . '|' . implode(',', $snapshotParts));
    }
}
