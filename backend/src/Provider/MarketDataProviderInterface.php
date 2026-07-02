<?php

namespace App\Provider;

interface MarketDataProviderInterface
{
    /**
     * Fetch current market data for the configured assets.
     *
     * Each item is an array with keys:
     *   asset         (string)                — ticker symbol, e.g. 'BTC'
     *   priceUsd      (string)
     *   marketCap     (string|null)
     *   volume24h     (string|null)
     *   changePct24h  (string|null)
     *   fetchedAt     (\DateTimeImmutable)
     *
     * @return iterable<array<string, mixed>>
     */
    public function fetch(): iterable;
}
