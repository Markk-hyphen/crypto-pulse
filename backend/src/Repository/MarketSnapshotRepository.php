<?php

namespace App\Repository;

use App\Entity\MarketSnapshot;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<MarketSnapshot>
 */
class MarketSnapshotRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, MarketSnapshot::class);
    }

    /**
     * Most recent snapshot per asset — used as market context (impact score,
     * "asset affected" enrichment) rather than a time series in the MVP.
     *
     * @return array<string, MarketSnapshot> keyed by asset
     */
    public function findLatestPerAsset(): array
    {
        $rows = $this->createQueryBuilder('m')
            ->orderBy('m.asset', 'ASC')
            ->addOrderBy('m.fetchedAt', 'DESC')
            ->getQuery()
            ->getResult();

        $latest = [];
        foreach ($rows as $row) {
            if (!isset($latest[$row->getAsset()])) {
                $latest[$row->getAsset()] = $row;
            }
        }

        return $latest;
    }

    /**
     * Deletes snapshots older than $olderThan — prices are polled every few
     * minutes and have no natural dedup key (unlike NewsItem::contentHash), so
     * without a retention purge the table grows unbounded.
     */
    public function deleteOlderThan(\DateTimeImmutable $cutoff): int
    {
        return (int) $this->createQueryBuilder('m')
            ->delete()
            ->andWhere('m.fetchedAt < :cutoff')
            ->setParameter('cutoff', $cutoff)
            ->getQuery()
            ->execute();
    }
}
