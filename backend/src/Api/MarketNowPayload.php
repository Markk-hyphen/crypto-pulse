<?php

namespace App\Api;

use App\Entity\MarketNowSummary;

/**
 * Single source of truth for the public shape of a Market Now summary — used
 * by both GET /api/market-now and the Mercure publish in MarketNowCommand,
 * same rationale as NewsItemPayload.
 */
final class MarketNowPayload
{
    /**
     * @return array<string, mixed>
     */
    public static function from(MarketNowSummary $summary): array
    {
        return [
            'summary'   => $summary->getSummary(),
            'model'     => $summary->getModel(),
            'costUsd'   => $summary->getCostUsd(),
            'createdAt' => $summary->getCreatedAt()->format(\DateTimeInterface::ATOM),
        ];
    }
}
