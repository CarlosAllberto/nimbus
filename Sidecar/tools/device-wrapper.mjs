// Ported from nimbus/app/api/tools/studio/device-wrapper/route.ts — same
// browser-chrome/phone-bezel composition, same padding/shadow/corner numbers,
// minus session/Supabase/quota (no auth in this version).
//
// Deliberate departure from the site: the site's bg=image always loads a
// fixed asset (public/background.webp). The app lets the user pick their own
// background image, so an optional second multipart field `background` is
// accepted — when present (and bg=image) it wins; otherwise bg=image falls
// back to the bundled asset below.
import sharp from 'sharp'
import { fileURLToPath } from 'node:url'
import fs from 'node:fs/promises'
import { verifyImage } from '../verifyImage.mjs'
import { imageTooLarge, MSG_IMAGE_TOO_LARGE } from '../uploadLimits.mjs'

// Resolved relative to this module, never process.cwd() — the sidecar's
// working directory is whatever the Swift app happened to launch it from.
const BUNDLED_BACKGROUND_PATH = fileURLToPath(new URL('../assets/background.webp', import.meta.url))

const PADDING = 60
const SHADOW_BLUR = 25
const SHADOW_OFFSET = 15
const SHADOW_OPACITY = 0.4

// The numbers above (and the bezel/header/corner sizes below) are absolute
// pixels tuned for a screenshot around this width. Applied unscaled to a 4000px
// screenshot they collapse into a hairline header with invisible window
// buttons, which is what a large image used to produce. Every chrome dimension
// is multiplied by `chromeScale` so the frame keeps the same proportions at any
// input size.
const REFERENCE_WIDTH = 1280
// Never below 1: small images already look right with the numbers as authored,
// and shrinking the chrome further would only make it flimsy. The ceiling keeps
// an enormous input from growing a frame that dwarfs the screenshot.
const MIN_CHROME_SCALE = 1
const MAX_CHROME_SCALE = 6

/// Width drives the scale for both layouts: the header height and the phone
/// bezel are both proportions of the device's width in the original design.
function chromeScale(width) {
  return Math.min(Math.max(width / REFERENCE_WIDTH, MIN_CHROME_SCALE), MAX_CHROME_SCALE)
}

function macosTrafficLights(scale) {
  const r = 6 * scale
  const cy = 20 * scale
  return `
    <circle cx="${20 * scale}" cy="${cy}" r="${r}" fill="#FF5F56" />
    <circle cx="${40 * scale}" cy="${cy}" r="${r}" fill="#FFBD2E" />
    <circle cx="${60 * scale}" cy="${cy}" r="${r}" fill="#27C93F" />
  `
}

function windowsControls(width, scale) {
  const size = 10 * scale
  const top = 15 * scale
  const bottom = 25 * scale
  return `
    <!-- Minimize -->
    <rect x="${width - 120 * scale}" y="${19 * scale}" width="${size}" height="${scale}" fill="#FFFFFF" />
    <!-- Maximize -->
    <rect x="${width - 80 * scale}" y="${top}" width="${size}" height="${size}" fill="none" stroke="#FFFFFF" stroke-width="${scale}" />
    <!-- Close -->
    <line x1="${width - 40 * scale}" y1="${top}" x2="${width - 30 * scale}" y2="${bottom}" stroke="#FFFFFF" stroke-width="${scale}" />
    <line x1="${width - 30 * scale}" y1="${top}" x2="${width - 40 * scale}" y2="${bottom}" stroke="#FFFFFF" stroke-width="${scale}" />
  `
}

/** Browser-chrome composition for a landscape (width >= height) source image. */
function composeDesktop(buffer, width, height, os, scale) {
  const headerHeight = Math.round(40 * scale)
  const cornerRadius = Math.round(12 * scale)

  const headerSvg = `
    <svg width="${width}" height="${headerHeight + cornerRadius}" viewBox="0 0 ${width} ${headerHeight + cornerRadius}">
      <path d="M 0 ${cornerRadius} Q 0 0 ${cornerRadius} 0 L ${width - cornerRadius} 0 Q ${width} 0 ${width} ${cornerRadius} L ${width} ${headerHeight} L 0 ${headerHeight} Z" fill="#1a1a1a" />
      ${os === 'windows' ? windowsControls(width, scale) : macosTrafficLights(scale)}
    </svg>
  `

  return {
    finalWidth: width,
    finalHeight: height + headerHeight,
    frameRadius: cornerRadius,
    composites: [
      { input: Buffer.from(headerSvg), top: 0, left: 0 },
      { input: buffer, top: headerHeight, left: 0 },
    ],
  }
}

/** Phone-bezel composition for a portrait (height > width) source image. */
async function composePortrait(buffer, width, height, scale) {
  const bezel = Math.round(15 * scale)
  const maskCornerRadius = Math.round(40 * scale)
  const frameRadius = Math.round(55 * scale)

  const maskSvg = `
    <svg width="${width}" height="${height}">
      <rect x="0" y="0" width="${width}" height="${height}" rx="${maskCornerRadius}" ry="${maskCornerRadius}" fill="white"/>
    </svg>
  `

  const roundedImageBuffer = await sharp(buffer)
    .resize(width, height)
    .composite([{ input: Buffer.from(maskSvg), blend: 'dest-in' }])
    .toBuffer()

  const finalWidth = width + bezel * 2
  const finalHeight = height + bezel * 2

  const frameSvg = `
    <svg width="${finalWidth}" height="${finalHeight}">
      <rect x="0" y="0" width="${finalWidth}" height="${finalHeight}" rx="${frameRadius}" ry="${frameRadius}" fill="#1a1a1a"/>
    </svg>
  `

  return {
    finalWidth,
    finalHeight,
    frameRadius,
    composites: [
      { input: Buffer.from(frameSvg), top: 0, left: 0 },
      { input: roundedImageBuffer, top: bezel, left: bezel },
    ],
  }
}

/** Blurred, semi-transparent silhouette of the device frame, offset down as a drop shadow. */
async function shadowLayer(finalWidth, finalHeight, frameRadius, padding, blur) {
  const shapeSvg = `
    <svg width="${finalWidth}" height="${finalHeight}">
      <rect x="0" y="0" width="${finalWidth}" height="${finalHeight}" rx="${frameRadius}" ry="${frameRadius}" fill="rgba(0,0,0,${SHADOW_OPACITY})"/>
    </svg>
  `

  return sharp(Buffer.from(shapeSvg))
    .extend({
      top: padding,
      bottom: padding,
      left: padding,
      right: padding,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    })
    .blur(blur)
    .toBuffer()
}

async function backgroundLayer(canvasWidth, canvasHeight, customBackgroundBuffer) {
  const sourceBuffer = customBackgroundBuffer ?? (await fs.readFile(BUNDLED_BACKGROUND_PATH))
  return sharp(sourceBuffer)
    .resize(canvasWidth, canvasHeight, { fit: 'cover', position: 'center' })
    .toBuffer()
}

async function handleDeviceWrapper(request) {
  const data = await request.formData()
  const file = data.get('file')
  const os = data.get('os')?.toString() === 'windows' ? 'windows' : 'macos'
  const bg = data.get('bg')?.toString() === 'image' ? 'image' : 'transparent'

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

  let customBackgroundBuffer
  if (bg === 'image') {
    const backgroundFile = data.get('background')
    if (backgroundFile instanceof File) {
      if (imageTooLarge(backgroundFile.size)) {
        return Response.json({ error: MSG_IMAGE_TOO_LARGE }, { status: 413 })
      }
      const backgroundBuffer = Buffer.from(await backgroundFile.arrayBuffer())
      if ((await verifyImage(backgroundBuffer)) === false) {
        return new Response('Arquivo não suportado', { status: 400 })
      }
      customBackgroundBuffer = backgroundBuffer
    }
  }

  const metadata = await sharp(buffer).metadata()
  if (!metadata.width || !metadata.height) {
    return new Response('Arquivo não suportado', { status: 400 })
  }

  const { width, height } = metadata
  const isDesktop = width >= height

  const scale = chromeScale(width)
  const padding = Math.round(PADDING * scale)
  const shadowOffset = Math.round(SHADOW_OFFSET * scale)

  const device = isDesktop
    ? composeDesktop(buffer, width, height, os, scale)
    : await composePortrait(buffer, width, height, scale)

  const canvasWidth = device.finalWidth + padding * 2
  const canvasHeight = device.finalHeight + padding * 2

  const shadow = await shadowLayer(
    device.finalWidth,
    device.finalHeight,
    device.frameRadius,
    padding,
    SHADOW_BLUR * scale,
  )

  const finalComposites = []

  if (bg === 'image') {
    try {
      finalComposites.push({
        input: await backgroundLayer(canvasWidth, canvasHeight, customBackgroundBuffer),
        top: 0,
        left: 0,
      })
    } catch (err) {
      console.error('Failed to load background image:', err)
    }
  }

  finalComposites.push({ input: shadow, top: shadowOffset, left: 0 })

  for (const layer of device.composites) {
    finalComposites.push({
      input: layer.input,
      top: layer.top + padding,
      left: layer.left + padding,
      blend: layer.blend,
    })
  }

  const resultBuffer = await sharp({
    create: {
      width: canvasWidth,
      height: canvasHeight,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite(finalComposites)
    .png()
    .toBuffer()

  return new Response(resultBuffer, {
    status: 200,
    headers: { 'Content-Type': 'image/png' },
  })
}

export function registerDeviceWrapper(registerRoute) {
  registerRoute('POST', '/api/tools/studio/device-wrapper', handleDeviceWrapper)
}
