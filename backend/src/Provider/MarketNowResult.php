<?php

namespace App\Provider;

final readonly class MarketNowResult
{
    public function __construct(
        public string $summary,
        public string $model,
        public int    $totalTokens,
        public string $costUsd,
    ) {}
}
