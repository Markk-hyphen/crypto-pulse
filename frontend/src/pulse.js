import 'bootstrap/dist/css/bootstrap.min.css'
import './style.css'

const HUB       = '/.well-known/mercure';
const TOPIC     = 'crypto/feed';
const FEED_URL  = '/api/feed?limit=30';
const MAX_CARDS = 60;

let source;
let feedEl;

document.addEventListener('DOMContentLoaded', () => {
    feedEl = document.getElementById('pulse-feed');
    loadInitial();
    connect();
});

// ─── Initial load (REST) ─────────────────────────────────────────────────────

async function loadInitial() {
    try {
        const res = await fetch(FEED_URL);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const { data } = await res.json();

        feedEl.innerHTML = '';
        if (data.length === 0) {
            feedEl.innerHTML = '<p class="pulse-empty">No news yet — the pipeline is warming up.</p>';
        } else {
            data.forEach(item => feedEl.appendChild(card(item)));
        }
        updateCount();
    } catch (err) {
        feedEl.innerHTML = '<p class="pulse-empty pulse-empty--error">Could not load the feed. Retrying…</p>';
        setTimeout(loadInitial, 5000);
    }
}

// ─── Mercure subscription ────────────────────────────────────────────────────

function connect() {
    const url = new URL(HUB, window.location.origin);
    url.searchParams.append('topic', TOPIC);

    source = new EventSource(url.toString());
    source.onopen    = () => setStatus(true);
    source.onerror   = () => { setStatus(false); source.close(); setTimeout(connect, 3000); };
    source.onmessage = ({ data }) => { try { upsert(JSON.parse(data)); } catch (_) {} };
}

// New item → prepend; known item (was pending, now enriched) → replace in place.
function upsert(item) {
    if (!item || typeof item.id !== 'number') return;

    const fresh = card(item);
    fresh.classList.add('pulse-card--new');

    const existing = feedEl.querySelector(`[data-id="${item.id}"]`);
    if (existing) {
        existing.replaceWith(fresh);
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
