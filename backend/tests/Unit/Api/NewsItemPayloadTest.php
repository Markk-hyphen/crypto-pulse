<?php

namespace App\Tests\Unit\Api;

use App\Api\NewsItemPayload;
use App\Entity\Enrichment;
use App\Entity\NewsItem;
use PHPUnit\Framework\TestCase;

class NewsItemPayloadTest extends TestCase
{
    private function makeItem(): NewsItem
    {
        return (new NewsItem())
            ->setSource('coindesk-rss')
            ->setExternalId('ext-1')
            ->setTitle('BTC breaks record')
            ->setUrl('https://example.com/btc')
            ->setBody('Full body')
            ->setPublishedAt(new \DateTimeImmutable('2026-07-02T10:00:00+00:00'))
            ->setContentHash(str_repeat('a', 64));
    }

    public function testFromWithEnrichment(): void
    {
        $enrichment = (new Enrichment())
            ->setSummary('Short summary')
            ->setSentiment('positive')
            ->setAssetClass('BTC')
            ->setTickers(['BTC'])
            ->setEntities(['Bitcoin'])
            ->setModel('claude-haiku-4-5')
            ->setCostUsd('0.000123');

        $payload = NewsItemPayload::from($this->makeItem(), $enrichment);

        self::assertSame('coindesk-rss', $payload['source']);
        self::assertSame('BTC breaks record', $payload['title']);
        self::assertSame('2026-07-02T10:00:00+00:00', $payload['publishedAt']);
        self::assertSame('Short summary', $payload['summary']);
        self::assertSame('positive', $payload['sentiment']);
        self::assertSame(['BTC'], $payload['tickers']);
        // The feed shape must stay in sync between REST and Mercure — lock the keys.
        self::assertSame(
            ['id', 'source', 'title', 'url', 'publishedAt', 'summary', 'sentiment', 'assetClass', 'tickers', 'entities', 'model', 'costUsd'],
            array_keys($payload),
        );
    }

    public function testFromWithoutEnrichmentNullsTheEnrichedFields(): void
    {
        $payload = NewsItemPayload::from($this->makeItem(), null);

        self::assertNull($payload['summary']);
        self::assertNull($payload['sentiment']);
        self::assertSame([], $payload['tickers']);
        self::assertSame([], $payload['entities']);
    }

    public function testDetailAddsBodyStatusAndCreatedAt(): void
    {
        $payload = NewsItemPayload::detail($this->makeItem());

        self::assertSame('Full body', $payload['body']);
        self::assertSame('pending', $payload['status']);
        self::assertArrayHasKey('createdAt', $payload);
    }
}
