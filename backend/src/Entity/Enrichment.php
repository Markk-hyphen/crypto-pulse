<?php

namespace App\Entity;

use App\Repository\EnrichmentRepository;
use Doctrine\ORM\Mapping as ORM;

#[ORM\Entity(repositoryClass: EnrichmentRepository::class)]
#[ORM\Table(name: 'enrichment')]
class Enrichment
{
    // Embedding dimensions: 1024 matches Voyage-3 (Anthropic's recommended provider).
    // Adjust here and regenerate the migration if switching providers.
    public const EMBEDDING_DIMENSIONS = 1024;

    #[ORM\Id]
    #[ORM\GeneratedValue]
    #[ORM\Column]
    private ?int $id = null;

    #[ORM\OneToOne(inversedBy: 'enrichment')]
    #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
    private NewsItem $newsItem;

    #[ORM\Column(type: 'text')]
    private string $summary;

    /** positive | negative | neutral */
    #[ORM\Column(length: 16)]
    private string $sentiment;

    /** Primary asset class affected: BTC, ETH, DeFi, NFT, Regulation… */
    #[ORM\Column(length: 64, nullable: true)]
    private ?string $assetClass = null;

    /** JSON array of ticker symbols mentioned: ["BTC","ETH"] */
    #[ORM\Column(type: 'json')]
    private array $tickers = [];

    /** JSON array of named entities (people, orgs, protocols) */
    #[ORM\Column(type: 'json')]
    private array $entities = [];

    /**
     * 0-1 priority score combining LLM salience + a deterministic heuristic
     * (asset class, ticker count, live market volatility) — see
     * Service\ImpactScorer. Computed once at enrichment time, not re-derived
     * per request.
     */
    #[ORM\Column(type: 'float', options: ['default' => 0])]
    private float $impactScore = 0.0;

    /** Dense vector representation of the article — used for semantic search */
    #[ORM\Column(type: 'vector', length: self::EMBEDDING_DIMENSIONS, nullable: true)]
    private ?array $embedding = null;

    /** Model used for enrichment, e.g. 'claude-haiku-4-5' */
    #[ORM\Column(length: 64)]
    private string $model;

    /** Total tokens consumed (input + output) for cost tracking */
    #[ORM\Column]
    private int $tokens = 0;

    /** Estimated cost in USD for this enrichment call */
    #[ORM\Column(type: 'decimal', precision: 10, scale: 6)]
    private string $costUsd = '0.000000';

    #[ORM\Column(type: 'datetime_immutable')]
    private \DateTimeImmutable $createdAt;

    public function __construct()
    {
        $this->createdAt = new \DateTimeImmutable();
    }

    public function getId(): ?int { return $this->id; }

    public function getNewsItem(): NewsItem { return $this->newsItem; }
    public function setNewsItem(NewsItem $newsItem): static { $this->newsItem = $newsItem; return $this; }

    public function getSummary(): string { return $this->summary; }
    public function setSummary(string $summary): static { $this->summary = $summary; return $this; }

    public function getSentiment(): string { return $this->sentiment; }
    public function setSentiment(string $sentiment): static { $this->sentiment = $sentiment; return $this; }

    public function getAssetClass(): ?string { return $this->assetClass; }
    public function setAssetClass(?string $assetClass): static { $this->assetClass = $assetClass; return $this; }

    public function getTickers(): array { return $this->tickers; }
    public function setTickers(array $tickers): static { $this->tickers = $tickers; return $this; }

    public function getEntities(): array { return $this->entities; }
    public function setEntities(array $entities): static { $this->entities = $entities; return $this; }

    public function getImpactScore(): float { return $this->impactScore; }
    public function setImpactScore(float $impactScore): static { $this->impactScore = $impactScore; return $this; }

    public function getEmbedding(): ?array { return $this->embedding; }
    public function setEmbedding(?array $embedding): static { $this->embedding = $embedding; return $this; }

    public function getModel(): string { return $this->model; }
    public function setModel(string $model): static { $this->model = $model; return $this; }

    public function getTokens(): int { return $this->tokens; }
    public function setTokens(int $tokens): static { $this->tokens = $tokens; return $this; }

    public function getCostUsd(): string { return $this->costUsd; }
    public function setCostUsd(string $costUsd): static { $this->costUsd = $costUsd; return $this; }

    public function getCreatedAt(): \DateTimeImmutable { return $this->createdAt; }
}
