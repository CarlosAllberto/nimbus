// Ported from nimbus/app/api/tools/studio/resize-video/route.ts, reusing the
// ffmpeg/temp-file plumbing from to-webm.mjs and the shared container
// mapping in videoContainers.mjs. Deliberate departure from the site,
// requested: the site always outputs mp4 with `-c:a copy`, which breaks (or
// silently corrupts) when the input's audio codec — e.g. Opus in a WebM —
// isn't legal inside an mp4 container. This preserves the input container
// instead, the same principle Resize Image already uses for image format.
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
import { containerForMime, isWebmContainer, vp9LossyParams } from '../videoContainers.mjs'

const execFileAsync = promisify(execFile)

// Checked once at startup, same as to-webm.mjs — see that file for why a
// missing binary fails only this route instead of the whole sidecar.
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

// The site has no quality preset on this tool — always libx264 preset fast
// crf 23. The webm branch (only reachable now that the container is
// preserved) uses the equivalent "lustroso" (score 90) vp9 tier from
// to-webm's formula so quality lands in the same ballpark, nothing invented.
const { crf: WEBM_CRF, bitrate: WEBM_BITRATE } = vp9LossyParams(90)

const AUDIO_REENCODE_BY_EXT = {
  webm: ['-c:a', 'libopus', '-b:a', '128k'],
  mp4: ['-c:a', 'aac', '-b:a', '192k'],
  mov: ['-c:a', 'aac', '-b:a', '192k'],
  mkv: ['-c:a', 'aac', '-b:a', '192k'],
}

function videoArgs(container) {
  return isWebmContainer(container)
    ? ['-c:v', 'libvpx-vp9', '-b:v', `${WEBM_BITRATE}k`, '-crf', String(WEBM_CRF), '-deadline', 'realtime', '-cpu-used', '8']
    : ['-c:v', 'libx264', '-preset', 'fast', '-crf', '23']
}

function ffmpegArgs(inputPath, outputPath, scaleFilter, container, audioArgs) {
  return [
    '-y', '-loglevel', 'error',
    '-i', inputPath,
    '-vf', scaleFilter,
    ...videoArgs(container),
    ...audioArgs,
    outputPath,
  ]
}

async function cleanup(...paths) {
  await Promise.all(paths.map((path) => unlink(path).catch(() => {})))
}

async function handleResizeVideo(request) {
  if (!ffmpegAvailable) {
    return new Response('Conversor de vídeo indisponível: binário do ffmpeg não encontrado.', { status: 500 })
  }

  const data = await request.formData()
  const file = data.get('video')
  const parsedWidth = Number(data.get('width'))
  const size = Number.isFinite(parsedWidth) && parsedWidth > 0 ? parsedWidth : 1280
  const resizeBy = data.get('resizeBy')?.toString() === 'height' ? 'height' : 'width'

  if (!(file instanceof File)) {
    return new Response("Nenhum vídeo fornecido. Envie um arquivo no campo 'video'.", { status: 400 })
  }
  if (videoTooLarge(file.size)) {
    return Response.json({ error: MSG_VIDEO_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  const detectedMime = await verifyVideo(buffer)
  if (!detectedMime) {
    return new Response('Arquivo não suportado. Envie um vídeo válido.', { status: 400 })
  }

  const container = containerForMime(detectedMime)
  // scale=W:-2 or scale=-2:H keeps aspect ratio, -2 rounds to an even dimension.
  const scaleFilter = resizeBy === 'height' ? `scale=-2:${size}` : `scale=${size}:-2`

  const tmpPath = join(tmpdir(), 'nimbus-resize-video')
  await mkdir(tmpPath, { recursive: true })

  const fileId = randomUUID()
  const inputExt = file.name.split('.').pop() || 'mp4'
  const inputPath = join(tmpPath, `${fileId}.${inputExt}`)
  const outputPath = join(tmpPath, `${fileId}-resized.${container.ext}`)

  await writeFile(inputPath, buffer)

  const execOptions = { maxBuffer: 50 * 1024 * 1024 }

  try {
    await execFileAsync(
      ffmpegPath,
      ffmpegArgs(inputPath, outputPath, scaleFilter, container, ['-c:a', 'copy']),
      execOptions,
    )
  } catch (copyErr) {
    // Output stays in the same container as the input, so `-c:a copy` should
    // essentially always work — this fallback exists for the rare case
    // ffmpeg rejects the stream copy anyway, so a resize never hard-fails
    // over an audio codec quirk the way the site's always-mp4 copy could.
    try {
      await execFileAsync(
        ffmpegPath,
        ffmpegArgs(inputPath, outputPath, scaleFilter, container, AUDIO_REENCODE_BY_EXT[container.ext]),
        execOptions,
      )
    } catch (reencodeErr) {
      await cleanup(inputPath, outputPath)
      console.error('ffmpeg failed for resize-video (copy):', copyErr)
      console.error('ffmpeg failed for resize-video (reencode fallback):', reencodeErr)
      return new Response('Erro ao redimensionar o vídeo.', { status: 500 })
    }
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

export function registerResizeVideo(registerRoute) {
  registerRoute('POST', '/api/tools/studio/resize-video', handleResizeVideo)
}
