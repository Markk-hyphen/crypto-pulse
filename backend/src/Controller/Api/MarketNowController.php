<?php

namespace App\Controller\Api;

use App\Api\MarketNowPayload;
use App\Repository\MarketNowSummaryRepository;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;

class MarketNowController
{
    public function __construct(
        private readonly MarketNowSummaryRepository $summaryRepo,
    ) {}

    #[Route('/api/market-now', methods: ['GET'])]
    public function marketNow(): JsonResponse
    {
        $summary = $this->summaryRepo->findLatest();

        return new JsonResponse([
            'data' => null !== $summary ? MarketNowPayload::from($summary) : null,
        ]);
    }
}
