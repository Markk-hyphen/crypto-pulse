<?php

namespace App\Provider;

use Symfony\Contracts\HttpClient\HttpClientInterface;

class CoinGeckoProvider implements MarketDataProviderInterface
{
    private const ENDPOINT = 'https://api.coingecko.com/api/v3/simple/price';

    /**
     * @param array<string, string> $assetIds CoinGecko coin id => ticker symbol, e.g. ['bitcoin' => 'BTC']
     */
    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly array $assetIds,
    ) {}

    public function fetch(): iterable
    {
        // No hand-rolled retry: the default http_client (framework.yaml) has
        // retry_failed, which already backs off on 429 — the rate-limit case.
        // A failed poll is harmless (nothing queued); supercronic re-runs it in
        // a couple of minutes.
        $response = $this->httpClient->request('GET', self::ENDPOINT, [
            'timeout' => 10,
            'query'   => [
                'ids'                 => implode(',', array_keys($this->assetIds)),
                'vs_currencies'       => 'usd',
                'include_market_cap'  => 'true',
                'include_24hr_vol'    => 'true',
                'include_24hr_change' => 'true',
            ],
        ]);

        $data = $response->toArray();
        $fetchedAt = new \DateTimeImmutable();

        foreach ($this->assetIds as $coinId => $ticker) {
            if (!isset($data[$coinId])) {
                continue;
            }

            $row = $data[$coinId];

            yield [
                'asset'        => $ticker,
                'priceUsd'     => (string) ($row['usd'] ?? '0'),
                'marketCap'    => isset($row['usd_market_cap']) ? (string) $row['usd_market_cap'] : null,
                'volume24h'    => isset($row['usd_24h_vol']) ? (string) $row['usd_24h_vol'] : null,
                'changePct24h' => isset($row['usd_24h_change']) ? (string) $row['usd_24h_change'] : null,
                'fetchedAt'    => $fetchedAt,
            ];
        }
    }
}
