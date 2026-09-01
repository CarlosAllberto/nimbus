// Ported from nimbus/app/api/tools/tools/qrcode/route.ts, minus session/quota.
// Already used formData() on the Next side, so the transport didn't change.
// The Swift side always sends format="svg" (product decision), but the other
// formats are kept for parity with the original route.
import QRCode from 'qrcode'
import sharp from 'sharp'
import { fileTypeFromBuffer } from 'file-type'
import { imageTooLarge, MAX_UPLOAD_IMAGE_MB } from '../uploadLimits.mjs'

const SIZE = 256
const MARGIN = 1
const ICON_RATIO = 0.22
const ICON_PADDING_RATIO = 0.04

async function isImageOrSvg(buffer, fileName) {
  const type = await fileTypeFromBuffer(new Uint8Array(buffer))
  if (type && type.mime.startsWith('image/')) return true
  if (fileName && fileName.toLowerCase().endsWith('.svg')) return true
  const start = buffer.slice(0, 200).toString('utf8').trimStart()
  return start.startsWith('<?xml') || start.startsWith('<svg')
}

function isSvgIcon(buffer, fileName) {
  if (fileName && fileName.toLowerCase().endsWith('.svg')) return true
  const start = buffer.slice(0, 200).toString('utf8').trimStart()
  return start.startsWith('<?xml') || start.startsWith('<svg')
}

function qrToSvg(qrData, outputSize, marginModules, iconDataUrl) {
  const { data: modData, size: modSize } = qrData.modules
  const scale = outputSize / (modSize + 2 * marginModules)
  const actualMarginPx = marginModules * scale
  const rects = []

  for (let row = 0; row < modSize; row++) {
    for (let col = 0; col < modSize; col++) {
      if (modData[row * modSize + col] === 1) {
        const x = actualMarginPx + col * scale
        const y = actualMarginPx + row * scale
        rects.push(`<rect x="${x}" y="${y}" width="${scale}" height="${scale}" fill="#000"/>`)
      }
    }
  }

  const iconPart =
    iconDataUrl &&
    (() => {
      const iconSize = Math.max(32, Math.floor(outputSize * ICON_RATIO))
      const padding = Math.floor(outputSize * ICON_PADDING_RATIO)
      const total = iconSize + 2 * padding
      const left = (outputSize - total) / 2
      const top = left
      return `<rect x="${left}" y="${top}" width="${total}" height="${total}" fill="#fff"/><image href="${iconDataUrl}" x="${left + padding}" y="${top + padding}" width="${iconSize}" height="${iconSize}" preserveAspectRatio="xMidYMid meet"/>`
    })()

  return `<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${outputSize} ${outputSize}" width="${outputSize}" height="${outputSize}">${rects.join('')}${iconPart || ''}</svg>`
}

async function handleQrcode(request) {
  let formData
  try {
    formData = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  try {
    const data = formData.get('data') || ''
    const format = formData.get('format') || 'png'
    const validFormat = ['png', 'jpg', 'png_transparent', 'svg'].includes(format) ? format : 'png'
    const iconFile = formData.get('icon')

    if (!data.trim()) {
      return Response.json({ error: 'Send the text or URL (field "data")' }, { status: 400 })
    }

    // With a center icon we use correction level 'H' so the QR stays readable.
    let iconBuffer = null
    if (iconFile instanceof File && iconFile.size > 0) {
      if (imageTooLarge(iconFile.size)) {
        return Response.json(
          { error: `This image is larger than the ${MAX_UPLOAD_IMAGE_MB} MB limit.` },
          { status: 413 },
        )
      }
      iconBuffer = Buffer.from(await iconFile.arrayBuffer())
    }
    const hasValidIcon = iconBuffer && (await isImageOrSvg(iconBuffer, iconFile?.name))
    const errorCorrectionLevel = hasValidIcon ? 'H' : 'L'

    const qrData = QRCode.create(data, { errorCorrectionLevel })

    // SVG: return directly (with the optional icon embedded).
    if (validFormat === 'svg') {
      let iconDataUrl
      if (hasValidIcon && iconBuffer) {
        const iconSize = Math.max(32, Math.floor(SIZE * ICON_RATIO))
        const padding = Math.floor(SIZE * ICON_PADDING_RATIO)
        let iconPipeline = sharp(iconBuffer)
        if (isSvgIcon(iconBuffer, iconFile?.name)) {
          iconPipeline = iconPipeline.flatten({ background: '#ffffff' })
        }
        const iconPadded = await iconPipeline
          .resize(iconSize, iconSize, { fit: 'contain', background: { r: 255, g: 255, b: 255, alpha: 1 } })
          .extend({
            top: padding,
            bottom: padding,
            left: padding,
            right: padding,
            background: { r: 255, g: 255, b: 255, alpha: 1 },
          })
          .png()
          .toBuffer()
        iconDataUrl = `data:image/png;base64,${iconPadded.toString('base64')}`
      }
      const svg = qrToSvg(qrData, SIZE, MARGIN, iconDataUrl)
      return new Response(svg, {
        status: 200,
        headers: {
          'Content-Type': 'image/svg+xml',
          'Content-Disposition': 'inline; filename="qrcode.svg"',
        },
      })
    }

    const transparentLight = validFormat === 'png_transparent'
    let qrBuffer = await QRCode.toBuffer(data, {
      type: 'png',
      width: SIZE,
      margin: MARGIN,
      errorCorrectionLevel,
      color: { dark: '#000000', light: '#ffffff' },
    })
    if (transparentLight) {
      const raw = await sharp(qrBuffer).ensureAlpha().raw().toBuffer({ resolveWithObject: true })
      const { data: pixels, info } = raw
      for (let i = 0; i < pixels.length; i += 4) {
        if (pixels[i] === 255 && pixels[i + 1] === 255 && pixels[i + 2] === 255) pixels[i + 3] = 0
      }
      qrBuffer = await sharp(pixels, {
        raw: { width: info.width, height: info.height, channels: 4 },
      })
        .png()
        .toBuffer()
    }

    let pipeline = sharp(qrBuffer)

    if (hasValidIcon && iconBuffer) {
      const meta = await pipeline.metadata()
      const qrSize = meta.width || SIZE
      const iconSize = Math.max(32, Math.floor(qrSize * ICON_RATIO))
      const padding = Math.floor(qrSize * ICON_PADDING_RATIO)
      const bgAlpha = transparentLight ? 0 : 1
      let iconPipeline = sharp(iconBuffer)
      if (isSvgIcon(iconBuffer, iconFile?.name)) {
        iconPipeline = iconPipeline.flatten({ background: '#ffffff' })
      }
      const iconPadded = await iconPipeline
        .resize(iconSize, iconSize, { fit: 'contain', background: { r: 255, g: 255, b: 255, alpha: bgAlpha } })
        .extend({
          top: padding,
          bottom: padding,
          left: padding,
          right: padding,
          background: { r: 255, g: 255, b: 255, alpha: bgAlpha },
        })
        .png()
        .toBuffer()
      const left = Math.floor((qrSize - iconSize - 2 * padding) / 2)
      const top = left
      pipeline = pipeline.composite([{ input: iconPadded, left, top }])
    }

    const isJpg = validFormat === 'jpg'
    const output = isJpg ? await pipeline.jpeg({ quality: 92 }).toBuffer() : await pipeline.png().toBuffer()
    const filename =
      validFormat === 'png_transparent' ? 'qrcode-transparent.png' : isJpg ? 'qrcode.jpg' : 'qrcode.png'

    return new Response(output, {
      status: 200,
      headers: {
        'Content-Type': isJpg ? 'image/jpeg' : 'image/png',
        'Content-Disposition': `inline; filename="${filename}"`,
      },
    })
  } catch (err) {
    console.error('QR code generation error:', err)
    return Response.json({ error: err instanceof Error ? err.message : 'Failed to generate QR code' }, { status: 500 })
  }
}

export function registerQrcode(registerRoute) {
  registerRoute('POST', '/api/tools/tools/qrcode', handleQrcode)
}
