<?php

namespace App\Service;

use App\Provider\EnrichmentResult;
use App\Repository\MarketSnapshotRepository;

/**
 * Combines the LLM-provided "salience" signal (subjective read of how
 * market-moving a story is, requested inside the same Haiku enrichment call
 * — see AnthropicEnrichmentProvider) with a deterministic heuristic over data
 * already on hand (asset class, ticker count, live market volatility from
 * MarketSnapshot). No second LLM call — see PLAN-MARKET-PULSE.md §2.5 for why.
 */
class ImpactScorer
{
    private const WEIGHT_SALIENCE  = 0.6;
    private const WEIGHT_HEURISTIC = 0.4;

    // Categories judged structurally more market-moving than routine coverage.
    private const HIGH_IMPACT_ASSET_CLASSES = ['Regulation', 'Exchange'];

    // 24h price move (%, absolute) considered volatile enough to raise impact.
    private const VOLATILITY_THRESHOLD_PCT = 5.0;

    public function __construct(
        private readonly MarketSnapshotRepository $snapshotRepo,
    ) {}

    public function score(EnrichmentResult $result): float
    {
        $score = (self::WEIGHT_SALIENCE * $result->salience) + (self::WEIGHT_HEURISTIC * $this->heuristic($result));

        return max(0.0, min(1.0, $score));
    }

    private function heuristic(EnrichmentResult $result): float
    {
        $score = 0.0;

        if ('neutral' !== $result->sentiment) {
            $score += 0.3;
        }

        if (null !== $result->assetClass && \in_array($result->assetClass, self::HIGH_IMPACT_ASSET_CLASSES, true)) {
            $score += 0.3;
        }

        if ([] !== $result->tickers) {
            $score += min(0.2, 0.05 * \count($result->tickers));
        }

        if ($this->hasVolatileTicker($result->tickers)) {
            $score += 0.2;
        }

        return min(1.0, $score);
    }

    /**
     * @param list<string> $tickers
     */
    private function hasVolatileTicker(array $tickers): bool
    {
        if ([] === $tickers) {
            return false;
        }

        $snapshots = $this->snapshotRepo->findLatestPerAsset();

        foreach ($tickers as $ticker) {
            $snapshot = $snapshots[$ticker] ?? null;
            if (null === $snapshot || null === $snapshot->getChangePct24h()) {
                continue;
            }
            if (abs((float) $snapshot->getChangePct24h()) >= self::VOLATILITY_THRESHOLD_PCT) {
                return true;
            }
        }

        return false;
    }
}
