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
}
