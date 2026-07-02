<?php

namespace App\Entity;

use App\Repository\MarketSnapshotRepository;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity(repositoryClass: MarketSnapshotRepository::class)]
#[ORM\Table(name: 'market_snapshot')]
#[ORM\Index(name: 'idx_market_snapshot_asset_fetched_at', columns: ['asset', 'fetched_at'])]
class MarketSnapshot
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    /** Ticker symbol, e.g. 'BTC', 'ETH' — matches Enrichment::tickers vocabulary */
    #[ORM\Column(length: 16)]
    private string $asset;

    #[ORM\Column(type: 'decimal', precision: 18, scale: 8)]
    private string $priceUsd;

    #[ORM\Column(type: 'decimal', precision: 20, scale: 2, nullable: true)]
    private ?string $marketCap = null;

    #[ORM\Column(type: 'decimal', precision: 20, scale: 2, nullable: true)]
    private ?string $volume24h = null;

    #[ORM\Column(type: 'decimal', precision: 8, scale: 4, nullable: true)]
    private ?string $changePct24h = null;

    #[ORM\Column(type: 'datetime_immutable')]
    private \DateTimeImmutable $fetchedAt;

    public function getId(): ?int { return $this->id; }

    public function getAsset(): string { return $this->asset; }
    public function setAsset(string $asset): static { $this->asset = $asset; return $this; }

    public function getPriceUsd(): string { return $this->priceUsd; }
    public function setPriceUsd(string $priceUsd): static { $this->priceUsd = $priceUsd; return $this; }

    public function getMarketCap(): ?string { return $this->marketCap; }
    public function setMarketCap(?string $marketCap): static { $this->marketCap = $marketCap; return $this; }

    public function getVolume24h(): ?string { return $this->volume24h; }
    public function setVolume24h(?string $volume24h): static { $this->volume24h = $volume24h; return $this; }

    public function getChangePct24h(): ?string { return $this->changePct24h; }
    public function setChangePct24h(?string $changePct24h): static { $this->changePct24h = $changePct24h; return $this; }

    public function getFetchedAt(): \DateTimeImmutable { return $this->fetchedAt; }
    public function setFetchedAt(\DateTimeImmutable $fetchedAt): static { $this->fetchedAt = $fetchedAt; return $this; }
}
