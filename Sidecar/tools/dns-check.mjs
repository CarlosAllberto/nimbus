// Ported from nimbus/app/api/tools/web/dns-check/route.ts, minus session/quota.
// DNS_TYPES adds CAA on top of the original list — the Swift picker already
// offers it, and DNS-over-HTTPS (record type 257) supports it fine.
const DNS_TYPES = ['A', 'AAAA', 'MX', 'NS', 'TXT', 'CNAME', 'SOA', 'CAA']

const TYPE_MAP = {
  1: 'A',
  2: 'NS',
  5: 'CNAME',
  6: 'SOA',
  15: 'MX',
  16: 'TXT',
  28: 'AAAA',
  257: 'CAA',
}

function normalizeDomain(input) {
  let s = input.trim().toLowerCase()
  s = s.replace(/^https?:\/\//, '')
  s = s.replace(/^www\./, '')
  s = s.split('/')[0]
  if (s && !s.endsWith('.')) s += '.'
  return s
}

function parseAnswer(item) {
  return {
    name: (item.name || '').replace(/\.$/, ''),
    type: TYPE_MAP[item.type ?? 0] ?? String(item.type),
    ttl: item.TTL ?? 0,
    data: item.data ?? '',
  }
}

async function queryGoogle(domain, type) {
  const url = `https://dns.google/resolve?name=${encodeURIComponent(domain)}&type=${encodeURIComponent(type)}`
  try {
    const res = await fetch(url)
    const data = await res.json()
    const answers = (data.Answer || []).map(parseAnswer)
    return { provider: 'Google DNS', server: '8.8.8.8', status: 'ok', answers }
  } catch (e) {
    return {
      provider: 'Google DNS',
      server: '8.8.8.8',
      status: 'error',
      answers: [],
      error: e instanceof Error ? e.message : 'Query failed',
    }
  }
}

async function queryCloudflare(domain, type) {
  const url = `https://cloudflare-dns.com/dns-query?name=${encodeURIComponent(domain)}&type=${encodeURIComponent(type)}`
  try {
    const res = await fetch(url, { headers: { Accept: 'application/dns-json' } })
    const data = await res.json()
    const answers = (data.Answer || []).map(parseAnswer)
    return { provider: 'Cloudflare', server: '1.1.1.1', status: 'ok', answers }
  } catch (e) {
    return {
      provider: 'Cloudflare',
      server: '1.1.1.1',
      status: 'error',
      answers: [],
      error: e instanceof Error ? e.message : 'Query failed',
    }
  }
}

async function handleDnsCheck(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const input = data.get('domain')
  const type = data.get('type') || 'A'

  if (!input || typeof input !== 'string') {
    return Response.json({ error: 'Enter a domain (e.g. example.com).' }, { status: 400 })
  }

  const domain = normalizeDomain(input)
  if (!domain || domain === '.') {
    return Response.json({ error: 'Invalid domain.' }, { status: 400 })
  }

  const typeStr = String(type).toUpperCase()
  if (!DNS_TYPES.includes(typeStr)) {
    return Response.json({ error: `Invalid type. Use: ${DNS_TYPES.join(', ')}` }, { status: 400 })
  }

  try {
    const [googleResult, cloudflareResult] = await Promise.all([
      queryGoogle(domain, typeStr),
      queryCloudflare(domain, typeStr),
    ])

    return Response.json({
      domain: domain.replace(/\.$/, ''),
      type: typeStr,
      results: [googleResult, cloudflareResult],
    })
  } catch (error) {
    console.error('DNS check error:', error)
    return Response.json({ error: "Couldn't check DNS. Try again later." }, { status: 500 })
  }
}

export function registerDnsCheck(registerRoute) {
  registerRoute('POST', '/api/tools/web/dns-check', handleDnsCheck)
}
