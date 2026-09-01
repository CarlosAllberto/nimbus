// Ported from nimbus/app/api/tools/tools/palette-from-image/route.ts, minus
// session/Supabase/quota. The k-means itself lives in ../extractPaletteKMeans.mjs,
// ported verbatim, so the palette matches the site's for the same image.
import sharp from 'sharp'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'
import { extractPaletteKMeans } from '../extractPaletteKMeans.mjs'

const MIN_K = 2
const MAX_K = 12
const MAX_SIDE = 256

// The site reaches for tinycolor2 purely to render `#rrggbb`. Not worth a
// dependency for six characters.
function toHex({ r, g, b }) {
  const pair = value => value.toString(16).padStart(2, '0')
  return `#${pair(r)}${pair(g)}${pair(b)}`
}

async function handlePaletteFromImage(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid form data' }, { status: 400 })
  }

  const file = data.get('file')
  const count = parseInt(String(data.get('count') ?? ''), 10)

  if (!(file instanceof File)) {
    return Response.json({ error: 'Image file is required' }, { status: 400 })
  }
  if (!Number.isFinite(count) || count < MIN_K || count > MAX_K) {
    return Response.json(
      { error: `Number of colors must be between ${MIN_K} and ${MAX_K}` },
      { status: 400 },
    )
  }
  if (imageTooLarge(file.size)) {
    return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  if ((await verifyImage(buffer)) === false) {
    return Response.json({ error: 'Unsupported image file' }, { status: 400 })
  }

  // Downscaled first: k-means over a full-resolution image would take seconds
  // and produce the same clusters.
  const { data: rawData, info } = await sharp(buffer)
    .rotate()
    .resize({ width: MAX_SIDE, height: MAX_SIDE, fit: 'inside', withoutEnlargement: true })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true })

  if (info.channels !== 3 && info.channels !== 4) {
    return Response.json({ error: 'Unexpected channel layout' }, { status: 500 })
  }

  const swatches = extractPaletteKMeans(
    new Uint8Array(rawData),
    info.width,
    info.height,
    info.channels,
    Math.round(count),
  )

  if (swatches.length === 0) {
    return Response.json(
      { error: 'Could not extract colors (image may be fully transparent)' },
      { status: 400 },
    )
  }

  const colors = swatches.map(swatch => ({
    hex: toHex(swatch.rgb),
    rgb: `rgb(${swatch.rgb.r}, ${swatch.rgb.g}, ${swatch.rgb.b})`,
    weight: swatch.weight,
  }))

  return Response.json({ colors })
}

export function registerPaletteFromImage(registerRoute) {
  registerRoute('POST', '/api/tools/tools/palette-from-image', handlePaletteFromImage)
}
