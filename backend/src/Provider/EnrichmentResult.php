<?php

namespace App\Provider;

final readonly class EnrichmentResult
{
    public function __construct(
        public string  $summary,
        public string  $sentiment,
        public ?string $assetClass,
        public array   $tickers,
        public array   $entities,
        public float   $salience,
        public string  $model,
        public int     $totalTokens,
        public string  $costUsd,
    ) {}
}
