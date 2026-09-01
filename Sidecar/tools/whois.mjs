// Ported from nimbus/app/api/tools/web/whois/route.ts, minus session/quota.
import { lookup } from 'whois'

function whoisLookup(domain) {
  return new Promise((resolve, reject) => {
    lookup(domain, { timeout: 10000 }, (err, data) => {
      if (err) return reject(err)
      resolve(data || '')
    })
  })
}

function parseWhoisRaw(raw) {
  const lines = raw.split(/\r?\n/)
  const result = {}
  for (const line of lines) {
    const match = line.match(/^([^:]+):\s*(.+)$/)
    if (match) {
      const key = match[1].trim()
      const value = match[2].trim()
      if (value && !key.startsWith('%') && key !== '>>>') {
        result[key] = value
      }
    }
  }
  return result
}

function extractDomain(input) {
  let s = input.trim().toLowerCase()
  s = s.replace(/^https?:\/\//, '')
  s = s.replace(/^www\./, '')
  s = s.split('/')[0]
  return s
}

async function handleWhois(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const input = data.get('domain')

  if (!input || typeof input !== 'string') {
    return Response.json(
      { error: 'Enter a domain or website (e.g. example.com or https://example.com).' },
      { status: 400 },
    )
  }

  const domain = extractDomain(input)
  if (!domain || !/^[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$/i.test(domain)) {
    return Response.json({ error: 'Invalid domain. Use a domain like example.com' }, { status: 400 })
  }

  try {
    const raw = await whoisLookup(domain)
    const parsed = parseWhoisRaw(raw)
    return Response.json({ domain, raw, parsed })
  } catch (error) {
    console.error('WHOIS error:', error)
    return Response.json(
      { error: "Couldn't look up WHOIS. Try another domain or try again later." },
      { status: 500 },
    )
  }
}

export function registerWhois(registerRoute) {
  registerRoute('POST', '/api/tools/web/whois', handleWhois)
}
