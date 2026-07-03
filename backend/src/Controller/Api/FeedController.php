<?php

namespace App\Controller\Api;

use App\Api\NewsItemPayload;
use App\Repository\NewsItemRepository;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\Routing\Attribute\Route;

class FeedController
{
    private const DEFAULT_LIMIT = 20;
    private const MAX_LIMIT = 100;

    public function __construct(
        private readonly NewsItemRepository $newsItemRepo,
    ) {}

    #[Route('/api/feed', methods: ['GET'])]
    public function feed(Request $request): JsonResponse
    {
        $page = $request->query->getInt('page', 1);
        $limit = $request->query->getInt('limit', self::DEFAULT_LIMIT);

        if ($page < 1 || $limit < 1 || $limit > self::MAX_LIMIT) {
            return new JsonResponse([
                'error' => sprintf('page must be >= 1 and limit between 1 and %d', self::MAX_LIMIT),
            ], 400);
        }

        // Empty string (?source=) is treated as "filter absent", not "match empty".
        $source = $request->query->get('source') ?: null;
        $sentiment = $request->query->get('sentiment') ?: null;
        $assetClass = $request->query->get('assetClass') ?: null;
        $ticker = $request->query->get('ticker') ?: null;

        $minImpactRaw = $request->query->get('minImpact') ?: null;
        $minImpact = null !== $minImpactRaw ? (float) $minImpactRaw : null;
        if (null !== $minImpact && ($minImpact < 0.0 || $minImpact > 1.0)) {
            return new JsonResponse(['error' => 'minImpact must be between 0 and 1'], 400);
        }

        ['items' => $items, 'total' => $total] = $this->newsItemRepo->findFeedPage(
            $page, $limit, $source, $sentiment, $assetClass, $minImpact, $ticker,
        );

        return new JsonResponse([
            'data' => array_map(
                static fn ($item) => NewsItemPayload::from($item, $item->getEnrichment()),
                $items,
            ),
            'meta' => [
                'page'  => $page,
                'limit' => $limit,
                'total' => $total,
                'pages' => (int) ceil($total / $limit),
            ],
        ]);
    }

    #[Route('/api/items/{id}', requirements: ['id' => '\d+'], methods: ['GET'])]
    public function item(int $id): JsonResponse
    {
        $item = $this->newsItemRepo->find($id);

        if (null === $item) {
            return new JsonResponse(['error' => 'Item not found'], 404);
        }

        return new JsonResponse(NewsItemPayload::detail($item));
    }
}
