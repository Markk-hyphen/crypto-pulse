<?php

namespace App\MessageHandler;

use App\Api\NewsItemPayload;
use App\Entity\Enrichment;
use App\Entity\NewsItemStatus;
use App\Message\EnrichItemMessage;
use App\Provider\EmbeddingProviderInterface;
use App\Provider\EnrichmentProviderInterface;
use App\Repository\NewsItemRepository;
use Doctrine\ORM\EntityManagerInterface;
use Psr\Log\LoggerInterface;
use Symfony\Component\Mercure\HubInterface;
use Symfony\Component\Mercure\Update;
use Symfony\Component\Messenger\Attribute\AsMessageHandler;

#[AsMessageHandler]
class EnrichItemHandler
{
    public function __construct(
        private readonly NewsItemRepository $newsItemRepo,
        private readonly EnrichmentProviderInterface $enrichmentProvider,
        private readonly EmbeddingProviderInterface $embeddingProvider,
        private readonly EntityManagerInterface $em,
        private readonly HubInterface $hub,
        private readonly LoggerInterface $logger,
    ) {}

    public function __invoke(EnrichItemMessage $message): void
    {
        $item = $this->newsItemRepo->find($message->newsItemId);

        if (null === $item) {
            $this->logger->warning('EnrichItemHandler: NewsItem not found', ['id' => $message->newsItemId]);
            return;
        }

        if ($item->getStatus() !== NewsItemStatus::Pending) {
            $this->logger->info('EnrichItemHandler: already processed, skipping', [
                'id'     => $message->newsItemId,
                'status' => $item->getStatus()->value,
            ]);
            return;
        }

        $result = $this->enrichmentProvider->enrich(
            $item->getContentHash(),
            $item->getTitle(),
            $item->getBody(),
        );

        $embedding = $this->embeddingProvider->embed(
            $item->getTitle() . "\n" . ($item->getBody() ?? '')
        );

        $enrichment = (new Enrichment())
            ->setNewsItem($item)
            ->setSummary($result->summary)
            ->setSentiment($result->sentiment)
            ->setAssetClass($result->assetClass)
            ->setTickers($result->tickers)
            ->setEntities($result->entities)
            ->setEmbedding($embedding)
            ->setModel($result->model)
            ->setTokens($result->totalTokens)
            ->setCostUsd($result->costUsd);

        $item->setStatus(NewsItemStatus::Enriched);

        $this->em->persist($enrichment);
        $this->em->flush();

        // Same shape as the REST API (GET /api/feed) — see NewsItemPayload.
        // The enrichment is already flushed: a Mercure outage must not throw,
        // or the message would retry/DLX for data that is safely persisted
        // (the retry would no-op on the status guard and the event would be
        // lost anyway). Clients recover missed events by resyncing over REST.
        try {
            $this->hub->publish(new Update(
                'crypto/feed',
                json_encode(NewsItemPayload::from($item, $enrichment)),
            ));
        } catch (\Throwable $e) {
            $this->logger->error('EnrichItemHandler: Mercure publish failed (item persisted, event dropped)', [
                'id'    => $item->getId(),
                'error' => $e->getMessage(),
            ]);
        }

        $this->logger->info('EnrichItemHandler: enriched', [
            'id'       => $item->getId(),
            'model'    => $result->model,
            'tokens'   => $result->totalTokens,
            'cost_usd' => $result->costUsd,
            'embedding' => null !== $embedding ? \count($embedding) . 'd' : 'null',
        ]);
    }
}
