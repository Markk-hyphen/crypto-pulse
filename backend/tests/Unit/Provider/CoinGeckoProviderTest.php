<?php

namespace App\Tests\Unit\Provider;

use App\Provider\CoinGeckoProvider;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpClient\MockHttpClient;
use Symfony\Component\HttpClient\Response\MockResponse;

class CoinGeckoProviderTest extends TestCase
{
    private const PRICE_JSON = <<<'JSON'
        {
          "bitcoin":  {"usd": 61364,   "usd_market_cap": 1230347527151.0, "usd_24h_vol": 42960747783.08, "usd_24h_change": 2.4121},
          "ethereum": {"usd": 1696.8,  "usd_market_cap": 204776483140.68, "usd_24h_vol": 13820807975.81, "usd_24h_change": 5.1239}
        }
        JSON;

    public function testMapsCoinIdsToTickersAndNormalizesFields(): void
    {
        $provider = new CoinGeckoProvider(
            new MockHttpClient(new MockResponse(self::PRICE_JSON)),
            ['bitcoin' => 'BTC', 'ethereum' => 'ETH'],
        );

        $rows = iterator_to_array($provider->fetch(), false);

        self::assertCount(2, $rows);

        // Order follows the configured assetIds map, not the JSON payload.
        self::assertSame('BTC', $rows[0]['asset']);
        self::assertSame('61364', $rows[0]['priceUsd']);
        self::assertSame('1230347527151', $rows[0]['marketCap']);
        self::assertSame('42960747783.08', $rows[0]['volume24h']);
        self::assertSame('2.4121', $rows[0]['changePct24h']);
        self::assertInstanceOf(\DateTimeImmutable::class, $rows[0]['fetchedAt']);

        self::assertSame('ETH', $rows[1]['asset']);
        self::assertSame('1696.8', $rows[1]['priceUsd']);
    }

    public function testSkipsAssetsMissingFromThePayload(): void
    {
        // solana is configured but not present in the response — must be skipped,
        // not yielded with null/zero fields.
        $provider = new CoinGeckoProvider(
            new MockHttpClient(new MockResponse(self::PRICE_JSON)),
            ['bitcoin' => 'BTC', 'solana' => 'SOL'],
        );

        $rows = iterator_to_array($provider->fetch(), false);

        self::assertCount(1, $rows);
        self::assertSame('BTC', $rows[0]['asset']);
    }

    public function testToleratesMissingOptionalFields(): void
    {
        $provider = new CoinGeckoProvider(
            new MockHttpClient(new MockResponse('{"bitcoin": {"usd": 61364}}')),
            ['bitcoin' => 'BTC'],
        );

        $rows = iterator_to_array($provider->fetch(), false);

        self::assertSame('61364', $rows[0]['priceUsd']);
        self::assertNull($rows[0]['marketCap']);
        self::assertNull($rows[0]['volume24h']);
        self::assertNull($rows[0]['changePct24h']);
    }

    public function testRequestsConfiguredCoinIds(): void
    {
        $client = new MockHttpClient(function (string $method, string $url) : MockResponse {
            self::assertSame('GET', $method);
            self::assertStringContainsString('ids=bitcoin%2Cethereum', $url);
            self::assertStringContainsString('vs_currencies=usd', $url);

            return new MockResponse(self::PRICE_JSON);
        });

        iterator_to_array(
            (new CoinGeckoProvider($client, ['bitcoin' => 'BTC', 'ethereum' => 'ETH']))->fetch(),
            false,
        );
    }
}
