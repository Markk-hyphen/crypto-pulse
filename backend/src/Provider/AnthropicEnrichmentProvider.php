<?php

namespace App\Provider;

use Symfony\Contracts\Cache\CacheInterface;
use Symfony\Contracts\Cache\ItemInterface;
use Symfony\Contracts\HttpClient\HttpClientInterface;

class AnthropicEnrichmentProvider implements EnrichmentProviderInterface
{
    private const MODEL = 'claude-haiku-4-5-20251001';
    private const MAX_TOKENS = 512;
    private const BODY_MAX_CHARS = 4000;

    // Pricing per token — claude-haiku-4-5 (verify at https://www.anthropic.com/pricing)
    private const COST_INPUT_PER_TOKEN        = 0.00000080; // $0.80 / MTok
    private const COST_OUTPUT_PER_TOKEN       = 0.00000400; // $4.00 / MTok
    private const COST_CACHE_WRITE_PER_TOKEN  = 0.00000100; // $1.00 / MTok
    private const COST_CACHE_READ_PER_TOKEN   = 0.00000008; // $0.08 / MTok

    private const SYSTEM_PROMPT = <<<'PROMPT'
You are a cryptocurrency news analyst. Given a news article, respond ONLY with a valid JSON object with exactly these keys:
- "summary": string — 2-3 sentence neutral summary of the key facts
- "sentiment": string — one of: "positive", "negative", "neutral"
- "asset_class": string or null — primary crypto category affected (e.g. "BTC", "ETH", "DeFi", "NFT", "Regulation", "Stablecoin", "Layer2", "Exchange", "Market", "Altcoin")
- "tickers": array of strings — cryptocurrency ticker symbols mentioned (e.g. ["BTC", "ETH"])
- "entities": array of strings — key named entities: people, organizations, protocols
- "salience": number between 0 and 1 — how significant this news is for the crypto market overall (1 = major market-moving event like a regulation change, exchange hack, or ETF decision; 0 = routine/minor item with little broader impact)

Return ONLY the JSON object. No markdown, no explanation, no wrapping.
PROMPT;

    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly CacheInterface $enrichmentCache,
        private readonly string $apiKey,
    ) {}

    public function enrich(string $contentHash, string $title, ?string $body): EnrichmentResult
    {
        return $this->enrichmentCache->get(
            'enrich_' . $contentHash,
            function (ItemInterface $item) use ($title, $body): EnrichmentResult {
                $item->expiresAfter(86400);
                return $this->callApi($title, $body);
            }
        );
    }

    private function callApi(string $title, ?string $body): EnrichmentResult
    {
        $userContent = 'Title: ' . $title;
        if (null !== $body && '' !== $body) {
            $userContent .= "\n\nBody: " . mb_substr($body, 0, self::BODY_MAX_CHARS);
        }

        $response = $this->httpClient->request('POST', 'https://api.anthropic.com/v1/messages', [
            'headers' => [
                'x-api-key'        => $this->apiKey,
                'anthropic-version' => '2023-06-01',
                'anthropic-beta'   => 'prompt-caching-2024-07-31',
                'content-type'     => 'application/json',
            ],
            'json' => [
                'model'      => self::MODEL,
                'max_tokens' => self::MAX_TOKENS,
                'system'     => [
                    [
                        'type'          => 'text',
                        'text'          => self::SYSTEM_PROMPT,
                        'cache_control' => ['type' => 'ephemeral'],
                    ],
                ],
                'messages' => [
                    ['role' => 'user', 'content' => $userContent],
                ],
            ],
        ]);

        $data = $response->toArray();
        $text = $data['content'][0]['text'] ?? '';

        $parsed = json_decode($text, true);
        if (!\is_array($parsed)) {
            throw new \RuntimeException(\sprintf('Anthropic returned non-JSON response: %s', mb_substr($text, 0, 200)));
        }

        $usage            = $data['usage'] ?? [];
        $inputTokens      = (int) ($usage['input_tokens'] ?? 0);
        $outputTokens     = (int) ($usage['output_tokens'] ?? 0);
        $cacheWriteTokens = (int) ($usage['cache_creation_input_tokens'] ?? 0);
        $cacheReadTokens  = (int) ($usage['cache_read_input_tokens'] ?? 0);

        $cost = ($inputTokens      * self::COST_INPUT_PER_TOKEN)
              + ($outputTokens     * self::COST_OUTPUT_PER_TOKEN)
              + ($cacheWriteTokens * self::COST_CACHE_WRITE_PER_TOKEN)
              + ($cacheReadTokens  * self::COST_CACHE_READ_PER_TOKEN);

        $sentimentRaw = $parsed['sentiment'] ?? 'neutral';
        $sentiment    = \in_array($sentimentRaw, ['positive', 'negative', 'neutral'], true)
            ? $sentimentRaw
            : 'neutral';

        // Default to 0 (not 0.5) on a missing/invalid value: an absent signal
        // should not silently pull the impact score toward the middle.
        $salienceRaw = $parsed['salience'] ?? null;
        $salience    = \is_numeric($salienceRaw) ? max(0.0, min(1.0, (float) $salienceRaw)) : 0.0;

        return new EnrichmentResult(
            summary:     $parsed['summary'] ?? '',
            sentiment:   $sentiment,
            assetClass:  $parsed['asset_class'] ?? null,
            tickers:     \is_array($parsed['tickers'] ?? null) ? $parsed['tickers'] : [],
            entities:    \is_array($parsed['entities'] ?? null) ? $parsed['entities'] : [],
            salience:    $salience,
            model:       self::MODEL,
            totalTokens: $inputTokens + $outputTokens + $cacheWriteTokens,
            costUsd:     number_format($cost, 6, '.', ''),
        );
    }
}
