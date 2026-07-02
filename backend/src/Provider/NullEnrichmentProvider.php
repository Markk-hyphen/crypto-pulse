<?php

namespace App\Provider;

/**
 * Dev-only stub: returns a fixed result without calling any API.
 * Wired as the default EnrichmentProviderInterface in config/services_dev.yaml
 * to avoid spending tokens during local development.
 */
class NullEnrichmentProvider implements EnrichmentProviderInterface
{
    public function enrich(string $contentHash, string $title, ?string $body): EnrichmentResult
    {
        return new EnrichmentResult(
            summary: '[DEV] ' . mb_substr($title, 0, 120),
            sentiment: 'neutral',
            assetClass: null,
            tickers: [],
            entities: [],
            salience: 0.0,
            model: 'null-provider',
            totalTokens: 0,
            costUsd: '0.000000',
        );
    }
}
