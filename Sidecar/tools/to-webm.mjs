// Ported from nimbus/app/api/tools/web/to-webm/route.ts — same VP9/Opus
// pipeline and quality formulas, minus session/Supabase/quota (no auth in
// this version). Deliberate departures from the site, all requested:
//  - ffmpeg path comes from `ffmpeg-static`'s own export, not a join() against
//    process.cwd()/process.env.PWD — the sidecar's working directory is
//    whatever the Swift app happened to launch it from, so that join breaks.
//  - the site never validates this endpoint's upload by magic bytes (only
//    size). Every other tool here does, so this one sniffs `video/*` too
//    instead of handing an unverified file straight to ffmpeg.
//  - new: `convertToWebm` field (same "0" disables, anything else/absence
//    enables convention as to-webp's `convertToWebp`). Off, it re-encodes
//    keeping the detected input container instead of always producing webm —
//    the site's to-webm has no such mode, it always converts.
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import { writeFile, readFile, mkdir, unlink } from 'node:fs/promises'
import fs, { constants as fsConstants } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { randomUUID } from 'node:crypto'
import ffmpegPath from 'ffmpeg-static'
import { verifyVideo } from '../verifyVideo.mjs'
import { videoTooLarge, MSG_VIDEO_TOO_LARGE } from '../uploadLimits.mjs'
import { WEBM_CONTAINER, containerForMime, vp9LossyParams } from '../videoContainers.mjs'

const execFileAsync = promisify(execFile)
const PRESETS = ['perda', 'lustroso', 'sem-perdas']

const X264_CRF_BY_PRESET = { 'sem-perdas': 0, lustroso: 23, perda: 30 }
const AAC_BITRATE_BY_PRESET = { 'sem-perdas': '128k', lustroso: '128k', perda: '96k' }

// Checked once at startup ("ao subir"), not on first request — a missing or
// non-executable binary should read as a clear log line here, never as a
// raw ENOENT/EACCES bubbling out of execFile on someone's first click.
function checkFfmpegBinary() {
  if (!ffmpegPath) {
    console.error('ffmpeg-static did not resolve a binary path for this platform.')
    return false
  }
  try {
    fs.accessSync(ffmpegPath, fsConstants.X_OK)
    return true
  } catch (err) {
    console.error(`ffmpeg binary at ${ffmpegPath} is missing or not executable:`, err.message)
    return false
  }
}

const ffmpegAvailable = checkFfmpegBinary()

function vp9Args(inputPath, outputPath, webmPreset) {
  if (webmPreset === 'sem-perdas') {
    return [
      '-y', '-loglevel', 'error',
      '-i', inputPath,
      '-c:v', 'libvpx-vp9', '-lossless', '1', '-row-mt', '1', '-deadline', 'good', '-cpu-used', '2',
      '-c:a', 'libopus', '-b:a', '128k', '-ac', '2',
      outputPath,
    ]
  }

  const score = webmPreset === 'lustroso' ? 90 : 42
  const { crf, bitrate, maxWidth } = vp9LossyParams(score)
  return [
    '-y', '-loglevel', 'error',
    '-i', inputPath,
    '-c:v', 'libvpx-vp9', '-b:v', `${bitrate}k`, '-crf', String(crf),
    '-vf', `scale='min(${maxWidth},iw)':-2`,
    '-deadline', 'realtime', '-cpu-used', '8',
    '-c:a', 'libopus', '-b:a', '16k', '-ac', '1',
    outputPath,
  ]
}

// convertToWebm=0 into an mp4/mov/mkv container: same three-tier quality
// preset, mapped onto x264/aac instead of vp9/opus. -crf 0 is genuinely
// lossless and can land larger than the input — that's correct, not a bug.
function x264Args(inputPath, outputPath, webmPreset) {
  return [
    '-y', '-loglevel', 'error',
    '-i', inputPath,
    '-c:v', 'libx264', '-crf', String(X264_CRF_BY_PRESET[webmPreset]), '-preset', 'veryfast',
    '-c:a', 'aac', '-b:a', AAC_BITRATE_BY_PRESET[webmPreset],
    outputPath,
  ]
}

function ffmpegArgs(inputPath, outputPath, webmPreset, container) {
  return container.ext === 'webm'
    ? vp9Args(inputPath, outputPath, webmPreset)
    : x264Args(inputPath, outputPath, webmPreset)
}

async function cleanup(...paths) {
  await Promise.all(paths.map((path) => unlink(path).catch(() => {})))
}

async function handleToWebm(request) {
  if (!ffmpegAvailable) {
    return new Response('Conversor de vídeo indisponível: binário do ffmpeg não encontrado.', { status: 500 })
  }

  const data = await request.formData()
  const file = data.get('video')
  const presetRaw = data.get('webmPreset')?.toString() ?? 'lustroso'
  const webmPreset = PRESETS.includes(presetRaw) ? presetRaw : 'lustroso'
  const convertToWebm = data.get('convertToWebm')?.toString() !== '0'

  if (!(file instanceof File)) {
    return new Response("Nenhum vídeo fornecido. Envie um arquivo no campo 'video'.", { status: 400 })
  }
  if (videoTooLarge(file.size)) {
    return Response.json({ error: MSG_VIDEO_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  const detectedMime = await verifyVideo(buffer)
  if (!detectedMime) {
    return new Response('Arquivo não suportado', { status: 400 })
  }

  const container = convertToWebm ? WEBM_CONTAINER : containerForMime(detectedMime)

  const tmpPath = join(tmpdir(), 'nimbus-to-webm')
  await mkdir(tmpPath, { recursive: true })

  const fileId = randomUUID()
  const inputExt = file.name.split('.').pop() || 'mp4'
  const inputPath = join(tmpPath, `${fileId}.${inputExt}`)
  const outputPath = join(tmpPath, `${fileId}-output.${container.ext}`)

  await writeFile(inputPath, buffer)

  try {
    await execFileAsync(ffmpegPath, ffmpegArgs(inputPath, outputPath, webmPreset, container), {
      maxBuffer: 10 * 1024 * 1024,
    })
  } catch (err) {
    await cleanup(inputPath, outputPath)
    console.error('ffmpeg failed for to-webm:', err)
    return new Response('Erro ao processar o vídeo.', { status: 500 })
  }

  let outputBuffer
  try {
    outputBuffer = await readFile(outputPath)
  } finally {
    await cleanup(inputPath, outputPath)
  }

  return new Response(outputBuffer, {
    status: 200,
    headers: { 'Content-Type': container.contentType },
  })
}

export function registerToWebm(registerRoute) {
  registerRoute('POST', '/api/tools/web/to-webm', handleToWebm)
}
