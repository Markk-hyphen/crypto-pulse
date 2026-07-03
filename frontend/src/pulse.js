import 'bootstrap/dist/css/bootstrap.min.css'
import './style.css'

const HUB       = '/.well-known/mercure';
const TOPIC     = 'crypto/feed';
const FEED_BASE = '/api/feed?limit=30';
const MAX_CARDS = 60;

const MARKET_NOW_TOPIC = 'crypto/market-now';
const MARKET_NOW_URL   = '/api/market-now';

// A proxied EventSource can go "zombie": the upstream (backend/hub) dies but
// the proxy keeps the browser side open, so onerror never fires and the page
// shows LIVE while silently missing every event. Watchdog: if nothing arrives
// for this long, tear the connection down and reconnect + resync. A false
// positive (news are just slow) only costs one cheap reconnect.
// Overridable for demos/tests: pulse.html?watchdog=<seconds>.
const WATCHDOG_MS = (Number(new URLSearchParams(location.search).get('watchdog')) || 300) * 1000;

let source;
let feedEl;
let loadAttempts = 0; // failed REST loads in a row
let esAttempts   = 0; // failed EventSource connections in a row
let wasDown      = false;
let lastActivity = Date.now(); // last open/message on the EventSource

let marketNowSource;
let marketNowEl;
let marketNowEsAttempts = 0; // failed EventSource connections in a row

// Client-side filter state (2.6). Applied to both the initial/resync REST
// load (via query params — the backend does the actual filtering) and to
// live Mercure events (matchesFilters below), which arrive unfiltered.
const filters = { source: '', assetClass: '', sentiment: '', minImpact: '', ticker: '' };
let filterEls;

document.addEventListener('DOMContentLoaded', () => {
    feedEl = document.getElementById('pulse-feed');
    initFilters();
    loadInitial();
    connect();

    setInterval(() => {
        if (Date.now() - lastActivity > WATCHDOG_MS) {
            lastActivity = Date.now();
            wasDown = true; // force a resync once the new connection opens
            source.close();
            connect();
        }
    }, Math.min(WATCHDOG_MS / 2, 30000));

    marketNowEl = document.getElementById('market-now');
    loadMarketNow();
    connectMarketNow();
});

// Exponential backoff, capped: 1× base, 2×, 4×… up to 30s. Keeps a dead
// backend from being hammered while still recovering fast from blips.
const backoff = (base, attempts) => Math.min(base * 2 ** attempts, 30000);

// ─── Filters (2.6) ───────────────────────────────────────────────────────────

function initFilters() {
    filterEls = {
        source:      document.getElementById('filter-source'),
        assetClass:  document.getElementById('filter-assetClass'),
        sentiment:   document.getElementById('filter-sentiment'),
        minImpact:   document.getElementById('filter-impact'),
        ticker:      document.getElementById('filter-ticker'),
    };

    filterEls.source.addEventListener('change', () => setFilter('source', filterEls.source.value));
    filterEls.assetClass.addEventListener('change', () => setFilter('assetClass', filterEls.assetClass.value));
    filterEls.sentiment.addEventListener('change', () => setFilter('sentiment', filterEls.sentiment.value));
    filterEls.minImpact.addEventListener('change', () => setFilter('minImpact', filterEls.minImpact.value));
    filterEls.ticker.addEventListener('change', () => setFilter('ticker', filterEls.ticker.value.trim().toUpperCase()));

    document.getElementById('filter-clear').addEventListener('click', () => {
        filters.source = filters.assetClass = filters.sentiment = filters.minImpact = filters.ticker = '';
        filterEls.source.value = filterEls.assetClass.value = filterEls.sentiment.value = filterEls.minImpact.value = '';
        filterEls.ticker.value = '';
        loadInitial();
    });

    // Clicking a ticker tag on a card filters the feed to that ticker.
    feedEl.addEventListener('click', (e) => {
        const tag = e.target.closest('.pulse-tag:not(.pulse-tag--class)');
        if (!tag) return;
        filterEls.ticker.value = tag.textContent;
        setFilter('ticker', tag.textContent);
    });
}

function setFilter(key, value) {
    filters[key] = value;
    loadInitial();
}

// Adds an <option> for a value not already present — keeps source/assetClass
// dropdowns populated from whatever the feed has actually seen so far,
// without a separate "distinct values" endpoint.
function ensureOption(selectEl, value) {
    if (!value || selectEl.querySelector(`option[value="${CSS.escape(value)}"]`)) return;
    const opt = document.createElement('option');
    opt.value = value;
    opt.textContent = value;
    selectEl.appendChild(opt);
}

function feedUrl() {
    const url = new URL(FEED_BASE, window.location.origin);
    if (filters.source)     url.searchParams.set('source', filters.source);
    if (filters.assetClass) url.searchParams.set('assetClass', filters.assetClass);
    if (filters.sentiment)  url.searchParams.set('sentiment', filters.sentiment);
    if (filters.minImpact)  url.searchParams.set('minImpact', filters.minImpact);
    if (filters.ticker)     url.searchParams.set('ticker', filters.ticker);
    return url.pathname + url.search;
}

// Applied to items arriving live via Mercure, which bypass the backend's
// query-param filtering — keeps the live stream consistent with whatever
// filter is currently selected.
function matchesFilters(item) {
    if (filters.source && item.source !== filters.source) return false;
    if (filters.assetClass && item.assetClass !== filters.assetClass) return false;
    if (filters.sentiment && item.sentiment !== filters.sentiment) return false;
    if (filters.minImpact && (item.impactScore ?? 0) < Number(filters.minImpact)) return false;
    if (filters.ticker && !(item.tickers ?? []).includes(filters.ticker)) return false;
    return true;
}

// ─── Initial load (REST) ─────────────────────────────────────────────────────

async function loadInitial() {
    try {
        const res = await fetch(feedUrl());
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const { data } = await res.json();
        loadAttempts = 0;

        feedEl.innerHTML = '';
        if (data.length === 0) {
            feedEl.innerHTML = '<p class="pulse-empty">No news yet — the pipeline is warming up.</p>';
        } else {
            data.forEach(item => {
                ensureOption(filterEls.source, item.source);
                ensureOption(filterEls.assetClass, item.assetClass);
                feedEl.appendChild(card(item));
            });
        }
        updateCount();
    } catch (err) {
        feedEl.innerHTML = '<p class="pulse-empty pulse-empty--error">Could not load the feed. Retrying…</p>';
        setTimeout(loadInitial, backoff(5000, loadAttempts++));
    }
}

// ─── Mercure subscription ────────────────────────────────────────────────────

function connect() {
    const url = new URL(HUB, window.location.origin);
    url.searchParams.append('topic', TOPIC);

    source = new EventSource(url.toString());
    source.onopen = () => {
        setStatus(true);
        esAttempts = 0;
        lastActivity = Date.now();
        // Events published while we were disconnected are gone from the
        // stream — pull the current feed state over REST to fill the gap.
        if (wasDown) { wasDown = false; resync(); }
    };
    source.onerror = () => {
        setStatus(false);
        wasDown = true;
        source.close();
        setTimeout(connect, backoff(3000, esAttempts++));
    };
    source.onmessage = ({ data }) => {
        lastActivity = Date.now();
        try { upsert(JSON.parse(data)); } catch (_) {}
    };
}

// ─── Market Now (2.4) ────────────────────────────────────────────────────────
// Separate EventSource on its own topic — the feed stream above already has a
// watchdog + full reconnect story; Market Now is a low-frequency, non-critical
// panel, so a plain backoff-retry on error is enough (no watchdog needed).

async function loadMarketNow() {
    try {
        const res = await fetch(MARKET_NOW_URL);
        if (!res.ok) return;
        const { data } = await res.json();
        if (data) renderMarketNow(data);
    } catch (_) {}
}

function connectMarketNow() {
    const url = new URL(HUB, window.location.origin);
    url.searchParams.append('topic', MARKET_NOW_TOPIC);

    marketNowSource = new EventSource(url.toString());
    marketNowSource.onopen = () => { marketNowEsAttempts = 0; };
    marketNowSource.onerror = () => {
        marketNowSource.close();
        setTimeout(connectMarketNow, backoff(5000, marketNowEsAttempts++));
    };
    marketNowSource.onmessage = ({ data }) => {
        try { renderMarketNow(JSON.parse(data)); } catch (_) {}
    };
}

function renderMarketNow(data) {
    if (!marketNowEl) return;
    const summaryEl = marketNowEl.querySelector('.pulse-summary');
    summaryEl.classList.remove('pulse-summary--pending');
    summaryEl.textContent = data.summary ?? '';

    let timeEl = marketNowEl.querySelector('.pulse-time');
    if (!timeEl && data.createdAt) {
        timeEl = document.createElement('span');
        timeEl.className = 'pulse-time';
        marketNowEl.querySelector('.pulse-card-meta').appendChild(timeEl);
    }
    if (timeEl && data.createdAt) {
        timeEl.title = data.createdAt;
        timeEl.textContent = when(data.createdAt);
    }
}

// Catch-up after a reconnect: merge the feed via upsert (oldest first, so
// prepends land in order) instead of wiping the list like loadInitial does.
async function resync() {
    try {
        const res = await fetch(feedUrl());
        if (!res.ok) return; // live again anyway; next disconnect retries
        const { data } = await res.json();
        [...data].reverse().forEach(item => upsert(item, { flash: false }));
    } catch (_) {}
}

// New item → prepend; known item (was pending, now enriched) → replace in place.
// Live Mercure events aren't pre-filtered by the backend, so a non-matching
// item is dropped here — but if it was already on screen (edited out of the
// current filter by re-enrichment) it must still be removed, not left stale.
function upsert(item, { flash = true } = {}) {
    if (!item || typeof item.id !== 'number') return;

    const existingBeforeFilter = feedEl.querySelector(`[data-id="${item.id}"]`);
    if (!matchesFilters(item)) {
        existingBeforeFilter?.remove();
        updateCount();
        return;
    }

    ensureOption(filterEls.source, item.source);
    ensureOption(filterEls.assetClass, item.assetClass);

    const fresh = card(item);
    if (flash) fresh.classList.add('pulse-card--new');

    if (existingBeforeFilter) {
        existingBeforeFilter.replaceWith(fresh);
    } else {
        feedEl.querySelector('.pulse-empty')?.remove();
        feedEl.prepend(fresh);
        while (feedEl.children.length > MAX_CARDS) feedEl.lastChild.remove();
    }
    updateCount();
}

// ─── Card rendering ──────────────────────────────────────────────────────────

function card(item) {
    const el = document.createElement('article');
    el.className = 'pulse-card';
    el.dataset.id = item.id;

    const sentiment = item.sentiment ?? null;
    const enriched  = null !== item.summary;

    el.innerHTML = `
        <div class="pulse-card-meta">
            <span class="pulse-source">${esc(item.source)}</span>
            <span class="pulse-time" title="${esc(item.publishedAt)}">${when(item.publishedAt)}</span>
            ${sentiment ? `<span class="pulse-sentiment pulse-sentiment--${esc(sentiment)}">${esc(sentiment)}</span>` : ''}
        </div>
        <h3 class="pulse-title">
            <a href="${esc(item.url)}" target="_blank" rel="noopener noreferrer">${esc(item.title)}</a>
        </h3>
        ${enriched
            ? `<p class="pulse-summary">${esc(item.summary)}</p>`
            : '<p class="pulse-summary pulse-summary--pending">Awaiting AI enrichment…</p>'}
        <div class="pulse-tags">
            ${item.assetClass ? `<span class="pulse-tag pulse-tag--class">${esc(item.assetClass)}</span>` : ''}
            ${(item.tickers ?? []).map(t => `<span class="pulse-tag">${esc(t)}</span>`).join('')}
        </div>`;
    return el;
}

function esc(value) {
    const div = document.createElement('div');
    div.textContent = String(value ?? '');
    return div.innerHTML.replaceAll('"', '&quot;');
}

function when(iso) {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    const mins = Math.round((Date.now() - d.getTime()) / 60000);
    if (mins < 1)  return 'just now';
    if (mins < 60) return `${mins}m ago`;
    if (mins < 60 * 24) return `${Math.floor(mins / 60)}h ago`;
    return d.toLocaleDateString();
}

// ─── UI helpers ──────────────────────────────────────────────────────────────

function setStatus(on) {
    document.querySelector('.live-dot')?.classList.toggle('live-dot--off', !on);
    const lbl = document.querySelector('.live-label');
    if (lbl) lbl.textContent = on ? 'LIVE' : 'RECONNECTING';
}

function updateCount() {
    const n = feedEl.querySelectorAll('.pulse-card').length;
    const el = document.querySelector('.pulse-count');
    if (el) el.textContent = `${n} ${n === 1 ? 'item' : 'items'}`;
}
