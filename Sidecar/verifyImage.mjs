// Ported from nimbus/app/utils/verifyImage.ts. Magic bytes, never the file
// extension or the client-supplied content type — both are trivially spoofed.
import { fileTypeFromBuffer } from 'file-type'

export async function verifyImage(buffer) {
  const type = await fileTypeFromBuffer(buffer)
  return !!type && type.mime.startsWith('image/')
}
