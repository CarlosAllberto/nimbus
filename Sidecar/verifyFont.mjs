// Ported from nimbus/app/utils/verifyFont.ts — format detection by signature,
// and the fonteditor-core/opentype.js conversion pipeline, in the same shape
// as verifyImage.mjs.
import { createFont, woff2 } from 'fonteditor-core'
import opentype from 'opentype.js'

export const SUPPORTED_FONT_FORMATS = ['ttf', 'otf', 'woff', 'woff2', 'eot']

const FONT_SIGNATURES = {
  '\x00\x01\x00\x00': 'ttf',
  OTTO: 'otf',
  wOFF: 'woff',
  wOF2: 'woff2',
}

const EOT_MAGIC_OFFSET = 34
const EOT_MAGIC = 'LP'

// fonteditor-core's woff2 codec is WASM-backed and needs an async init before
// first use. Memoized so concurrent/repeat requests share one init instead of
// each racing their own. The wasm itself is located by fonteditor-core's own
// emscripten glue relative to its module file (not process.cwd()), so no
// manual path resolution is needed here — verified working when this module
// is loaded from inside the .app bundle, not just from a checkout.
let woff2InitPromise = null

function toArrayBuffer(buffer) {
  return Uint8Array.from(buffer).buffer
}

export function getFontExtension(filename) {
  const ext = filename?.split('.').pop()?.toLowerCase()
  return SUPPORTED_FONT_FORMATS.includes(ext) ? ext : null
}

export function getFontMimeType(format) {
  switch (format) {
    case 'ttf':
      return 'font/ttf'
    case 'otf':
      return 'font/otf'
    case 'woff':
      return 'font/woff'
    case 'woff2':
      return 'font/woff2'
    case 'eot':
      return 'application/vnd.ms-fontobject'
    default:
      return 'application/octet-stream'
  }
}

export async function ensureWoff2Ready() {
  if (!woff2InitPromise) {
    woff2InitPromise = woff2.init().then(() => undefined)
  }
  await woff2InitPromise
}

function sniffFontFormat(buffer) {
  if (buffer.length >= 4) {
    const signature = buffer.subarray(0, 4).toString('latin1')
    if (signature in FONT_SIGNATURES) {
      return FONT_SIGNATURES[signature]
    }
  }

  if (buffer.length > EOT_MAGIC_OFFSET + 2) {
    const eotSignature = buffer.subarray(EOT_MAGIC_OFFSET, EOT_MAGIC_OFFSET + 2).toString('latin1')
    if (eotSignature === EOT_MAGIC) {
      return 'eot'
    }
  }

  return null
}

async function canParseFont(buffer, format) {
  try {
    if (format === 'woff2') {
      await ensureWoff2Ready()
    }
    createFont(buffer, { type: format })
    return true
  } catch {
    return false
  }
}

export async function detectFontFormat(buffer, filename) {
  const candidates = new Set()

  const sniffed = sniffFontFormat(buffer)
  if (sniffed) candidates.add(sniffed)

  const extension = filename ? getFontExtension(filename) : null
  if (extension) candidates.add(extension)

  for (const format of SUPPORTED_FONT_FORMATS) {
    candidates.add(format)
  }

  for (const candidate of candidates) {
    if (await canParseFont(buffer, candidate)) {
      return candidate
    }
  }

  return null
}

export async function convertFontBuffer(buffer, inputFormat, targetFormat) {
  if (inputFormat === 'woff2' || targetFormat === 'woff2') {
    await ensureWoff2Ready()
  }

  const inputFont = createFont(buffer, { type: inputFormat })
  const ttfObject = inputFont.get()
  const normalizedTtf = Buffer.from(inputFont.write({ type: 'ttf', toBuffer: true }))

  if (targetFormat === 'ttf') {
    return normalizedTtf
  }

  if (targetFormat === 'otf') {
    const parsed = opentype.parse(toArrayBuffer(normalizedTtf))
    const family = ttfObject.name.fontFamily || 'Nimbus Font'
    const subfamily = ttfObject.name.fontSubFamily || 'Regular'
    const fullName = ttfObject.name.fullName || `${family} ${subfamily}`.trim()
    const postScriptName = ttfObject.name.postScriptName || fullName.replace(/\s+/g, '-')

    parsed.names = {
      copyright: { en: '' },
      description: { en: '' },
      designer: { en: '' },
      designerURL: { en: '' },
      fontFamily: { en: family },
      fontSubfamily: { en: subfamily },
      fullName: { en: fullName },
      license: { en: '' },
      licenseURL: { en: '' },
      manufacturer: { en: '' },
      manufacturerURL: { en: '' },
      postScriptName: { en: postScriptName },
      trademark: { en: '' },
      version: { en: ttfObject.name.version || 'Version 1.0' },
    }
    return Buffer.from(parsed.toArrayBuffer())
  }

  return Buffer.from(createFont(normalizedTtf, { type: 'ttf' }).write({ type: targetFormat, toBuffer: true }))
}
