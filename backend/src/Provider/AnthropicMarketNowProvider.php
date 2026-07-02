<?php

namespace App\Provider;

use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * "Market Now" aggregate summary — a single Sonnet call per scheduled run
 * (app:market:now), never per-item. Deliberately separate from
 * AnthropicEnrichmentProvider (Haiku, per-item, cached by contentHash):
 * mixing the two would turn a cheap periodic digest into a per-article cost.
 */
class AnthropicMarketNowProvider implements MarketNowProviderInterface
{
    // Verify at https://www.anthropic.com/pricing before assuming this is
    // still current — Sonnet 5 is the aggregation model on purpose (Haiku is
    // reserved for per-item classification volume, see AnthropicEnrichmentProvider).
    private const MODEL = 'claude-sonnet-5';
    private const MAX_TOKENS = 700;

    // Pricing per token — claude-sonnet-5 standard tier (verify at https://www.anthropic.com/pricing)
    private const COST_INPUT_PER_TOKEN  = 0.000003; // $3.00 / MTok
    private const COST_OUTPUT_PER_TOKEN = 0.000015; // $15.00 / MTok

    private const MAX_ITEMS_IN_PROMPT = 15;
    private const ITEM_SUMMARY_MAX_CHARS = 240;

    private const SYSTEM_PROMPT = <<<'PROMPT'
You are writing "Market Now" — a short live-dashboard digest for a crypto market pulse app.
Given a list of recently enriched news items and the latest market snapshots per asset,
write 3-4 sentences in neutral, informative tone covering: the most notable price moves
(mention direction and magnitude), and the news driving the market right now. Do not use
markdown, headers, or bullet points — plain prose only. If there is nothing notable, say so
briefly instead of inventing significance.
PROMPT;

    public function __construct(
        private readonly HttpClientInterface $httpClient,
        private readonly string $apiKey,
    ) {}

    public function summarize(array $items, array $snapshots): MarketNowResult
    {
        $userContent = $this->buildUserContent($items, $snapshots);

        $response = $this->httpClient->request('POST', 'https://api.anthropic.com/v1/messages', [
            'headers' => [
                'x-api-key'         => $this->apiKey,
                'anthropic-version' => '2023-06-01',
                'content-type'      => 'application/json',
            ],
            'json' => [
                'model'      => self::MODEL,
                'max_tokens' => self::MAX_TOKENS,
                // Disabled, not omitted: on Sonnet 5, omitting `thinking` runs
                // adaptive thinking by default and spends reasoning tokens on
                // what should be a cheap periodic digest.
                'thinking'   => ['type' => 'disabled'],
                'system'     => self::SYSTEM_PROMPT,
                'messages'   => [
                    ['role' => 'user', 'content' => $userContent],
                ],
            ],
        ]);

        $data = $response->toArray();
        $text = trim($data['content'][0]['text'] ?? '');

        if ('' === $text) {
            throw new \RuntimeException('Anthropic Market Now: empty response text');
        }

        $usage        = $data['usage'] ?? [];
        $inputTokens  = (int) ($usage['input_tokens'] ?? 0);
        $outputTokens = (int) ($usage['output_tokens'] ?? 0);

        $cost = ($inputTokens * self::COST_INPUT_PER_TOKEN) + ($outputTokens * self::COST_OUTPUT_PER_TOKEN);

        return new MarketNowResult(
            summary:     $text,
            model:       self::MODEL,
            totalTokens: $inputTokens + $outputTokens,
            costUsd:     number_format($cost, 6, '.', ''),
        );
    }

    /**
     * @param list<\App\Entity\NewsItem> $items
     * @param array<string, \App\Entity\MarketSnapshot> $snapshots
     */
    private function buildUserContent(array $items, array $snapshots): string
    {
        $lines = [];

        $lines[] = 'Market snapshots (latest per asset):';
        if ([] === $snapshots) {
            $lines[] = '(none available)';
        } else {
            foreach ($snapshots as $asset => $snapshot) {
                $lines[] = sprintf(
                    '- %s: $%s (24h change: %s%%)',
                    $asset,
                    $snapshot->getPriceUsd(),
                    $snapshot->getChangePct24h() ?? 'n/a',
                );
            }
        }

        $lines[] = '';
        $lines[] = 'Recent enriched news:';
        $capped = \array_slice($items, 0, self::MAX_ITEMS_IN_PROMPT);
        if ([] === $capped) {
            $lines[] = '(none available)';
        } else {
            foreach ($capped as $item) {
                $enrichment = $item->getEnrichment();
                $summary = mb_substr((string) $enrichment?->getSummary(), 0, self::ITEM_SUMMARY_MAX_CHARS);
                $tickers = implode(',', $enrichment?->getTickers() ?? []);
                $lines[] = sprintf('- [%s] %s (tickers: %s)', $enrichment?->getSentiment() ?? 'n/a', $summary, $tickers ?: 'none');
            }
        }

        return implode("\n", $lines);
    }
}
