// New tool, no site route to port from. Reuses the ffmpeg-static/temp-file
// plumbing resize-video.mjs and to-webm.mjs already established — same
// checkFfmpegBinary startup guard, same tmpdir()/randomUUID() staging, same
// execFile/cleanup shape. Simpler than those two: no video filter, no
// container choice — output is always mp3/audio-mpeg.
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

const execFileAsync = promisify(execFile)
const BITRATES = ['128', '192', '320']

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

function ffmpegArgs(inputPath, outputPath, bitrate) {
  return [
    '-y', '-loglevel', 'error',
    '-i', inputPath,
    '-vn',
    '-c:a', 'libmp3lame', '-b:a', `${bitrate}k`,
    outputPath,
  ]
}

async function cleanup(...paths) {
  await Promise.all(paths.map((path) => unlink(path).catch(() => {})))
}

async function handleToMp3(request) {
  if (!ffmpegAvailable) {
    return new Response('Audio converter unavailable: ffmpeg binary not found.', { status: 500 })
  }

  const data = await request.formData()
  const file = data.get('video')
  const bitrateRaw = data.get('bitrate')?.toString() ?? '192'
  const bitrate = BITRATES.includes(bitrateRaw) ? bitrateRaw : '192'

  if (!(file instanceof File)) {
    return new Response("No video provided. Send a file in the 'video' field.", { status: 400 })
  }
  if (videoTooLarge(file.size)) {
    return Response.json({ error: MSG_VIDEO_TOO_LARGE }, { status: 413 })
  }

  const buffer = Buffer.from(await file.arrayBuffer())
  const detectedMime = await verifyVideo(buffer)
  if (!detectedMime) {
    return new Response('Unsupported file. Send a valid video.', { status: 400 })
  }

  const tmpPath = join(tmpdir(), 'nimbus-to-mp3')
  await mkdir(tmpPath, { recursive: true })

  const fileId = randomUUID()
  const inputExt = file.name.split('.').pop() || 'mp4'
  const inputPath = join(tmpPath, `${fileId}.${inputExt}`)
  const outputPath = join(tmpPath, `${fileId}-output.mp3`)

  await writeFile(inputPath, buffer)

  try {
    await execFileAsync(ffmpegPath, ffmpegArgs(inputPath, outputPath, bitrate), {
      maxBuffer: 10 * 1024 * 1024,
    })
  } catch (err) {
    await cleanup(inputPath, outputPath)
    console.error('ffmpeg failed for to-mp3:', err)
    return new Response('Error converting the file.', { status: 500 })
  }

  let outputBuffer
  try {
    outputBuffer = await readFile(outputPath)
  } finally {
    await cleanup(inputPath, outputPath)
  }

  return new Response(outputBuffer, {
    status: 200,
    headers: { 'Content-Type': 'audio/mpeg' },
  })
}

export function registerToMp3(registerRoute) {
  registerRoute('POST', '/api/tools/studio/to-mp3', handleToMp3)
}