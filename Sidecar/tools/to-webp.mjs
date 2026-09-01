// Ported from nimbus/app/api/tools/web/to-webp/route.ts — same encoders and
// resize/quality pipeline, minus session/Supabase/quota (no auth in this version).
import sharp from 'sharp'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'

const PRESETS = ['perda', 'lustroso', 'sem-perdas']

const MIME_BY_FORMAT = {
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  heif: 'image/heif',
}

async function encodeWebp(buffer, preset) {
  if (preset === 'sem-perdas') {
    return sharp(buffer).webp({ lossless: true }).toBuffer()
  }
  if (preset === 'lustroso') {
    return sharp(buffer)
      .webp({
        quality: 90,
        effort: 6,
        smartSubsample: true,
        alphaQuality: 80,
      })
      .toBuffer()
  }

  const targetFactor = 0.42
  let maxQuality = 72
  let minQuality = 26
  minQuality = Math.min(minQuality, maxQuality)
  const targetSizeKB = (buffer.length / 1024) * targetFactor
  let outputBuffer = buffer

  while (minQuality <= maxQuality) {
    const q = Math.round((minQuality + maxQuality) / 2)
    const bufferTest = await sharp(buffer)
      .webp({
        quality: q,
        effort: 6,
        smartSubsample: true,
        alphaQuality: 60,
      })
      .toBuffer()
    const currentSizeKB = bufferTest.length / 1024
    if (currentSizeKB > targetSizeKB) {
      maxQuality = q - 1
    } else {
      outputBuffer = bufferTest
      minQuality = q + 1
    }
  }

  return outputBuffer
}

async function encodeJpeg(buffer, preset, originalSize) {
  if (preset === 'sem-perdas') {
    return sharp(buffer).jpeg({ quality: 100, mozjpeg: true }).toBuffer()
  }
  if (preset === 'lustroso') {
    return sharp(buffer).jpeg({ quality: 90, mozjpeg: true }).toBuffer()
  }

  const targetFactor = 0.42
  let maxQuality = 72
  let minQuality = 26
  const targetSizeKB = (originalSize / 1024) * targetFactor
  let outputBuffer = await sharp(buffer).jpeg({ quality: minQuality, mozjpeg: true }).toBuffer()

  while (minQuality <= maxQuality) {
    const q = Math.round((minQuality + maxQuality) / 2)
    const bufferTest = await sharp(buffer).jpeg({ quality: q, mozjpeg: true }).toBuffer()
    const currentSizeKB = bufferTest.length / 1024
    if (currentSizeKB > targetSizeKB) {
      maxQuality = q - 1
    } else {
      outputBuffer = bufferTest
      minQuality = q + 1
    }
  }

  return outputBuffer
}

async function encodePng(buffer, preset) {
  if (preset === 'sem-perdas') {
    return sharp(buffer).png({ compressionLevel: 0 }).toBuffer()
  }
  if (preset === 'lustroso') {
    return sharp(buffer).png({ compressionLevel: 6, palette: false }).toBuffer()
  }
  return sharp(buffer).png({ compressionLevel: 9, palette: true, effort: 10 }).toBuffer()
}

async function encodeHeif(buffer, preset) {
  const quality = preset === 'sem-perdas' ? 100 : preset === 'lustroso' ? 90 : 65
  try {
    return await sharp(buffer).heif({ quality }).toBuffer()
  } catch {
    return encodeJpeg(buffer, preset, buffer.length)
  }
}

async function encodeNativeFormat(buffer, preset, format, originalSize) {
  const normalized = format === 'jpg' ? 'jpeg' : format

  switch (normalized) {
    case 'jpeg':
      return { data: await encodeJpeg(buffer, preset, originalSize), contentType: MIME_BY_FORMAT.jpeg }
    case 'png':
      return { data: await encodePng(buffer, preset), contentType: MIME_BY_FORMAT.png }
    case 'webp':
      return { data: await encodeWebp(buffer, preset), contentType: MIME_BY_FORMAT.webp }
    case 'heif':
    case 'heic':
      return { data: await encodeHeif(buffer, preset), contentType: MIME_BY_FORMAT.heif }
    default:
      return { data: await encodeJpeg(buffer, preset, originalSize), contentType: MIME_BY_FORMAT.jpeg }
  }
}

async function handleToWebp(request) {
  const data = await request.formData()
  const file = data.get('file')
  const presetRaw = data.get('webpPreset')?.toString() ?? 'lustroso'
  const webpPreset = PRESETS.includes(presetRaw) ? presetRaw : 'lustroso'
  const convertToWebp = data.get('convertToWebp')?.toString() !== '0'

  if (!(file instanceof Blob)) {
    return new Response('Arquivo não suportado', { status: 400 })
  }
  if (imageTooLarge(file.size)) {
    return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  if ((await verifyImage(buffer)) === false) {
    return new Response('Arquivo não suportado', { status: 400 })
  }

  const pipeline = sharp(buffer).rotate().resize({
    width: 1920,
    withoutEnlargement: true,
    fit: 'inside',
  })

  const resizedBuffer = await pipeline.toBuffer()
  const metadata = await sharp(resizedBuffer).metadata()

  let outputBuffer
  let contentType

  if (convertToWebp) {
    outputBuffer = await encodeWebp(resizedBuffer, webpPreset)
    contentType = MIME_BY_FORMAT.webp
  } else {
    const encoded = await encodeNativeFormat(resizedBuffer, webpPreset, metadata.format, buffer.length)
    outputBuffer = encoded.data
    contentType = encoded.contentType
  }

  return new Response(outputBuffer, {
    status: 200,
    headers: { 'Content-Type': contentType },
  })
}

export function registerToWebp(registerRoute) {
  registerRoute('POST', '/api/tools/web/to-webp', handleToWebp)
}
