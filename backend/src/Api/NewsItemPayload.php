<?php

namespace App\Api;

use App\Entity\Enrichment;
use App\Entity\NewsItem;

/**
 * Single source of truth for the public shape of a news item.
 *
 * Used by both the REST API (GET /api/feed, GET /api/items/{id}) and the
 * Mercure publish in EnrichItemHandler, so live events and REST responses
 * stay structurally identical and the dashboard can render both with the
 * same code path.
 */
final class NewsItemPayload
{
    /**
     * @return array<string, mixed>
     */
    public static function from(NewsItem $item, ?Enrichment $enrichment): array
    {
        return [
            'id'          => $item->getId(),
            'source'      => $item->getSource(),
            'title'       => $item->getTitle(),
            'url'         => $item->getUrl(),
            'publishedAt' => $item->getPublishedAt()->format(\DateTimeInterface::ATOM),
            'summary'     => $enrichment?->getSummary(),
            'sentiment'   => $enrichment?->getSentiment(),
            'assetClass'  => $enrichment?->getAssetClass(),
            'tickers'     => $enrichment?->getTickers() ?? [],
            'entities'    => $enrichment?->getEntities() ?? [],
            'model'       => $enrichment?->getModel(),
            'costUsd'     => $enrichment?->getCostUsd(),
        ];
    }

    /**
     * Detail variant: everything the feed shows plus fields that only make
     * sense when looking at a single item (body, status, timestamps).
     *
     * @return array<string, mixed>
     */
    public static function detail(NewsItem $item): array
    {
        return self::from($item, $item->getEnrichment()) + [
            'body'      => $item->getBody(),
            'status'    => $item->getStatus()->value,
            'createdAt' => $item->getCreatedAt()->format(\DateTimeInterface::ATOM),
        ];
    }
}
