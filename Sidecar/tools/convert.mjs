// Ported from nimbus/app/api/tools/studio/convert/route.ts, minus
// session/Supabase (no auth in this version), with two deliberate departures
// from the site — see the comments on FORMATS and Content-Type below.
import sharp from 'sharp'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'

// The site passes the raw field straight into `sharp.toFormat()`, so `jpg`
// throws (sharp only knows `jpeg`) and an absent field becomes the string
// "null" and throws too. Validating here turns both into a 400 the client can
// explain instead of a 500 carrying a sharp stack trace.
const FORMATS = {
  png: { sharp: 'png', mime: 'image/png' },
  jpg: { sharp: 'jpeg', mime: 'image/jpeg' },
  jpeg: { sharp: 'jpeg', mime: 'image/jpeg' },
  webp: { sharp: 'webp', mime: 'image/webp' },
}

async function handleConvert(request) {
  const data = await request.formData()
  const file = data.get('file')
  const format = FORMATS[String(data.get('format') ?? '').toLowerCase()]

  if (!(file instanceof File)) {
    return new Response('Arquivo não suportado', { status: 400 })
  }
  if (!format) {
    return new Response('Formato de saída inválido.', { status: 400 })
  }
  if (imageTooLarge(file.size)) {
    return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  if ((await verifyImage(buffer)) === false) {
    return new Response('Arquivo não suportado', { status: 400 })
  }

  const outputBuffer = await sharp(buffer).toFormat(format.sharp).toBuffer()

  // The site answers with no Content-Type at all and lets the browser client
  // guess the extension from the requested format. This client names the file
  // from the response, so the header is sent.
  return new Response(outputBuffer, {
    status: 200,
    headers: { 'Content-Type': format.mime },
  })
}

export function registerConvert(registerRoute) {
  registerRoute('POST', '/api/tools/studio/convert', handleConvert)
}
