// Ported from nimbus/app/api/tools/web/ico/route.ts. Same sizes, same safe
// margin, same hand-built ICO header. This route never had auth on the site
// either, so nothing was removed beyond the shared quota plumbing.
import sharp from 'sharp'
import JSZip from 'jszip'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'

/** Margin per side, so the icon does not touch the edge — rounded tabs clip corners. */
const ICON_SAFE_MARGIN_RATIO = 0.12

const OUTPUTS = [
  { name: 'favicon-16x16.png', size: 16 },
  { name: 'favicon-32x32.png', size: 32 },
  { name: 'apple-touch-icon.png', size: 180 },
  { name: 'android-chrome-192x192.png', size: 192 },
  { name: 'android-chrome-512x512.png', size: 512 },
]

function marginRatio(formData) {
  const raw = formData.get('safeMargin')
  if (raw === null) return 0
  const value = String(raw).trim().toLowerCase()
  return ['true', '1', 'on', 'yes'].includes(value) ? ICON_SAFE_MARGIN_RATIO : 0
}

async function pngIcon(source, size, sideMarginRatio) {
  const inner = Math.max(1, Math.round(size * (1 - 2 * sideMarginRatio)))
  const fitted = await source
    .clone()
    .resize({
      width: inner,
      height: inner,
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .png()
    .toBuffer()

  return sharp({
    create: { width: size, height: size, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } },
  })
    .composite([{ input: fitted, gravity: 'centre' }])
    .png()
    .toBuffer()
}

/** A 22-byte ICONDIR + ICONDIRENTRY wrapping a single 32x32 PNG. */
function pngToIco(pngBuffer) {
  const header = Buffer.alloc(22)
  header.writeUInt16LE(0, 0) // reserved
  header.writeUInt16LE(1, 2) // type: icon
  header.writeUInt16LE(1, 4) // image count
  header.writeUInt8(32, 6) // width
  header.writeUInt8(32, 7) // height
  header.writeUInt8(0, 8) // palette colors
  header.writeUInt8(0, 9) // reserved
  header.writeUInt16LE(1, 10) // color planes
  header.writeUInt16LE(32, 12) // bits per pixel
  header.writeUInt32LE(pngBuffer.length, 14)
  header.writeUInt32LE(22, 18) // offset of the image data
  return Buffer.concat([header, pngBuffer])
}

async function handleIco(request) {
  const data = await request.formData()
  const file = data.get('file')

  if (!(file instanceof File)) {
    return Response.json({ error: 'No file provided' }, { status: 400 })
  }
  if (imageTooLarge(file.size)) {
    return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  // The site trusts `file.type`, which the client supplies and can spoof. Every
  // other tool here sniffs magic bytes, so this one does too.
  if ((await verifyImage(buffer)) === false) {
    return Response.json({ error: 'Invalid file type. Please upload an image.' }, { status: 400 })
  }

  const image = sharp(buffer)
  const sideMarginRatio = marginRatio(data)
  const zip = new JSZip()

  zip.file('favicon.ico', pngToIco(await pngIcon(image, 32, sideMarginRatio)))
  for (const { name, size } of OUTPUTS) {
    zip.file(name, await pngIcon(image, size, sideMarginRatio))
  }

  const zipContent = await zip.generateAsync({ type: 'nodebuffer' })

  return new Response(zipContent, {
    status: 200,
    headers: { 'Content-Type': 'application/zip' },
  })
}

export function registerIco(registerRoute) {
  registerRoute('POST', '/api/tools/web/ico', handleIco)
}
