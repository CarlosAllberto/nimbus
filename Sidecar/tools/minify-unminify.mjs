// Ported from nimbus/app/api/tools/code/minify-unminify/route.ts, minus
// session/quota. Regex-based minify/unminify, verbatim from the site.
const INLINE_TAGS = [
  'a', 'span', 'b', 'strong', 'i', 'em', 'img', 'br', 'button', 'input',
  'label', 'small', 'sub', 'sup', 'code', 'q', 'svg', 'path',
]
const BLOCK_TEXT_TAGS = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'title', 'td', 'th', 'li']
const NO_BREAK_TAGS = new Set([...INLINE_TAGS, ...BLOCK_TEXT_TAGS])

function minifyHtml(html) {
  return html
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/>\s+</g, '><')
    .replace(/\s{2,}/g, ' ')
    .replace(/[\r\n]+/g, '')
    .trim()
}

function unminifyHtml(html) {
  let formatted = ''
  let indentLevel = 0
  const cleanHtml = html.replace(/>\s+</g, '><')

  const tokens = cleanHtml.split(/(<\/?[^>]+>)/g).filter(t => t !== '')
  let noBreakDepth = 0

  for (let i = 0; i < tokens.length; i++) {
    const rawToken = tokens[i]
    const isTag = /^<\/?[^>]+>$/.test(rawToken.trim())

    if (isTag) {
      const token = rawToken.trim()
      const isClosing = /^<\//.test(token)
      const isSelfClosing =
        /<[^>]+\/>$/.test(token) ||
        /<(img|br|hr|input|meta|link|base|col|embed|param|source|track|wbr)[^>]*>/i.test(token)
      const isDoctypeOrComment = /^<!/.test(token) || /^<\?/.test(token)

      let tagName = ''
      const match = token.match(/<\/?([a-zA-Z0-9\-]+)/)
      if (match) tagName = match[1].toLowerCase()

      if (isClosing) {
        if (NO_BREAK_TAGS.has(tagName)) {
          noBreakDepth = Math.max(0, noBreakDepth - 1)
        }
        if (noBreakDepth === 0 && !NO_BREAK_TAGS.has(tagName)) {
          indentLevel = Math.max(0, indentLevel - 1)
          formatted += '\n' + '\t'.repeat(indentLevel) + token
        } else {
          formatted += token
        }
      } else {
        if (noBreakDepth === 0) {
          if (formatted) formatted += '\n' + '\t'.repeat(indentLevel)
          formatted += token
          if (NO_BREAK_TAGS.has(tagName)) {
            noBreakDepth++
          } else if (!isSelfClosing && !isDoctypeOrComment) {
            indentLevel++
          }
        } else {
          formatted += token
          if (NO_BREAK_TAGS.has(tagName) && !isSelfClosing && !isDoctypeOrComment) {
            noBreakDepth++
          }
        }
      }
    } else {
      if (rawToken.trim() === '') {
        if (noBreakDepth > 0 && formatted && !formatted.endsWith(' ')) {
          formatted += ' '
        }
        continue
      }
      let text = rawToken.replace(/\s+/g, ' ')
      if (noBreakDepth === 0) {
        formatted += '\n' + '\t'.repeat(indentLevel) + text.trim()
      } else {
        formatted += text
      }
    }
  }

  return formatted.trim()
}

async function handleHtmlMinify(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const html = data.get('html')
  const action = data.get('action')

  if (!html || typeof html !== 'string') {
    return Response.json(
      { error: 'HTML code is required and must be a valid string.' },
      { status: 400 },
    )
  }
  if (!action || !['minify', 'unminify'].includes(action)) {
    return Response.json(
      { error: 'Invalid action. Must be "minify" or "unminify".' },
      { status: 400 },
    )
  }

  try {
    const result = action === 'minify' ? minifyHtml(html) : unminifyHtml(html)
    return Response.json({ result }, { status: 200 })
  } catch (error) {
    console.error('Error in minify-unminify API:', error)
    return Response.json({ error: 'Internal server error. Could not process HTML.' }, { status: 500 })
  }
}

export function registerHtmlMinify(registerRoute) {
  registerRoute('POST', '/api/tools/code/minify-unminify', handleHtmlMinify)
}
