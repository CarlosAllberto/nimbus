import '../pdfNodeSetup.mjs'
import { configurePdfParseWorker } from '../configurePdfParseWorker.mjs'
import { documentTooLarge, MSG_DOCUMENT_TOO_LARGE } from '../uploadLimits.mjs'
import { GoogleGenAI } from '@google/genai'
import * as mammoth from 'mammoth'
import { PDFParse } from 'pdf-parse'

configurePdfParseWorker()

/** Gemma 4 primeiro (API Google AI); depois Gemini Flash como fallback. */
const COPY_GEMINI_MODELS = [
  'gemma-4-26b-a4b-it',
  'gemma-4-31b-it',
  'gemini-2.0-flash',
  'gemini-2.5-flash',
  'gemini-1.5-flash',
]

function isLikelyUnknownModelError(err) {
  const msg = String((err && err.message) || err)
  return /404|NOT_FOUND|not found|invalid model|is not supported|Unknown model/i.test(msg)
}

function errorMessageFromUnknown(err) {
  if (err instanceof Error && err.message.trim()) return err.message.trim()
  return String(err)
}

function isGeminiQuotaOrRateLimitError(err) {
  const status = (err && err.status) || (err && err.response && err.response.status)
  if (status === 429) return true
  const msg = errorMessageFromUnknown(err)
  return /RESOURCE_EXHAUSTED|quota exceeded|exceeded your current quota|rate limit|rate-limit|free_tier|GenerateRequestsPerMinute|PerDayPerProjectPerModel/i.test(
    msg,
  )
}

/**
 * Auth error heuristic for Gemini — checked before the quota branch so a
 * rejected key surfaces as 401, not 429/500.
 */
function isGeminiAuthError(err) {
  const status = (err && err.status) || (err && err.response && err.response.status)
  if (status === 401 || status === 403) return true
  const msg = errorMessageFromUnknown(err)
  return /API key not valid|API_KEY_INVALID|PERMISSION_DENIED|invalid[_ ]?api[_ ]?key|unauthorized/i.test(msg)
}

const MSG_GEMINI_QUOTA =
  'Gemini API limit reached (free-tier quota or too many requests per minute/day). Wait about a minute and try again. If this continues, check your quota and billing at https://ai.google.dev/gemini-api/docs/rate-limits'

const MSG_GEMINI_AUTH_REJECTED = 'Your Gemini API key was rejected. Check the key in Preferences.'

const MSG_NO_BRIEFING = 'Add a briefing file or describe the site to continue.'

const MSG_UNSUPPORTED_FILE = 'Unsupported file format. Use .txt, .docx, or .pdf.'

const MSG_PDF_NO_TEXT =
  "Couldn't extract text from this PDF. Scanned image-only PDFs have no selectable text — use a PDF with text, or a .txt/.docx file instead."

const MSG_PDF_READ_ERROR =
  "Couldn't read the PDF. The file may be corrupted or password-protected."

const MSG_INVALID_PAGES_JSON = 'Invalid page structure (JSON).'

const MSG_PAGES_NOT_LIST = 'Page structure must be a list.'

const MSG_NO_PAGES = 'No page structure configured.'

const MSG_COPY_FAILED_FALLBACK = "Couldn't generate the copy. Try again shortly."

const MSG_COPY_FAILED_DETAIL = `Couldn't generate the copy.`

export async function handleCopyGenerator(request) {
  const apiKey = process.env.GEMINI_API_KEY?.trim()
  if (!apiKey) {
    return Response.json(
      { error: 'Add your Gemini API key in Preferences to use this tool.' },
      { status: 503 },
    )
  }

  const ai = new GoogleGenAI({ apiKey })

  try {
    const data = await request.formData()
    const dataFile = data.get('file')
    const siteDescriptionRaw = data.get('siteDescription')
    const copyObservationsRaw = data.get('copyObservations')
    const pagesConfigRaw = data.get('pagesConfig')

    if (!pagesConfigRaw) {
      return Response.json({ error: MSG_NO_PAGES }, { status: 400 })
    }

    let briefingText = ''
    const siteDescription =
      typeof siteDescriptionRaw === 'string' ? siteDescriptionRaw.trim() : ''
    const copyObservations =
      typeof copyObservationsRaw === 'string' ? copyObservationsRaw.trim() : ''
    const hasBriefingFile = dataFile instanceof File

    if (!hasBriefingFile && !siteDescription) {
      return Response.json({ error: MSG_NO_BRIEFING }, { status: 400 })
    }

    if (hasBriefingFile) {
      if (documentTooLarge(dataFile.size)) {
        return Response.json({ error: MSG_DOCUMENT_TOO_LARGE }, { status: 413 })
      }

      const lowerName = dataFile.name.toLowerCase()
      const isPdf = lowerName.endsWith('.pdf') || dataFile.type === 'application/pdf'

      if (lowerName.endsWith('.txt')) {
        briefingText = await dataFile.text()
      } else if (lowerName.endsWith('.docx')) {
        const buffer = Buffer.from(await dataFile.arrayBuffer())
        const result = await mammoth.extractRawText({ buffer })
        briefingText = result.value
      } else if (isPdf) {
        const buffer = Buffer.from(await dataFile.arrayBuffer())
        const parser = new PDFParse({ data: new Uint8Array(buffer) })
        try {
          const result = await parser.getText()
          briefingText = (result.text ?? '').trim()
          if (!briefingText) {
            return Response.json({ error: MSG_PDF_NO_TEXT }, { status: 400 })
          }
        } catch (pdfErr) {
          console.error('PDF parse error:', pdfErr?.message ?? String(pdfErr))
          return Response.json({ error: MSG_PDF_READ_ERROR }, { status: 400 })
        } finally {
          await parser.destroy().catch(() => {})
        }
      } else {
        return Response.json({ error: MSG_UNSUPPORTED_FILE }, { status: 400 })
      }
    } else {
      briefingText = siteDescription
    }

    let pagesConfig
    try {
      pagesConfig = JSON.parse(pagesConfigRaw.toString())
    } catch {
      return Response.json({ error: MSG_INVALID_PAGES_JSON }, { status: 400 })
    }
    if (!Array.isArray(pagesConfig)) {
      return Response.json({ error: MSG_PAGES_NOT_LIST }, { status: 400 })
    }

    let generatedCopyText = ''
    let lastModelError
    for (const model of COPY_GEMINI_MODELS) {
      try {
        const response = await ai.models.generateContent({
          model,
          contents: buildFinalPrompt({
            systemPrompt: SYSTEM_PROMPT,
            contextLabel: hasBriefingFile
              ? 'ARQUIVO DE BRIEFING DO CLIENTE'
              : 'DESCRIÇÃO DO SITE INFORMADA PELO USUÁRIO',
            briefingText,
            structurePrompt: buildStructurePrompt(pagesConfig),
            observationsBlock: copyObservations,
          }),
        })
        generatedCopyText = (response.text ?? '').trim()
        if (!generatedCopyText) {
          const pf = response.promptFeedback
          if (pf && pf.blockReason) {
            return Response.json(
              {
                error: `Generation was blocked by the safety filter (${pf.blockReason}). Adjust the briefing or description and try again.`,
              },
              { status: 422 },
            )
          }
          lastModelError = new Error('The AI returned an empty response.')
          continue
        }
        break
      } catch (err) {
        lastModelError = err
        if (isGeminiAuthError(err)) {
          return Response.json({ error: MSG_GEMINI_AUTH_REJECTED }, { status: 401 })
        }
        if (isGeminiQuotaOrRateLimitError(err)) {
          return Response.json({ error: MSG_GEMINI_QUOTA }, { status: 429 })
        }
        if (isLikelyUnknownModelError(err)) continue
        throw err
      }
    }

    if (!generatedCopyText) {
      const detail = lastModelError ? errorMessageFromUnknown(lastModelError) : 'No model available.'
      return Response.json(
        {
          error: `${MSG_COPY_FAILED_DETAIL} ${detail}`,
        },
        { status: 502 },
      )
    }

    // Split the response into individual pages using the delimiter
    const pageBlocks = generatedCopyText.split(/===PAGE:\s*/i).filter(Boolean)
    const pages = pageBlocks.map(block => {
      const endOfTitle = block.indexOf('===')
      const title = endOfTitle !== -1 ? block.substring(0, endOfTitle).trim() : 'pagina'
      const content = endOfTitle !== -1 ? block.substring(endOfTitle + 3).trim() : block.trim()
      return { title, content }
    })

    return Response.json({ pages }, { status: 200 })
  } catch (err) {
    console.error('Error generating copy:', err?.message ?? String(err))
    if (isGeminiAuthError(err)) {
      return Response.json({ error: MSG_GEMINI_AUTH_REJECTED }, { status: 401 })
    }
    if (isGeminiQuotaOrRateLimitError(err)) {
      return Response.json({ error: MSG_GEMINI_QUOTA }, { status: 429 })
    }
    const msg = errorMessageFromUnknown(err)
    return Response.json(
      {
        error:
          msg.length > 280
            ? `${msg.slice(0, 277)}…`
            : msg || MSG_COPY_FAILED_FALLBACK,
      },
      { status: 500 },
    )
  }
}

const SYSTEM_PROMPT = `Você é um especialista em Copywriting e UX Writing de alta conversão para Landing Pages e Sites.
O usuário fornece um briefing (arquivo) ou uma descrição curta do site.

Seu objetivo é gerar toda a copy da estrutura solicitada, com tom adequado, CTAs eficientes e textos persuasivos.
Não invente informações falsas; pode usar técnicas de copy para valorizar o que existe no briefing/descrição.

FORMATO DE SAÍDA OBRIGATÓRIO (texto puro .txt):

1) Separe CADA PÁGINA com o delimitador exato no início da página:
   ===PAGE: Nome da Página===

2) Dentro de cada página, cada seção segue ESTA ordem (não inverta):
   - Linha com # e o NOME DA SEÇÃO em MAIÚSCULAS (ex.: # HERO). Use só # para o cabeçalho da seção; sem markdown pesado (** , listas longas numeradas, etc.).
   - Linha em branco OBRIGATÓRIA após a linha # SEÇÃO (nunca cole "Título:" na mesma linha nem grude o título da seção no divisor de hífens).
   - Depois, identifique a copy de interface:
     Título: ...
     Subtulo: ...
     CTA: [...]  (use CTA: [—] se não houver botão)
   - Textos extras com rótulos em linha própria: Texto:, Item 1:, Pergunta:/Resposta:, etc.
   - Elementos não-copy entre colchetes: [carrossel de imagens], [galeria de fotos], etc.

3) Divisor entre seções (linha com mínimo 17 hífens: -----------------):
   - NUNCA coloque ----------------- ACIMA da PRIMEIRA seção da página (não há conteúdo antes dela).
   - Coloque ----------------- DEPOIS do conteúdo completo de uma seção e ANTES da próxima.
   - Entre o fim do conteúdo da seção e a linha ----------------- pode haver no máximo uma linha em branco.
   - Depois da linha ----------------- deve haver UMA linha em branco e só então a linha # PRÓXIMA_SEÇÃO (o nome da seção nunca fica colado ao divisor).
   - Na ÚLTIMA seção da página, NÃO coloque ----------------- no final (nada abaixo).

Exemplo (estrutura exata; adapte textos):

# HERO

Titulo: exemplo
Subtitulo: exemplo

CTA: [exemplo]

-----------------

# SOBRE NÓS

Titulo: exemplo
Texto: exemplo

-----------------

# CONTATO

Titulo: exemplo
CTA: [exemplo]

Não omita "Titulo:", "Subtitulo:" e "CTA:" quando fizer sentido; use "—" ou CTA: [—] quando não existir.
`

function buildStructurePrompt(pagesConfig) {
  let prompt = 'ESTRUTURA SOLICITADA PARA O SITE:\n\n'
  pagesConfig.forEach(page => {
    prompt += `PÁGINA: ${page.title || 'Página'}\n`
    prompt += `SEÇÕES DESEJADAS: ${page.sections ?? ''}\n\n`
  })
  return prompt
}

function buildFinalPrompt(parts) {
  const observationsBlock = parts.observationsBlock
    ? `

-----------------------------------------

      OBSERVAÇÕES / RESTRIÇÕES DO CLIENTE (respeite rigorosamente quando fizer sentido; não invente novas restrições além das listadas):
      ${parts.observationsBlock}
`
    : ''

  return `
${parts.systemPrompt}

-----------------------------------------

${parts.contextLabel}:
${parts.briefingText}

-----------------------------------------

${parts.structurePrompt}
${observationsBlock}
      
Por favor, gere agora a copy completa seguindo a estrutura de páginas e seções pedidas.
Obrigatório: ===PAGE: Nome=== no início de cada página; primeira seção começa direto com # SEM ----------------- acima; após cada seção (exceto a última) use -----------------, linha em branco e então # próxima seção; linha em branco após cada # antes de Título:.
`
}

export function registerCopyGenerator(registerRoute) {
  registerRoute('POST', '/api/tools/web/copy-generator', handleCopyGenerator)
}
