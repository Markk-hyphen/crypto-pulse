<?php

namespace App\Provider;

/**
 * Dev default — no ANTHROPIC_API_KEY is expected in dev (see services_dev.yaml,
 * same pattern as NullEnrichmentProvider), so app:market:now must not call out.
 */
class NullMarketNowProvider implements MarketNowProviderInterface
{
    public function summarize(array $items, array $snapshots): MarketNowResult
    {
        return new MarketNowResult(
            summary:     sprintf('[dev] Market Now placeholder — %d items, %d assets tracked.', \count($items), \count($snapshots)),
            model:       'null-provider',
            totalTokens: 0,
            costUsd:     '0.000000',
        );
    }
}
