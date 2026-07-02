<?php

namespace App\Tests\Unit\Adapter;

use App\Adapter\RssAdapter;
use PHPUnit\Framework\TestCase;
use Symfony\Component\HttpClient\MockHttpClient;
use Symfony\Component\HttpClient\Response\MockResponse;

class RssAdapterTest extends TestCase
{
    private const RSS = <<<'XML'
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Test Feed</title>
            <item>
              <title>Bitcoin hits &lt;b&gt;new high&lt;/b&gt;</title>
              <link>https://example.com/btc-high</link>
              <guid>guid-1</guid>
              <description>BTC &lt;i&gt;rallies&lt;/i&gt; today.</description>
              <pubDate>Wed, 01 Jul 2026 12:00:00 GMT</pubDate>
            </item>
            <item>
              <title>No link, must be skipped</title>
            </item>
          </channel>
        </rss>
        XML;

    private const ATOM = <<<'XML'
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Now We Are Atom</title>
          <entry><title>Invisible to RSS parsing</title></entry>
        </feed>
        XML;

    public function testParsesRssItemsAndStripsMarkup(): void
    {
        $adapter = new RssAdapter(new MockHttpClient(new MockResponse(self::RSS)), 'test-rss', 'https://example.com/rss');

        $items = iterator_to_array($adapter->fetch(), false);

        self::assertCount(1, $items); // the link-less item is skipped
        self::assertSame('guid-1', $items[0]['externalId']);
        self::assertSame('Bitcoin hits new high', $items[0]['title']);
        self::assertSame('https://example.com/btc-high', $items[0]['url']);
        self::assertSame('BTC rallies today.', $items[0]['body']);
        self::assertSame('2026-07-01', $items[0]['publishedAt']->format('Y-m-d'));
    }

    public function testSendsUserAgentHeader(): void
    {
        $client = new MockHttpClient(function (string $method, string $url, array $options): MockResponse {
            self::assertContains('User-Agent: CryptoMarketPulse/1.0 (news aggregator)', $options['headers']);

            return new MockResponse(self::RSS);
        });

        iterator_to_array((new RssAdapter($client, 'test-rss', 'https://example.com/rss'))->fetch(), false);
    }

    public function testNonRssFeedFailsLoudlyInsteadOfYieldingNothing(): void
    {
        $adapter = new RssAdapter(new MockHttpClient(new MockResponse(self::ATOM)), 'test-atom', 'https://example.com/atom');

        $this->expectException(\RuntimeException::class);
        $this->expectExceptionMessage('is not RSS 2.0');

        iterator_to_array($adapter->fetch(), false);
    }
}
