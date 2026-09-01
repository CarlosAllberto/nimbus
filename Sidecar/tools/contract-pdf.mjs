// Ported from nimbus/app/api/tools/tools/contract-pdf/route.ts, minus the
// JSON body read (sidecar reads formData) and minus session/quota. The
// `contractFields` field arrives as a JSON STRING (the Swift side serializes
// 14 fields with JSONEncoder); we explicitly JSON.parse it before any use,
// including the localData fallback. PDF rendering is ported 1:1 with
// pdf-lib. User-facing strings translated to English; generated contract
// content stays in PT-BR per the rules.
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib'
import { GoogleGenAI } from '@google/genai'

const PAGE_WIDTH = 595
const PAGE_HEIGHT = 842
const MARGIN_TOP = 56
const MARGIN_BOTTOM = 56
const MARGIN_SIDE = 52
const LINE_HEIGHT = 17
const TITLE_SIZE = 20
const SECTION_SIZE = 12
const BODY_SIZE = 11
const SIGNATURE_LABEL_SIZE = 10
const HEADER_LINE_Y = PAGE_HEIGHT - 36
const HEADER_NIMBUS_Y = PAGE_HEIGHT - 28
const GRAY_900 = { r: 0.12, g: 0.12, b: 0.14 }
const GRAY_600 = { r: 0.35, g: 0.35, b: 0.38 }
const GRAY_400 = { r: 0.5, g: 0.5, b: 0.52 }
const GRAY_100 = { r: 0.96, g: 0.96, b: 0.97 }
/** Model candidates tried in order. The previous port hardcoded
 * `gemini-2.5-flash` (faithful to the Next route's line 161), but that model
 * is no longer accepting requests from new API keys as of 2026-09-01 — the
 * Google API returns 404 NOT_FOUND for it. The copy-generator already uses
 * a list with fallback (`COPY_GEMINI_MODELS`); same pattern here so the
 * contract tool doesn't die the next time Google retires a model. Order
 * reflects Google's own recommendation surfaced in the 404 message, then
 * the previously known-good names. */
const CONTRACT_GEMINI_MODELS = [
  'gemini-3.6-flash',
  'gemini-flash-latest',
  'gemini-2.5-flash',
  'gemini-2.0-flash',
  'gemini-1.5-flash',
]

function isLikelyUnknownModelError(err) {
  const msg = String((err && err.message) || err)
  return /404|NOT_FOUND|not found|invalid model|is not supported|Unknown model/i.test(msg)
}

function isGeminiAuthError(err) {
  const status = (err && err.status) || (err && err.response && err.response.status)
  if (status === 401 || status === 403) return true
  const msg = err instanceof Error && err.message ? err.message : String(err)
  return /API key not valid|API_KEY_INVALID|PERMISSION_DENIED|invalid[_ ]?api[_ ]?key|unauthorized/i.test(msg)
}

const TITLE_MAX_WIDTH_PT = PAGE_WIDTH - 2 * MARGIN_SIDE

function wrapText(text, maxCharsPerLine) {
  const lines = []
  const paragraphs = text.split(/\n\n+/)
  for (const para of paragraphs) {
    const trimmed = para.trim()
    if (!trimmed) {
      lines.push('')
      continue
    }
    const words = trimmed.split(/\s+/)
    let current = ''
    for (const word of words) {
      const next = current ? `${current} ${word}` : word
      if (next.length <= maxCharsPerLine) {
        current = next
      } else {
        if (current) lines.push(current)
        current = word.length > maxCharsPerLine ? word : word
      }
    }
    if (current) lines.push(current)
    lines.push('')
  }
  return lines
}

function isSectionHeader(line) {
  const t = line.trim().toUpperCase()
  return (
    t.startsWith('DO ') ||
    t.startsWith('DA ') ||
    t.startsWith('DAS ') ||
    /^CLÁUSULA\s+\d+ª?\s*:?/i.test(t) ||
    /^CONTRATANTE\s*:?/i.test(t) ||
    /^CONTRATADA\s*:?/i.test(t)
  )
}

function wrapTitleByWidth(title, maxWidthPt, font, size) {
  const trimmed = title.trim()
  if (!trimmed) return ['']
  const words = trimmed.split(/\s+/)
  const lines = []
  let current = ''
  for (const word of words) {
    const toTry = current ? `${current} ${word}` : word
    const w = font.widthOfTextAtSize(toTry, size)
    if (w <= maxWidthPt) {
      current = toTry
      continue
    }
    if (current) lines.push(current)
    if (font.widthOfTextAtSize(word, size) <= maxWidthPt) {
      current = word
    } else {
      for (let i = 0; i < word.length; i++) {
        const chunk = word[i]
        const candidate = current + chunk
        if (font.widthOfTextAtSize(candidate, size) <= maxWidthPt) {
          current = candidate
        } else {
          if (current) lines.push(current)
          current = chunk
        }
      }
    }
  }
  if (current) lines.push(current)
  return lines
}

function isLikelyAuthError(message) {
  return /API key not valid|API_KEY_INVALID|PERMISSION_DENIED|invalid[_ ]?api[_ ]?key|unauthorized/i.test(
    message || '',
  )
}

const MSG_GEMINI_AUTH_REJECTED = 'Your Gemini API key was rejected. Check the key in Preferences.'

async function generateContractWithGemini(ai, fields) {
  const lines = []
  lines.push('Dados do CONTRATANTE (cliente) — use APENAS os que estiverem preenchidos:')
  if (fields.nome) lines.push(`- Nome: ${fields.nome}`)
  if (fields.cpf) lines.push(`- CPF: ${fields.cpf}`)
  if (fields.email) lines.push(`- Email: ${fields.email}`)
  if (fields.telefone) lines.push(`- Telefone: ${fields.telefone}`)
  if (fields.endereco) lines.push(`- Endereço: ${fields.endereco}`)
  lines.push('')
  lines.push('Dados da CONTRATADA (prestador) — use APENAS os que estiverem preenchidos:')
  if (fields.razaoSocialContratada) lines.push(`- Razão social: ${fields.razaoSocialContratada}`)
  if (fields.cnpjContratada) lines.push(`- CNPJ: ${fields.cnpjContratada}`)
  if (fields.enderecoContratada) lines.push(`- Endereço: ${fields.enderecoContratada}`)
  lines.push('')
  lines.push('Dados do serviço:')
  if (fields.tipoServico) lines.push(`- Tipo de serviço: ${fields.tipoServico}`)
  if (fields.prazo) lines.push(`- Prazo: ${fields.prazo}`)
  if (fields.valor) lines.push(`- Valor total: ${fields.valor}`)
  if (fields.cidadeForo || fields.ufForo)
    lines.push(`- Foro: ${[fields.cidadeForo, fields.ufForo].filter(Boolean).join('-')}`)

  const prompt = `Você é um redator jurídico. Gere um CONTRATO DE PRESTAÇÃO DE SERVIÇOS em português do Brasil, em texto puro.

REGRAS OBRIGATÓRIAS:
- Inclua no contrato SOMENTE os dados que foram listados abaixo. NÃO use placeholders como [nome], [CPF], [a preencher], etc.
- Se um dado não foi fornecido, omita essa parte da frase ou use redação genérica (ex.: "valor a ser combinado entre as partes" se valor não foi informado; "conforme combinado" para prazos não detalhados).
- Na identificação das partes, escreva apenas os itens que aparecem na lista (ex.: se só tem Nome e Email, escreva só isso para o CONTRATANTE).

${lines.join('\n')}

INSTRUÇÕES DE FORMATO:
1. Primeira linha do seu texto = TÍTULO EM MAIÚSCULAS (ex: CONTRATO DE PRESTAÇÃO DE SERVIÇOS DE [tipo informado]). Título curto, em uma linha.
2. Depois da primeira linha, pule duas linhas e escreva o conteúdo completo.
3. Conteúdo: identificação CONTRATANTE e CONTRATADA (só com os dados fornecidos), preâmbulo, cláusulas (Objeto, Valor e forma de pagamento, Prazo, Etapas, Conteúdo e alterações, Cancelamento e reembolso, Disposições finais). Use CLÁUSULA 1ª, 2ª, etc.
4. Se valor foi informado, escreva por extenso (ex.: R$ 1.500,00 = mil e quinhentos reais). Se não, use "valor a ser combinado entre as partes".
5. Apenas texto puro, parágrafos separados por linha em branco. Sem markdown.
6. Não inclua no texto o bloco de assinaturas (local e data, CONTRATANTE/CONTRATADO).`

  let lastError = null
  for (const model of CONTRACT_GEMINI_MODELS) {
    try {
      const res = await ai.models.generateContent({ model, contents: prompt })
      const text = (res.text || '').trim()
      const firstLine = text.split('\n')[0]?.trim() || 'Contrato'
      const rest = text.slice(firstLine.length).replace(/^\n+/, '').trim()
      return { title: firstLine, content: rest || text }
    } catch (err) {
      // Never log the full error object — the Gemini SDK can embed request
      // config (including the API key in headers) into the error.
      const msg = err instanceof Error && err.message ? err.message : String(err)
      lastError = err
      if (isGeminiAuthError(err)) {
        // Surface as auth error so the caller renders the 401 with the key
        // message instead of a generic 502.
        const e = new Error(MSG_GEMINI_AUTH_REJECTED)
        e.__nimbusAuth = true
        throw e
      }
      if (isLikelyUnknownModelError(err)) {
        // Try the next candidate model. Log only the model name + message
        // string, never the error object.
        console.error(`Gemini contract: model ${model} unavailable — ${msg}`)
        continue
      }
      // Any other failure: stop trying, let the caller render a generic
      // generation-failed error that does not blame the key.
      throw err
    }
  }
  throw lastError || new Error('No Gemini model available')
}

async function handleContractPDF(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  let title = 'Contrato'
  let content = ''
  const signerLabel = 'Assinatura do contratado'
  const dateLabel = 'Data'
  const nameLabel = 'Nome completo'
  let datePlace = ''
  let signer1Label = data.get('signer1Label') || ''
  let signer2Label = data.get('signer2Label') || ''

  const contractFieldsRaw = data.get('contractFields')
  if (typeof contractFieldsRaw === 'string' && contractFieldsRaw.length > 0) {
    let contractFields
    try {
      contractFields = JSON.parse(contractFieldsRaw)
    } catch {
      return Response.json({ error: 'Invalid contract data (JSON).' }, { status: 400 })
    }
    if (contractFields && typeof contractFields === 'object') {
      const apiKey = process.env.GEMINI_API_KEY?.trim()
      if (!apiKey) {
        return Response.json(
          { error: 'Add your Gemini API key in Preferences to use this tool.' },
          { status: 503 },
        )
      }
      const ai = new GoogleGenAI({ apiKey })
      try {
        const generated = await generateContractWithGemini(ai, contractFields)
        title = generated.title
        content = generated.content
        if (!datePlace && contractFields.localData) datePlace = contractFields.localData
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e)
        if (e && e.__nimbusAuth) {
          return Response.json(
            { error: MSG_GEMINI_AUTH_REJECTED },
            { status: 401 },
          )
        }
        if (isLikelyAuthError(msg)) {
          return Response.json(
            { error: MSG_GEMINI_AUTH_REJECTED },
            { status: 401 },
          )
        }
        // Log only the message string, never the full error (the SDK can
        // embed request config incl. headers into the error object).
        console.error('Gemini contract generation:', msg)
        return Response.json(
          { error: "Couldn't generate the contract text. Check that the Gemini API key is configured." },
          { status: 502 },
        )
      }
    }
  }

  const twoSigners = Boolean(signer1Label && signer2Label)

  const doc = await PDFDocument.create()
  const font = await doc.embedFont(StandardFonts.Helvetica)
  const fontBold = await doc.embedFont(StandardFonts.HelveticaBold)

  const contentWidth = PAGE_WIDTH - 2 * MARGIN_SIDE
  const maxCharsPerLine = Math.floor(contentWidth / (BODY_SIZE * 0.6))
  const contentLines = wrapText(content || 'Conteúdo do contrato não informado.', maxCharsPerLine)

  const drawPageFooter = (p, pageNum) => {
    const footerY = MARGIN_BOTTOM - 14
    p.drawText(`${pageNum}`, {
      x: PAGE_WIDTH / 2 - 4,
      y: footerY,
      size: 9,
      font,
      color: rgb(GRAY_400.r, GRAY_400.g, GRAY_400.b),
    })
    const nimbusText = 'Nimbus'
    const nimbusW = font.widthOfTextAtSize(nimbusText, 7)
    p.drawText(nimbusText, {
      x: PAGE_WIDTH / 2 - nimbusW / 2,
      y: footerY - 12,
      size: 7,
      font,
      color: rgb(0.72, 0.72, 0.74),
    })
  }

  const drawHeaderBranding = (p) => {
    const nimbusText = 'Nimbus'
    const brandW = font.widthOfTextAtSize(nimbusText, 8)
    p.drawText(nimbusText, {
      x: PAGE_WIDTH - MARGIN_SIDE - brandW,
      y: HEADER_NIMBUS_Y,
      size: 8,
      font,
      color: rgb(0.72, 0.72, 0.74),
    })
  }

  let page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT])
  let pageNum = 1
  let y = PAGE_HEIGHT - MARGIN_TOP

  drawHeaderBranding(page)
  page.drawLine({
    start: { x: MARGIN_SIDE, y: HEADER_LINE_Y },
    end: { x: PAGE_WIDTH - MARGIN_SIDE, y: HEADER_LINE_Y },
    thickness: 1,
    color: rgb(GRAY_400.r, GRAY_400.g, GRAY_400.b),
  })
  y -= 20

  const titleLines = wrapTitleByWidth(title, TITLE_MAX_WIDTH_PT, fontBold, TITLE_SIZE)
  for (const line of titleLines) {
    page.drawText(line || ' ', {
      x: MARGIN_SIDE,
      y,
      size: TITLE_SIZE,
      font: fontBold,
      color: rgb(GRAY_900.r, GRAY_900.g, GRAY_900.b),
    })
    y -= TITLE_SIZE + 5
  }
  y -= 4
  page.drawLine({
    start: { x: MARGIN_SIDE, y },
    end: { x: MARGIN_SIDE + 80, y },
    thickness: 1.2,
    color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
  })
  y -= 20

  for (const line of contentLines) {
    if (y < MARGIN_BOTTOM + 100) {
      drawPageFooter(page, pageNum)
      page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT])
      pageNum += 1
      y = PAGE_HEIGHT - MARGIN_TOP
      drawHeaderBranding(page)
      page.drawLine({
        start: { x: MARGIN_SIDE, y: HEADER_LINE_Y },
        end: { x: PAGE_WIDTH - MARGIN_SIDE, y: HEADER_LINE_Y },
        thickness: 1,
        color: rgb(GRAY_400.r, GRAY_400.g, GRAY_400.b),
      })
      y -= 20
    }
    const isHeader = line.trim() && isSectionHeader(line)
    page.drawText(line || ' ', {
      x: MARGIN_SIDE,
      y,
      size: isHeader ? SECTION_SIZE : BODY_SIZE,
      font: isHeader ? fontBold : font,
      color: rgb(GRAY_900.r, GRAY_900.g, GRAY_900.b),
    })
    y -= isHeader ? LINE_HEIGHT + 2 : LINE_HEIGHT
  }

  y -= 28
  if (y < MARGIN_BOTTOM + 160) {
    drawPageFooter(page, pageNum)
    page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT])
    pageNum += 1
    y = PAGE_HEIGHT - MARGIN_TOP
    drawHeaderBranding(page)
    page.drawLine({
      start: { x: MARGIN_SIDE, y: HEADER_LINE_Y },
      end: { x: PAGE_WIDTH - MARGIN_SIDE, y: HEADER_LINE_Y },
      thickness: 1,
      color: rgb(GRAY_400.r, GRAY_400.g, GRAY_400.b),
    })
    y -= 20
  }

  const lineLength = 220
  const lineStart = PAGE_WIDTH - MARGIN_SIDE - lineLength
  const sigBlockPadding = 14
  const sigBlockY = y + 8

  if (twoSigners) {
    const blockHeight = datePlace ? 130 : 100
    page.drawRectangle({
      x: lineStart - sigBlockPadding,
      y: sigBlockY - blockHeight,
      width: lineLength + 2 * sigBlockPadding,
      height: blockHeight,
      color: rgb(GRAY_100.r, GRAY_100.g, GRAY_100.b),
      borderColor: rgb(GRAY_400.r, GRAY_400.g, GRAY_400.b),
      borderWidth: 0.5,
    })
    if (datePlace) {
      page.drawText(datePlace, {
        x: MARGIN_SIDE,
        y,
        size: SIGNATURE_LABEL_SIZE,
        font,
        color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
      })
      y -= 28
    }
    const block1Y = y
    page.drawLine({
      start: { x: lineStart, y: block1Y - 4 },
      end: { x: lineStart + lineLength, y: block1Y - 4 },
      thickness: 1,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    page.drawText(signer1Label, {
      x: lineStart,
      y: block1Y - 18,
      size: SIGNATURE_LABEL_SIZE,
      font,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    y -= 48
    const block2Y = y
    page.drawLine({
      start: { x: lineStart, y: block2Y - 4 },
      end: { x: lineStart + lineLength, y: block2Y - 4 },
      thickness: 1,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    page.drawText(signer2Label, {
      x: lineStart,
      y: block2Y - 18,
      size: SIGNATURE_LABEL_SIZE,
      font,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
  } else {
    const blockHeight = 100
    page.drawRectangle({
      x: lineStart - sigBlockPadding,
      y: sigBlockY - blockHeight,
      width: lineLength + 2 * sigBlockPadding,
      height: blockHeight,
      color: rgb(GRAY_100.r, GRAY_100.g, GRAY_100.b),
      borderColor: rgb(GRAY_400.r, GRAY_400.g, GRAY_400.b),
      borderWidth: 0.5,
    })
    const signatureBlockY = y
    const lineY = signatureBlockY - 8

    page.drawText(signerLabel, {
      x: lineStart,
      y: signatureBlockY + 4,
      size: SIGNATURE_LABEL_SIZE,
      font,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    page.drawLine({
      start: { x: lineStart, y: lineY },
      end: { x: lineStart + lineLength, y: lineY },
      thickness: 1,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    const dataY = lineY - 26
    page.drawText(dateLabel, {
      x: lineStart,
      y: dataY + 14,
      size: SIGNATURE_LABEL_SIZE,
      font,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    page.drawLine({
      start: { x: lineStart, y: dataY },
      end: { x: lineStart + lineLength, y: dataY },
      thickness: 1,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    const nameY = dataY - 26
    page.drawText(nameLabel, {
      x: lineStart,
      y: nameY + 14,
      size: SIGNATURE_LABEL_SIZE,
      font,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
    page.drawLine({
      start: { x: lineStart, y: nameY },
      end: { x: lineStart + lineLength, y: nameY },
      thickness: 1,
      color: rgb(GRAY_600.r, GRAY_600.g, GRAY_600.b),
    })
  }

  drawPageFooter(page, pageNum)

  const pdfBytes = await doc.save()

  return new Response(pdfBytes, {
    status: 200,
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': 'attachment; filename="contrato.pdf"',
    },
  })
}

export function registerContractPDF(registerRoute) {
  registerRoute('POST', '/api/tools/tools/contract-pdf', handleContractPDF)
}
