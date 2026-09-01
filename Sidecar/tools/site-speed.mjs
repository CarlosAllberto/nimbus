// Ported from nimbus/app/api/tools/web/site-speed/route.ts, minus the JSON
// body read (this sidecar reads formData) and the `req.json()`-style field
// access. SSRF guard copied verbatim from wordpress-inspector.mjs (same
// `normalizeTargetUrl`/`isUrlSafe` pattern, per the spec — no shared
// helper). User-facing strings translated to English.
const PAGESPEED_ENDPOINT = 'https://www.googleapis.com/pagespeedonline/v5/runPagespeed'
const GOOGLE_FETCH_TIMEOUT_MS = 120_000

function normalizeTargetUrl(input) {
  const s = input.trim()
  if (!s || s.length > 2048) return null
  const withProto = /^https?:\/\//i.test(s) ? s : `https://${s}`
  try {
    return new URL(withProto)
  } catch {
    return null
  }
}

function isUrlSafe(url) {
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return false
  if (url.username || url.password) return false
  const host = url.hostname.toLowerCase()
  if (!host) return false
  if (host === 'localhost' || host.endsWith('.localhost')) return false
  if (host.endsWith('.local')) return false
  if (host === 'metadata.google.internal') return false
  if (host === '[::1]' || host === '::1') return false
  if (host.includes(':') && host.startsWith('[')) {
    const inner = host.slice(1, -1).toLowerCase()
    if (inner === '::1' || inner.startsWith('fe80:') || inner.startsWith('fc') || inner.startsWith('fd'))
      return false
  }
  const ipv4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/
  const m = host.match(ipv4)
  if (m) {
    const p = [m[1], m[2], m[3], m[4]].map(Number)
    if (p[0] === 10) return false
    if (p[0] === 127) return false
    if (p[0] === 0) return false
    if (p[0] === 169 && p[1] === 254) return false
    if (p[0] === 192 && p[1] === 168) return false
    if (p[0] === 172 && p[1] >= 16 && p[1] <= 31) return false
  }
  if (host === '0.0.0.0') return false
  return true
}

function isLikelyAuthError(status, message) {
  if (status === 401 || status === 403) return true
  if (status === 400 && /API key/i.test(message || '')) return true
  return false
}

function roundCategoryScore(cat) {
  if (!cat || typeof cat.score !== 'number' || Number.isNaN(cat.score)) return null
  return Math.round(cat.score * 100)
}

const LAB_AUDIT_IDS = [
  'first-contentful-paint',
  'largest-contentful-paint',
  'speed-index',
  'total-blocking-time',
  'cumulative-layout-shift',
]

async function handleSiteSpeed(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const apiKey = process.env.GOOGLE_PAGESPEED_API_KEY?.trim()
  if (!apiKey) {
    return Response.json(
      { error: 'Add your Google PageSpeed API key in Preferences to use this tool.' },
      { status: 503 },
    )
  }

  const raw = data.get('url')
  const strategyRaw = data.get('strategy')
  const strategy =
    strategyRaw === 'desktop' || strategyRaw === 'mobile' ? strategyRaw : 'mobile'

  if (!raw || typeof raw !== 'string') {
    return Response.json(
      { error: 'Enter the site URL (e.g. https://example.com).' },
      { status: 400 },
    )
  }

  const url = normalizeTargetUrl(raw)
  if (!url || !isUrlSafe(url)) {
    return Response.json(
      { error: 'Invalid or disallowed URL (public http/https only).' },
      { status: 400 },
    )
  }

  const params = new URLSearchParams({
    url: url.toString(),
    key: apiKey,
    strategy,
    locale: 'en_US',
  })
  for (const cat of ['performance', 'accessibility', 'best-practices', 'seo']) {
    params.append('category', cat)
  }

  const googleUrl = `${PAGESPEED_ENDPOINT}?${params.toString()}`
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), GOOGLE_FETCH_TIMEOUT_MS)

  let googleRes
  try {
    googleRes = await fetch(googleUrl, {
      method: 'GET',
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    })
  } catch (e) {
    clearTimeout(timer)
    const msg = e instanceof Error ? e.message : String(e)
    if (msg.includes('abort') || msg.includes('Abort')) {
      return Response.json(
        { error: 'Timed out contacting the PageSpeed API. Try again later.' },
        { status: 504 },
      )
    }
    return Response.json(
      { error: 'Network failure while contacting the PageSpeed API.' },
      { status: 502 },
    )
  }

  let payload
  try {
    payload = await googleRes.json()
  } catch {
    clearTimeout(timer)
    return Response.json(
      { error: `Invalid response from the PageSpeed API (HTTP ${googleRes.status}).` },
      { status: 502 },
    )
  }
  clearTimeout(timer)

  if (!googleRes.ok) {
    const msg = payload?.error?.message || `PageSpeed API error (${googleRes.status}).`
    if (isLikelyAuthError(googleRes.status, msg)) {
      return Response.json(
        { error: 'Your Google PageSpeed API key was rejected. Check the key in Preferences.' },
        { status: 401 },
      )
    }
    return Response.json(
      { error: msg },
      { status: googleRes.status >= 400 ? googleRes.status : 502 },
    )
  }

  const lh = payload?.lighthouseResult
  if (!lh) {
    return Response.json(
      { error: 'Invalid response from the PageSpeed API (no lighthouseResult).' },
      { status: 502 },
    )
  }

  const cats = lh.categories ?? {}
  const scores = {
    performance: roundCategoryScore(cats.performance),
    accessibility: roundCategoryScore(cats.accessibility),
    bestPractices: roundCategoryScore(cats['best-practices']),
    seo: roundCategoryScore(cats.seo),
  }

  const metrics = []
  for (const id of LAB_AUDIT_IDS) {
    const a = lh.audits?.[id]
    if (!a) continue
    const display =
      a.displayValue ??
      (typeof a.numericValue === 'number' && !Number.isNaN(a.numericValue)
        ? String(a.numericValue)
        : '—')
    metrics.push({ id, displayValue: display })
  }

  return Response.json({
    source: 'google_pagespeed',
    requestedUrl: url.toString(),
    finalUrl: lh.finalUrl ?? payload.id ?? url.toString(),
    strategy,
    scores,
    metrics,
  })
}

export function registerSiteSpeed(registerRoute) {
  registerRoute('POST', '/api/tools/web/site-speed', handleSiteSpeed)
}
