// Ported from nimbus/app/api/tools/studio/trim-image/route.ts — same trim and
// PNG settings, minus session/Supabase/quota (no auth in this version).
import sharp from 'sharp'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'

async function handleTrimImage(request) {
  const data = await request.formData()
  const file = data.get('file')

  if (!(file instanceof File)) {
    return new Response('Arquivo não suportado', { status: 400 })
  }
  if (imageTooLarge(file.size)) {
    return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  if ((await verifyImage(buffer)) === false) {
    return new Response('Arquivo não suportado', { status: 400 })
  }

  // `compressionLevel: 0` matches the site: trimming is a cropping tool, so it
  // hands back the fastest, most faithful PNG rather than a small one.
  const outputBuffer = await sharp(buffer).trim().png({ compressionLevel: 0 }).toBuffer()

  return new Response(outputBuffer, {
    status: 200,
    headers: { 'Content-Type': 'image/png' },
  })
}

export function registerTrimImage(registerRoute) {
  registerRoute('POST', '/api/tools/studio/trim-image', handleTrimImage)
}
