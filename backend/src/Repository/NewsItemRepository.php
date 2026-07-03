<?php

namespace App\Repository;

use App\Entity\NewsItem;
use App\Entity\NewsItemStatus;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<NewsItem>
 */
class NewsItemRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, NewsItem::class);
    }

    /**
     * Page of enriched items for the feed, newest first.
     *
     * Only enriched items are exposed: pending/failed ones have no summary or
     * sentiment yet, so they carry nothing the feed can render. The enrichment
     * is fetch-joined to avoid N+1 when serializing (OneToOne → no row
     * multiplication, LIMIT/OFFSET stay correct without a Paginator).
     *
     * @return array{items: list<NewsItem>, total: int}
     */
    public function findFeedPage(
        int $page,
        int $limit,
        ?string $source = null,
        ?string $sentiment = null,
        ?string $assetClass = null,
        ?float $minImpact = null,
        ?string $ticker = null,
    ): array {
        $qb = $this->createQueryBuilder('n')
            ->innerJoin('n.enrichment', 'e')
            ->andWhere('n.status = :status')
            ->setParameter('status', NewsItemStatus::Enriched);

        if (null !== $source) {
            $qb->andWhere('n.source = :source')->setParameter('source', $source);
        }
        if (null !== $sentiment) {
            $qb->andWhere('e.sentiment = :sentiment')->setParameter('sentiment', $sentiment);
        }
        if (null !== $assetClass) {
            $qb->andWhere('e.assetClass = :assetClass')->setParameter('assetClass', $assetClass);
        }
        if (null !== $minImpact) {
            $qb->andWhere('e.impactScore >= :minImpact')->setParameter('minImpact', $minImpact);
        }
        if (null !== $ticker) {
            // tickers is a plain JSON column (not jsonb): Postgres has no `@>`
            // containment operator for it, and DQL has no CAST to route around
            // "operator does not exist: json ~~ unknown". Resolve the matching
            // ids with one native-SQL LIKE against the text cast, then filter
            // the DQL query by id — tickers are stored upper-case (see
            // AnthropicEnrichmentProvider).
            $matchingIds = $this->getEntityManager()->getConnection()->fetchFirstColumn(
                'SELECT news_item_id FROM enrichment WHERE tickers::text LIKE :ticker',
                ['ticker' => '%"'.strtoupper($ticker).'"%'],
            );
            if ([] === $matchingIds) {
                return ['items' => [], 'total' => 0];
            }
            $qb->andWhere('n.id IN (:ids)')->setParameter('ids', $matchingIds);
        }

        $total = (int) (clone $qb)->select('COUNT(n.id)')->getQuery()->getSingleScalarResult();

        $items = $qb->addSelect('e')
            ->orderBy('n.publishedAt', 'DESC')
            ->addOrderBy('n.id', 'DESC') // tie-breaker: stable order when publishedAt collides
            ->setFirstResult(($page - 1) * $limit)
            ->setMaxResults($limit)
            ->getQuery()
            ->getResult();

        return ['items' => $items, 'total' => $total];
    }

    /**
     * Most recently enriched items, newest first — feeds the Market Now
     * aggregate (2.4). Fetch-joined for the same reason as findFeedPage: one
     * query, no N+1 when reading Enrichment fields per item.
     *
     * @return list<NewsItem>
     */
    public function findRecentEnrichedForSummary(int $limit): array
    {
        return $this->createQueryBuilder('n')
            ->innerJoin('n.enrichment', 'e')
            ->addSelect('e')
            ->andWhere('n.status = :status')
            ->setParameter('status', NewsItemStatus::Enriched)
            ->orderBy('n.publishedAt', 'DESC')
            ->addOrderBy('n.id', 'DESC')
            ->setMaxResults($limit)
            ->getQuery()
            ->getResult();
    }

    /**
     * Pending items that have been sitting for at least $minAge — i.e. their
     * EnrichItemMessage was likely lost (broker down after the ingest flush).
     * The age floor keeps the recovery sweep from double-dispatching items
     * whose message is simply still waiting in the queue.
     *
     * @return list<NewsItem>
     */
    public function findStalePending(\DateInterval $minAge): array
    {
        return $this->createQueryBuilder('n')
            ->andWhere('n.status = :status')
            ->andWhere('n.createdAt <= :cutoff')
            ->setParameter('status', NewsItemStatus::Pending)
            ->setParameter('cutoff', (new \DateTimeImmutable())->sub($minAge))
            ->getQuery()
            ->getResult();
    }
}
