// Ported from nimbus/app/api/tools/tools/font-convert/route.ts, using
// verifyFont.mjs (ported from app/utils/verifyFont.ts) for detection and
// conversion, minus session/Supabase/quota (no auth in this version).
import { fontTooLarge, MSG_FONT_TOO_LARGE } from '../uploadLimits.mjs'
import {
  convertFontBuffer,
  detectFontFormat,
  getFontExtension,
  getFontMimeType,
  SUPPORTED_FONT_FORMATS,
} from '../verifyFont.mjs'

function sanitizeBaseName(filename) {
  const baseName = filename.replace(/\.[^.]+$/, '').trim() || 'font'
  return baseName.replace(/[^a-zA-Z0-9-_]+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '')
}

function isSupportedFontFormat(value) {
  return SUPPORTED_FONT_FORMATS.includes(value)
}

async function handleFontConvert(request) {
  const data = await request.formData()
  const file = data.get('file')
  const targetFormat = data.get('targetFormat')?.toString().toLowerCase() ?? ''

  if (!(file instanceof File)) {
    return new Response('Arquivo de fonte não suportado.', { status: 400 })
  }
  if (!isSupportedFontFormat(targetFormat)) {
    return new Response('Formato de saída inválido.', { status: 400 })
  }
  if (fontTooLarge(file.size)) {
    return Response.json({ error: MSG_FONT_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  const inputFormat = (await detectFontFormat(buffer, file.name)) ?? getFontExtension(file.name)

  if (!inputFormat) {
    return new Response('Não foi possível identificar o formato da fonte enviada.', { status: 400 })
  }
  if (inputFormat === targetFormat) {
    return new Response('A fonte já está no formato selecionado.', { status: 400 })
  }

  const outputBuffer = await convertFontBuffer(buffer, inputFormat, targetFormat)
  const fileName = `${sanitizeBaseName(file.name)}.${targetFormat}`

  return new Response(outputBuffer, {
    status: 200,
    headers: {
      'Content-Type': getFontMimeType(targetFormat),
      'Content-Disposition': `attachment; filename="${fileName}"`,
      'X-Detected-Font-Format': inputFormat,
    },
  })
}

export function registerFontConvert(registerRoute) {
  registerRoute('POST', '/api/tools/tools/font-convert', handleFontConvert)
}
