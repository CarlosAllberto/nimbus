// Ported from nimbus/app/api/tools/studio/resize/route.ts, minus session
// (no auth in this version). Resizing keeps the source format — only the
// dimensions change — so the Content-Type is read back off the output.
import sharp from 'sharp'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'

const MIME_BY_FORMAT = {
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  gif: 'image/gif',
  tiff: 'image/tiff',
  avif: 'image/avif',
  heif: 'image/heif',
}

async function handleResize(request) {
  const data = await request.formData()
  const file = data.get('file')
  // The field is named `width` on both sides even when resizing by height —
  // it carries whichever dimension was picked. Kept as-is for parity with the
  // site rather than renamed here.
  const size = Number(data.get('width'))
  const resizeBy = String(data.get('resizeBy') ?? 'width')

  if (!(file instanceof File)) {
    return new Response('Arquivo não suportado', { status: 400 })
  }
  // The site falls back to 50 for anything unparseable, which silently produces
  // a thumbnail when a field is malformed. A 400 says what actually happened.
  if (!Number.isFinite(size) || size < 1) {
    return new Response('Dimensão inválida.', { status: 400 })
  }
  if (imageTooLarge(file.size)) {
    return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  if ((await verifyImage(buffer)) === false) {
    return new Response('Arquivo não suportado', { status: 400 })
  }

  const outputBuffer = await sharp(buffer)
    .resize(resizeBy === 'height' ? { height: Math.round(size) } : { width: Math.round(size) })
    .toBuffer()

  const metadata = await sharp(outputBuffer).metadata()
  const contentType = MIME_BY_FORMAT[metadata.format] ?? 'application/octet-stream'

  return new Response(outputBuffer, {
    status: 200,
    headers: { 'Content-Type': contentType },
  })
}

export function registerResize(registerRoute) {
  registerRoute('POST', '/api/tools/studio/resize', handleResize)
}
