<?php

namespace App\Provider;

use App\Entity\MarketSnapshot;
use App\Entity\NewsItem;

interface MarketNowProviderInterface
{
    /**
     * @param list<NewsItem>                $items     recently enriched items (with Enrichment loaded)
     * @param array<string, MarketSnapshot>  $snapshots latest snapshot per asset, keyed by ticker
     */
    public function summarize(array $items, array $snapshots): MarketNowResult;
}
