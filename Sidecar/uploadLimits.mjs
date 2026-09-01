// Size ceilings for the local sidecar.
//
// The web app's limits (10 MB image, 20 MB font, 30 MB video) existed because
// the file crossed the internet and cost bandwidth and quota. Nothing is
// uploaded here — the sidecar runs on the same machine as the file — so those
// numbers only got in the way: a couple of minutes of screen recording clears
// 30 MB easily.
//
// What remains is a memory ceiling, not a product limit. The request body is
// buffered whole (once by the HTTP layer, again by `arrayBuffer()`), so peak
// memory is roughly twice the file. These values are set where that is still
// comfortable on a modern Mac. Handling files past them properly means
// streaming the body to a temp file instead of buffering it, which is a real
// change, not a bigger constant.
const MB = 1024 * 1024

export const MAX_UPLOAD_IMAGE_MB = 250
export const MAX_UPLOAD_IMAGE_BYTES = MAX_UPLOAD_IMAGE_MB * MB
export const MSG_IMAGE_TOO_LARGE = `Imagem acima do limite máximo de ${MAX_UPLOAD_IMAGE_MB} MB.`

export function imageTooLarge(size) {
  return size > MAX_UPLOAD_IMAGE_BYTES
}

export const MAX_UPLOAD_FONT_MB = 100
export const MAX_UPLOAD_FONT_BYTES = MAX_UPLOAD_FONT_MB * MB
export const MSG_FONT_TOO_LARGE = `Fonte acima do limite máximo de ${MAX_UPLOAD_FONT_MB} MB.`

export function fontTooLarge(size) {
  return size > MAX_UPLOAD_FONT_BYTES
}

export const MAX_UPLOAD_VIDEO_MB = 1024
export const MAX_UPLOAD_VIDEO_BYTES = MAX_UPLOAD_VIDEO_MB * MB
export const MSG_VIDEO_TOO_LARGE = `Vídeo acima do limite máximo de ${MAX_UPLOAD_VIDEO_MB} MB.`

export function videoTooLarge(size) {
  return size > MAX_UPLOAD_VIDEO_BYTES
}

export const MAX_UPLOAD_DOCUMENT_MB = 100
export const MAX_UPLOAD_DOCUMENT_BYTES = MAX_UPLOAD_DOCUMENT_MB * MB
export const MSG_DOCUMENT_TOO_LARGE = `This document is larger than the ${MAX_UPLOAD_DOCUMENT_MB} MB limit.`

export function documentTooLarge(size) {
  return size > MAX_UPLOAD_DOCUMENT_BYTES
}
