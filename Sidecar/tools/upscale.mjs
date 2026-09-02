// Ported from nimbus/app/api/tools/studio/upscale/route.ts, minus session
// (no auth in this version). 2x lanczos3 interpolation, no options — matches
// the site exactly (scaleFactor is literal in its code, not a configurable
// default). This is interpolation, not AI upscaling: the user asked for a
// free-library AI upscaler and confirmed none works today (UpscalerJS/
// tfjs-node break on Node 25 — 'util.isNullOrUndefined is not a function',
// tested against 4.22 stable and 4.23.0-rc.0, same failure both times).
// Ported the working thing now; AI stays future work.
import sharp from 'sharp'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'

const SCALE_FACTOR = 2

async function handleUpscale(request) {
  const data = await request.formData()
  const file = data.get('file')

  if (!(file instanceof File)) {
    return new Response('Unsupported file.', { status: 400 })
  }
  if (imageTooLarge(file.size)) {
    return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  if ((await verifyImage(buffer)) === false) {
    return new Response('Unsupported file.', { status: 400 })
  }

  const metadata = await sharp(buffer).metadata()
  const originalWidth = metadata.width || 0
  const originalHeight = metadata.height || 0

  const upscaled = await sharp(buffer)
    .resize(originalWidth * SCALE_FACTOR, originalHeight * SCALE_FACTOR, {
      kernel: sharp.kernel.lanczos3,
      fit: 'fill',
    })
    .png()
    .toBuffer()

  return new Response(upscaled, {
    status: 200,
    headers: { 'Content-Type': 'image/png' },
  })
}

export function registerUpscale(registerRoute) {
  registerRoute('POST', '/api/tools/studio/upscale', handleUpscale)
}