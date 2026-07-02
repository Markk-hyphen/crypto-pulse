<?php

namespace App\Repository;

use App\Entity\MarketNowSummary;
use Doctrine\Bundle\DoctrineBundle\Repository\ServiceEntityRepository;
use Doctrine\Persistence\ManagerRegistry;

/**
 * @extends ServiceEntityRepository<MarketNowSummary>
 */
class MarketNowSummaryRepository extends ServiceEntityRepository
{
    public function __construct(ManagerRegistry $registry)
    {
        parent::__construct($registry, MarketNowSummary::class);
    }

    public function findLatest(): ?MarketNowSummary
    {
        return $this->createQueryBuilder('s')
            ->orderBy('s.createdAt', 'DESC')
            ->setMaxResults(1)
            ->getQuery()
            ->getOneOrNullResult();
    }

    /**
     * Retention purge — same rationale as MarketSnapshotRepository::deleteOlderThan:
     * this is a periodic digest, not a history product worth keeping unbounded.
     */
    public function deleteOlderThan(\DateTimeImmutable $cutoff): int
    {
        return (int) $this->createQueryBuilder('s')
            ->delete()
            ->andWhere('s.createdAt < :cutoff')
            ->setParameter('cutoff', $cutoff)
            ->getQuery()
            ->execute();
    }
}
