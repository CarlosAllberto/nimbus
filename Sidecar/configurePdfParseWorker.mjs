import './pdfNodeSetup.mjs'
import { existsSync } from 'node:fs'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { dirname, join } from 'node:path'
import { PDFParse } from 'pdf-parse'

let configured = false
const sidecarRoot = dirname(fileURLToPath(import.meta.url))

/**
 * Points pdf-parse's pdfjs worker at an absolute file:// URL, resolved
 * against this file's own location rather than process.cwd() — the sidecar
 * is launched with an unpredictable working directory.
 */
export function configurePdfParseWorker() {
  if (configured) return
  configured = true
  const candidates = [
    join(sidecarRoot, 'node_modules', 'pdf-parse', 'node_modules', 'pdfjs-dist', 'legacy', 'build', 'pdf.worker.mjs'),
    join(sidecarRoot, 'node_modules', 'pdfjs-dist', 'legacy', 'build', 'pdf.worker.mjs'),
  ]
  for (const workerPath of candidates) {
    if (existsSync(workerPath)) {
      PDFParse.setWorker(pathToFileURL(workerPath).href)
      return
    }
  }
}
