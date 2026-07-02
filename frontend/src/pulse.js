import 'bootstrap/dist/css/bootstrap.min.css'
import './style.css'

const HUB       = '/.well-known/mercure';
const TOPIC     = 'crypto/feed';
const FEED_URL  = '/api/feed?limit=30';
const MAX_CARDS = 60;

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

document.addEventListener('DOMContentLoaded', () => {
    feedEl = document.getElementById('pulse-feed');
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
});

// Exponential backoff, capped: 1× base, 2×, 4×… up to 30s. Keeps a dead
// backend from being hammered while still recovering fast from blips.
const backoff = (base, attempts) => Math.min(base * 2 ** attempts, 30000);

// ─── Initial load (REST) ─────────────────────────────────────────────────────

async function loadInitial() {
    try {
        const res = await fetch(FEED_URL);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const { data } = await res.json();
        loadAttempts = 0;

        feedEl.innerHTML = '';
        if (data.length === 0) {
            feedEl.innerHTML = '<p class="pulse-empty">No news yet — the pipeline is warming up.</p>';
        } else {
            data.forEach(item => feedEl.appendChild(card(item)));
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

// Catch-up after a reconnect: merge the feed via upsert (oldest first, so
// prepends land in order) instead of wiping the list like loadInitial does.
async function resync() {
    try {
        const res = await fetch(FEED_URL);
        if (!res.ok) return; // live again anyway; next disconnect retries
        const { data } = await res.json();
        [...data].reverse().forEach(item => upsert(item, { flash: false }));
    } catch (_) {}
}

// New item → prepend; known item (was pending, now enriched) → replace in place.
function upsert(item, { flash = true } = {}) {
    if (!item || typeof item.id !== 'number') return;

    const fresh = card(item);
    if (flash) fresh.classList.add('pulse-card--new');

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
