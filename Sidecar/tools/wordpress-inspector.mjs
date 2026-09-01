// Ported from nimbus/app/api/tools/web/wordpress-inspector/route.ts, minus
// session/quota. Faithful port (505 lines in the source) — reads `url` from
// formData instead of the JSON body; everything else (SSRF guards, scan
// logic, WPVulnerability lookups) is unchanged. User-facing strings
// (errors, warnings, attribution) translated to English per the contract;
// status codes, field names, and behavior are otherwise identical.
import { compare } from 'compare-versions'

const FETCH_TIMEOUT_MS = 20_000
const PER_RESOURCE_TIMEOUT_MS = 12_000
const MAX_HTML_BYTES = 1_250_000
const MAX_PLUGINS = 30
const MAX_THEMES = 15
const BATCH_CONCURRENCY = 5
const WPVULN_BASE = 'https://www.wpvulnerability.net'

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
    if (inner === '::1' || inner.startsWith('fe80:') || inner.startsWith('fc') || inner.startsWith('fd')) return false
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

function isValidSlug(slug) {
  if (!slug || slug.length > 120) return false
  if (slug.includes('..') || slug.includes('/') || slug.includes('\\')) return false
  return /^[a-z0-9][a-z0-9_.-]*$/i.test(slug)
}

async function readResponseTextLimited(res, maxBytes) {
  const reader = res.body?.getReader()
  if (!reader) return (await res.text()).slice(0, maxBytes)
  const decoder = new TextDecoder()
  let total = 0
  let out = ''
  while (total < maxBytes) {
    const { done, value } = await reader.read()
    if (done) break
    if (value) {
      total += value.byteLength
      out += decoder.decode(value, { stream: true })
    }
  }
  reader.releaseLock?.()
  return out.slice(0, maxBytes)
}

async function fetchText(url, signal, maxBytes) {
  const controller = new AbortController()
  const t = setTimeout(() => controller.abort(), PER_RESOURCE_TIMEOUT_MS)
  const onParentAbort = () => controller.abort()
  if (signal.aborted) controller.abort()
  else signal.addEventListener('abort', onParentAbort, { once: true })
  try {
    const res = await fetch(url, {
      method: 'GET',
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        Accept: 'text/html,application/xhtml+xml,text/plain,*/*;q=0.8',
        'User-Agent':
          'Mozilla/5.0 (compatible; NimbusWordPressInspector/1.0; +https://nimbus.app) AppleWebKit/537.36',
      },
    })
    const text = await readResponseTextLimited(res, maxBytes)
    return { ok: res.ok, text, status: res.status }
  } catch {
    return { ok: false, text: '', status: 0 }
  } finally {
    clearTimeout(t)
    signal.removeEventListener('abort', onParentAbort)
  }
}

function extractCoreVersion(html) {
  const m = html.match(/<meta[^>]+name=["']generator["'][^>]*content=["'][^"']*WordPress\s+([\d.]+)/i)
  if (m?.[1]) return m[1].trim()
  const m2 = html.match(/content=["'][^"']*WordPress\s+([\d.]+)[^"']*["'][^>]*name=["']generator/i)
  return m2?.[1]?.trim() ?? null
}

function extractSlugs(html, re) {
  const found = new Set()
  let m
  const copy = new RegExp(re.source, re.flags.includes('g') ? re.flags : `${re.flags}g`)
  while ((m = copy.exec(html)) !== null) {
    const s = m[1]?.trim().toLowerCase()
    if (s && isValidSlug(s)) found.add(s)
  }
  return [...found]
}

const PLUGIN_RE = /\/wp-content\/plugins\/([^/"'?#]+)\//gi
const THEME_RE = /\/wp-content\/themes\/([^/"'?#]+)\//gi

function parseReadmeStableTag(text) {
  const line = text.split(/\r?\n/).find(l => /^\s*stable tag:/i.test(l))
  if (!line) return null
  const m = line.match(/stable tag:\s*(.+)$/i)
  const v = m?.[1]?.trim()
  return v && v.length <= 80 ? v : null
}

function parseStyleCssVersion(text) {
  const head = text.slice(0, 16_384)
  const m = head.match(/^[\s*]*version:\s*(.+)$/im)
  const v = m?.[1]?.trim().split(/\s+/)[0]
  return v && v.length <= 80 ? v : null
}

function mapPhpOp(op) {
  if (!op) return null
  const o = op.toLowerCase()
  const map = { eq: '=', ne: '!=', lt: '<', gt: '>', le: '<=', ge: '>=' }
  return map[o] ?? null
}

function matchesBound(version, bound, op) {
  if (bound == null || bound === '' || op == null || op === '') return true
  const cmpOp = mapPhpOp(op)
  if (!cmpOp) return true
  try {
    return compare(version, bound, cmpOp)
  } catch {
    return false
  }
}

function isVersionAffectedByOperator(version, operator) {
  if (!operator) return true
  const minOk = matchesBound(version, operator.min_version, operator.min_operator)
  const maxOk = matchesBound(version, operator.max_version, operator.max_operator)
  return minOk && maxOk
}

function partitionSources(sources) {
  const cves = []
  const otherSources = []
  for (const s of sources ?? []) {
    const id = (s.id ?? s.name ?? '').trim()
    if (!id) continue
    const entry = {
      id,
      name: (s.name ?? id).trim(),
      link: typeof s.link === 'string' ? s.link : null,
      published: s.date ?? undefined,
    }
    if (/^CVE-\d{4}-\d+$/i.test(id)) {
      cves.push({
        id: id.toUpperCase(),
        link: entry.link,
        title: (s.description ?? s.name ?? id).trim() || id,
        published: entry.published,
      })
    } else {
      otherSources.push({ id, name: entry.name, link: entry.link, published: entry.published })
    }
  }
  return { cves, otherSources }
}

function filterVulnsByVersion(vulns, version) {
  if (!version) return { cves: [], otherSources: [] }
  const cveMap = new Map()
  const otherMap = new Map()
  for (const v of vulns ?? []) {
    if (v.operator && !isVersionAffectedByOperator(version, v.operator)) continue
    const { cves, otherSources } = partitionSources(v.source)
    for (const c of cves) cveMap.set(c.id, c)
    for (const o of otherSources) otherMap.set(o.id, o)
  }
  return { cves: [...cveMap.values()], otherSources: [...otherMap.values()] }
}

async function fetchWpVulnerabilityJson(path, signal) {
  const url = `${WPVULN_BASE}${path}`
  const controller = new AbortController()
  const t = setTimeout(() => controller.abort(), PER_RESOURCE_TIMEOUT_MS)
  const onParentAbort = () => controller.abort()
  if (signal.aborted) controller.abort()
  else signal.addEventListener('abort', onParentAbort, { once: true })
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: { Accept: 'application/json', 'User-Agent': 'NimbusWordPressInspector/1.0' },
    })
    if (!res.ok) return null
    const j = await res.json()
    if (typeof j?.error === 'number' && j.error !== 0) return null
    return j
  } catch {
    return null
  } finally {
    clearTimeout(t)
    signal.removeEventListener('abort', onParentAbort)
  }
}

async function batchMap(items, batchSize, fn) {
  const out = []
  for (let i = 0; i < items.length; i += batchSize) {
    const chunk = items.slice(i, i + batchSize)
    const part = await Promise.all(chunk.map(fn))
    out.push(...part)
  }
  return out
}

async function handleWordpressInspector(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const raw = data.get('url')
  if (!raw || typeof raw !== 'string') {
    return Response.json({ error: 'Enter the site URL (e.g. https://example.com).' }, { status: 400 })
  }

  const url = normalizeTargetUrl(raw)
  if (!url || !isUrlSafe(url)) {
    return Response.json({ error: 'Invalid or disallowed URL (public http/https only).' }, { status: 400 })
  }

  try {
    const warnings = []
    const mainController = new AbortController()
    const mainTimer = setTimeout(() => mainController.abort(), FETCH_TIMEOUT_MS)

    let finalUrl = url.toString()
    let html = ''
    try {
      const res = await fetch(url.toString(), {
        method: 'GET',
        signal: mainController.signal,
        redirect: 'follow',
        headers: {
          Accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
          'User-Agent':
            'Mozilla/5.0 (compatible; NimbusWordPressInspector/1.0) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36',
        },
      })
      finalUrl = res.url || url.toString()
      html = await readResponseTextLimited(res, MAX_HTML_BYTES)
      if (!res.ok) {
        clearTimeout(mainTimer)
        return Response.json({ error: `Could not fetch the home page (HTTP ${res.status}).` }, { status: 502 })
      }
    } catch (e) {
      clearTimeout(mainTimer)
      const msg = e instanceof Error ? e.message : String(e)
      if (msg.includes('abort') || msg.includes('Abort')) {
        return Response.json({ error: 'Timed out loading the site. Try again or a different URL.' }, { status: 504 })
      }
      return Response.json({ error: 'Network failure while loading the site.' }, { status: 502 })
    } finally {
      clearTimeout(mainTimer)
    }

    const coreVersion = extractCoreVersion(html)
    let pluginSlugs = extractSlugs(html, PLUGIN_RE)
    let themeSlugs = extractSlugs(html, THEME_RE)

    const origPluginCount = pluginSlugs.length
    const origThemeCount = themeSlugs.length
    if (pluginSlugs.length > MAX_PLUGINS) {
      pluginSlugs = pluginSlugs.slice(0, MAX_PLUGINS)
      warnings.push(`Plugin list truncated (${origPluginCount} detected, analyzing the first ${MAX_PLUGINS}).`)
    }
    if (themeSlugs.length > MAX_THEMES) {
      themeSlugs = themeSlugs.slice(0, MAX_THEMES)
      warnings.push(`Theme list truncated (${origThemeCount} detected, analyzing the first ${MAX_THEMES}).`)
    }

    const origin = new URL(finalUrl).origin
    const scanController = new AbortController()
    const scanTimer = setTimeout(() => scanController.abort(), FETCH_TIMEOUT_MS)
    const scanSignal = scanController.signal

    try {
      const pluginVersions = await batchMap(pluginSlugs, BATCH_CONCURRENCY, async slug => {
        const readmeUrl = `${origin}/wp-content/plugins/${encodeURIComponent(slug)}/readme.txt`
        const { ok, text, status } = await fetchText(readmeUrl, scanSignal, 256_000)
        if (!ok) {
          return {
            slug,
            version: null,
            versionSource: null,
            versionError: status === 404 ? 'readme_not_found' : 'readme_fetch_failed',
          }
        }
        const version = parseReadmeStableTag(text)
        return {
          slug,
          version,
          versionSource: version ? 'readme' : null,
          versionError: version ? undefined : 'stable_tag_not_found',
        }
      })

      const themeVersions = await batchMap(themeSlugs, BATCH_CONCURRENCY, async slug => {
        const cssUrl = `${origin}/wp-content/themes/${encodeURIComponent(slug)}/style.css`
        const { ok, text, status } = await fetchText(cssUrl, scanSignal, 256_000)
        if (!ok) {
          return {
            slug,
            version: null,
            versionSource: null,
            versionError: status === 404 ? 'style_not_found' : 'style_fetch_failed',
          }
        }
        const version = parseStyleCssVersion(text)
        return {
          slug,
          version,
          versionSource: version ? 'style.css' : null,
          versionError: version ? undefined : 'version_header_not_found',
        }
      })

      const plugins = await batchMap(pluginVersions, BATCH_CONCURRENCY, async row => {
        const json = await fetchWpVulnerabilityJson(`/plugin/${encodeURIComponent(row.slug)}/`, scanSignal)
        const vulns = json?.data?.vulnerability
        const displayName = json?.data?.name ?? null
        const { cves, otherSources } = filterVulnsByVersion(vulns, row.version)
        return {
          slug: row.slug,
          version: row.version,
          versionSource: row.versionSource,
          displayName,
          cves,
          otherSources,
          vulnDbError: json ? null : 'wpvulnerability_unavailable',
          versionError: row.versionError ?? null,
          cveScanSkipped: !row.version,
        }
      })

      const themes = await batchMap(themeVersions, BATCH_CONCURRENCY, async row => {
        const json = await fetchWpVulnerabilityJson(`/theme/${encodeURIComponent(row.slug)}/`, scanSignal)
        const vulns = json?.data?.vulnerability
        const displayName = json?.data?.name ?? null
        const { cves, otherSources } = filterVulnsByVersion(vulns, row.version)
        return {
          slug: row.slug,
          version: row.version,
          versionSource: row.versionSource,
          displayName,
          cves,
          otherSources,
          vulnDbError: json ? null : 'wpvulnerability_unavailable',
          versionError: row.versionError ?? null,
          cveScanSkipped: !row.version,
        }
      })

      let core = null

      if (coreVersion) {
        const enc = encodeURIComponent(coreVersion)
        const json = await fetchWpVulnerabilityJson(`/core/${enc}/`, scanSignal)
        const vulns = json?.data?.vulnerability
        const merged = { cves: [], otherSources: [] }
        for (const v of vulns ?? []) {
          const { cves, otherSources } = partitionSources(v.source)
          for (const c of cves) merged.cves.push(c)
          for (const o of otherSources) merged.otherSources.push(o)
        }
        const cveMap = new Map(merged.cves.map(c => [c.id, c]))
        const otherMap = new Map(merged.otherSources.map(o => [o.id, o]))
        core = {
          version: coreVersion,
          cves: [...cveMap.values()],
          otherSources: [...otherMap.values()],
          vulnDbError: json ? null : 'wpvulnerability_unavailable',
        }
      } else {
        core = { version: null, cves: [], otherSources: [], vulnDbError: null }
      }

      const looksLikeWordPress =
        Boolean(coreVersion) || pluginSlugs.length > 0 || themeSlugs.length > 0 || /wp-content|wp-includes/i.test(html)

      return Response.json({
        source: 'wordpress_inspector',
        requestedUrl: url.toString(),
        finalUrl,
        looksLikeWordPress,
        core,
        plugins,
        themes,
        warnings,
        attribution: 'Vulnerability data: WPVulnerability (https://www.wpvulnerability.com/)',
      })
    } finally {
      clearTimeout(scanTimer)
    }
  } catch (err) {
    console.error('wordpress-inspector:', err)
    return Response.json({ error: 'Internal error while analyzing the WordPress site.' }, { status: 500 })
  }
}

export function registerWordpressInspector(registerRoute) {
  registerRoute('POST', '/api/tools/web/wordpress-inspector', handleWordpressInspector)
}
