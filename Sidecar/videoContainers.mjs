// Shared by to-webm.mjs and resize-video.mjs — the two ffmpeg-based video
// tools — so both agree on which container an input video maps to when its
// container is being *preserved* rather than converted, and share the one
// VP9 quality formula instead of each keeping its own copy. Same spirit as
// verifyImage.mjs / verifyVideo.mjs: a small shared module, not a framework.
export const WEBM_CONTAINER = { ext: 'webm', contentType: 'video/webm' }
export const DEFAULT_CONTAINER = { ext: 'mp4', contentType: 'video/mp4' }

// `file-type` reports mkv as "video/matroska" (verified against its real
// output), not the "video/x-matroska" IANA-style name — both keys are
// mapped here so detection works regardless, while the container's
// Content-Type stays "video/x-matroska".
const MKV_CONTAINER = { ext: 'mkv', contentType: 'video/x-matroska' }

const CONTAINER_BY_MIME = {
  'video/mp4': DEFAULT_CONTAINER,
  'video/quicktime': { ext: 'mov', contentType: 'video/quicktime' },
  'video/x-matroska': MKV_CONTAINER,
  'video/matroska': MKV_CONTAINER,
  'video/webm': WEBM_CONTAINER,
}

// Anything not in the table (an oddball container that still sniffs as
// video/*) falls back to mp4.
export function containerForMime(mime) {
  return CONTAINER_BY_MIME[mime] ?? DEFAULT_CONTAINER
}

export function isWebmContainer(container) {
  return container.ext === 'webm'
}

// Score 1-100: higher = better (same scale as the "lustroso" = 90% image preset).
export function vp9LossyParams(score) {
  const q = Math.max(1, Math.min(100, score))
  const crf = Math.round(63 - ((q - 1) * (63 - 20)) / 99)
  const bitrate = Math.round(10 + ((q - 1) * (1000 - 10)) / 99)
  const maxWidth = Math.round(320 + ((q - 1) * (1080 - 320)) / 99)
  return { crf, bitrate, maxWidth }
}
