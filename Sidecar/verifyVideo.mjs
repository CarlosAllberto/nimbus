// Ported from nimbus/app/utils/verifyVideo.ts. Magic bytes, never the file
// extension or the client-supplied content type — same rule as verifyImage.mjs.
//
// Deliberate divergence from the site: to-webm/route.ts never called this —
// it only checked size. Every tool in this sidecar validates content, so
// to-webm.mjs uses this too, instead of handing an unverified file to ffmpeg.
//
// Returns the detected mime (e.g. "video/mp4") instead of a bare boolean —
// to-webm's convertToWebm=0 mode needs the input container to pick the
// matching output container, so the sniff result is worth keeping.
import { fileTypeFromBuffer } from 'file-type'

export async function verifyVideo(buffer) {
  const type = await fileTypeFromBuffer(buffer)
  if (!type || !type.mime.startsWith('video/')) return null
  return type.mime
}
