<?php

namespace App\Provider;

use Symfony\Contracts\HttpClient\Exception\ClientExceptionInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

class CoinGeckoProvider implements MarketDataProviderInterface
{
    private const ENDPOINT = 'https://api.coingecko.com/api/v3/simple/price';
    private const MAX_RETRIES = 3;
    private const RETRY_BASE_DELAY_MS = 1000;

    /**
     * @param array<string, string> $assetIds CoinGecko coin id => ticker symbol, e.g. ['bitcoin' => 'BTC']
     */
    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly array $assetIds,
    ) {}

    public function fetch(): iterable
    {
        $data = $this->requestWithBackoff();
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

    /**
     * @return array<string, array<string, mixed>>
     */
    private function requestWithBackoff(): array
    {
        $delay = self::RETRY_BASE_DELAY_MS;

        for ($attempt = 1; $attempt <= self::MAX_RETRIES; ++$attempt) {
            try {
                $response = $this->httpClient->request('GET', self::ENDPOINT, [
                    'timeout' => 10,
                    'query'   => [
                        'ids'                  => implode(',', array_keys($this->assetIds)),
                        'vs_currencies'        => 'usd',
                        'include_market_cap'   => 'true',
                        'include_24hr_vol'     => 'true',
                        'include_24hr_change'  => 'true',
                    ],
                ]);

                return $response->toArray();
            } catch (ClientExceptionInterface $e) {
                // 429 (rate limit) is the only case worth retrying — anything
                // else (4xx auth/shape errors) would just fail the same way again.
                if (429 !== $e->getResponse()->getStatusCode() || $attempt === self::MAX_RETRIES) {
                    throw $e;
                }
                usleep($delay * 1000);
                $delay *= 2;
            }
        }

        throw new \RuntimeException('CoinGecko request failed after retries'); // unreachable, satisfies static analysis
    }
}
