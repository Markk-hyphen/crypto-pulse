<?php

namespace App\Entity;

use App\Repository\MarketNowSummaryRepository;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity(repositoryClass: MarketNowSummaryRepository::class)]
#[ORM\Table(name: 'market_now_summary')]
#[ORM\Index(name: 'idx_market_now_summary_created_at', columns: ['created_at'])]
class MarketNowSummary
{
    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\Column(type: 'text')]
    private string $summary;

    /**
     * SHA-256 over the source items/snapshots that produced this summary —
     * lets app:market:now skip the LLM call when nothing changed since the
     * last run (see Command\MarketNowCommand).
     */
    #[ORM\Column(length: 64)]
    private string $sourceHash;

    /** Model used, e.g. 'claude-sonnet-5' (or 'null-provider' in dev) */
    #[ORM\Column(length: 64)]
    private string $model;

    #[ORM\Column]
    private int $tokens = 0;

    #[ORM\Column(type: 'decimal', precision: 10, scale: 6)]
    private string $costUsd = '0.000000';

    #[ORM\Column(type: 'datetime_immutable')]
    private \DateTimeImmutable $createdAt;

    public function __construct()
    {
        $this->createdAt = new \DateTimeImmutable();
    }

    public function getId(): ?int { return $this->id; }

    public function getSummary(): string { return $this->summary; }
    public function setSummary(string $summary): static { $this->summary = $summary; return $this; }

    public function getSourceHash(): string { return $this->sourceHash; }
    public function setSourceHash(string $sourceHash): static { $this->sourceHash = $sourceHash; return $this; }

    public function getModel(): string { return $this->model; }
    public function setModel(string $model): static { $this->model = $model; return $this; }

    public function getTokens(): int { return $this->tokens; }
    public function setTokens(int $tokens): static { $this->tokens = $tokens; return $this; }

    public function getCostUsd(): string { return $this->costUsd; }
    public function setCostUsd(string $costUsd): static { $this->costUsd = $costUsd; return $this; }

    public function getCreatedAt(): \DateTimeImmutable { return $this->createdAt; }
}
