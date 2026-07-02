<?php

namespace App\Tests\Unit\Service;

use App\Entity\MarketSnapshot;
use App\Provider\EnrichmentResult;
use App\Repository\MarketSnapshotRepository;
use App\Service\ImpactScorer;
use PHPUnit\Framework\TestCase;

class ImpactScorerTest extends TestCase
{
    private function enrichmentResult(
        string $sentiment,
        ?string $assetClass,
        array $tickers,
        float $salience,
    ): EnrichmentResult {
        return new EnrichmentResult(
            summary: 'summary',
            sentiment: $sentiment,
            assetClass: $assetClass,
            tickers: $tickers,
            entities: [],
            salience: $salience,
            model: 'claude-haiku-4-5',
            totalTokens: 100,
            costUsd: '0.000100',
        );
    }

    private function snapshot(string $asset, ?string $changePct24h): MarketSnapshot
    {
        return (new MarketSnapshot())
            ->setAsset($asset)
            ->setPriceUsd('60000')
            ->setChangePct24h($changePct24h)
            ->setFetchedAt(new \DateTimeImmutable());
    }

    private function scorerWithSnapshots(array $snapshots): ImpactScorer
    {
        $repo = $this->createStub(MarketSnapshotRepository::class);
        $repo->method('findLatestPerAsset')->willReturn($snapshots);

        return new ImpactScorer($repo);
    }

    public function testMajorRegulationNewsOnVolatileAssetScoresHigh(): void
    {
        $scorer = $this->scorerWithSnapshots(['BTC' => $this->snapshot('BTC', '-8.5')]);

        $result = $this->enrichmentResult('negative', 'Regulation', ['BTC'], 0.9);

        self::assertGreaterThan(0.8, $scorer->score($result));
    }

    public function testRoutineNeutralNewsWithoutTickersScoresLow(): void
    {
        $scorer = $this->scorerWithSnapshots([]);

        $result = $this->enrichmentResult('neutral', null, [], 0.1);

        self::assertLessThan(0.2, $scorer->score($result));
    }

    public function testItemsWithoutSnapshotOrTickersGetADefinedLowScoreNotNullOrCrash(): void
    {
        $scorer = $this->scorerWithSnapshots([]);

        $result = $this->enrichmentResult('neutral', null, [], 0.0);

        self::assertSame(0.0, $scorer->score($result));
    }

    public function testScoreIsAlwaysClampedBetweenZeroAndOne(): void
    {
        $scorer = $this->scorerWithSnapshots(['BTC' => $this->snapshot('BTC', '50')]);

        $result = $this->enrichmentResult('negative', 'Regulation', ['BTC', 'ETH', 'SOL', 'XRP'], 1.0);

        $score = $scorer->score($result);

        self::assertLessThanOrEqual(1.0, $score);
        self::assertGreaterThanOrEqual(0.0, $score);
    }

    public function testOrderingIsSensibleAcrossScenarios(): void
    {
        $highImpact = $this->scorerWithSnapshots(['BTC' => $this->snapshot('BTC', '-12.0')])
            ->score($this->enrichmentResult('negative', 'Regulation', ['BTC'], 0.95));

        $mediumImpact = $this->scorerWithSnapshots(['BTC' => $this->snapshot('BTC', '1.2')])
            ->score($this->enrichmentResult('positive', 'Altcoin', ['BTC'], 0.4));

        $lowImpact = $this->scorerWithSnapshots([])
            ->score($this->enrichmentResult('neutral', null, [], 0.05));

        self::assertGreaterThan($mediumImpact, $highImpact);
        self::assertGreaterThan($lowImpact, $mediumImpact);
    }
}
