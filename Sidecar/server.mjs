#!/usr/bin/env node
// Nimbus sidecar: local HTTP server that runs the tool pipelines the Swift
// app used to call over the network, now as a loopback-only child process.
//
// Contract with the Swift side (do not change without updating it too):
//  - started as `node Sidecar/server.mjs` with NIMBUS_SIDECAR_SECRET in the
//    environment (never argv — argv is visible via `ps`).
//  - once bound, prints exactly one line to stdout:
//      NIMBUS_SIDECAR_READY {"port":12345}
//    nothing else goes to stdout before that line.
//  - binds only to 127.0.0.1, port 0 (OS-assigned).
//  - every request must carry `X-Nimbus-Secret` matching the env secret, or
//    gets a 401 before any processing happens.
//  - exits when stdin closes, so it never outlives a force-quit parent.

import { createServer } from 'node:http'
import { registerRoute, resolveRoute } from './router.mjs'
import { registerToWebp } from './tools/to-webp.mjs'
import { registerTrimImage } from './tools/trim-image.mjs'
import { registerConvert } from './tools/convert.mjs'
import { registerResize } from './tools/resize.mjs'
import { registerIco } from './tools/ico.mjs'
import { registerPaletteFromImage } from './tools/palette-from-image.mjs'
import { registerDeviceWrapper } from './tools/device-wrapper.mjs'
import { registerFontConvert } from './tools/font-convert.mjs'
import { registerToWebm } from './tools/to-webm.mjs'
import { registerResizeVideo } from './tools/resize-video.mjs'
import { registerWhois } from './tools/whois.mjs'
import { registerDnsCheck } from './tools/dns-check.mjs'
import { registerWordpressInspector } from './tools/wordpress-inspector.mjs'
import { registerPolicyGenerator } from './tools/policy-generator.mjs'
import { registerQrcode } from './tools/qrcode.mjs'
import { registerResponsiveFontClamp } from './tools/responsive-font-clamp.mjs'
import { registerHtmlMinify } from './tools/minify-unminify.mjs'
import { registerJsMinify } from './tools/minify-unminify-js.mjs'
import { registerGeneratePassword } from './tools/generate-password.mjs'
import { registerColorConvert } from './tools/color-convert.mjs'
import { registerContrastCheck } from './tools/contrast-check.mjs'
import { registerWhatsappLink } from './tools/whatsapp-link.mjs'
import { registerJsonCreator } from './tools/json-creator.mjs'
import { registerSiteSpeed } from './tools/site-speed.mjs'
import { registerContractPDF } from './tools/contract-pdf.mjs'
import { registerCopyGenerator } from './tools/copy-generator.mjs'

const secret = process.env.NIMBUS_SIDECAR_SECRET
if (!secret) {
  console.error('NIMBUS_SIDECAR_SECRET is not set in the environment.')
  process.exit(1)
}

registerToWebp(registerRoute)
registerTrimImage(registerRoute)
registerConvert(registerRoute)
registerResize(registerRoute)
registerIco(registerRoute)
registerPaletteFromImage(registerRoute)
registerDeviceWrapper(registerRoute)
registerFontConvert(registerRoute)
registerToWebm(registerRoute)
registerResizeVideo(registerRoute)
registerWhois(registerRoute)
registerDnsCheck(registerRoute)
registerWordpressInspector(registerRoute)
registerPolicyGenerator(registerRoute)
registerQrcode(registerRoute)
registerResponsiveFontClamp(registerRoute)
registerHtmlMinify(registerRoute)
registerJsMinify(registerRoute)
registerGeneratePassword(registerRoute)
registerColorConvert(registerRoute)
registerContrastCheck(registerRoute)
registerWhatsappLink(registerRoute)
registerJsonCreator(registerRoute)
registerSiteSpeed(registerRoute)
registerContractPDF(registerRoute)
registerCopyGenerator(registerRoute)

function toWebRequest(req) {
  const url = `http://127.0.0.1${req.url}`
  const headers = new Headers()
  for (const [name, value] of Object.entries(req.headers)) {
    if (value === undefined) continue
    headers.set(name, Array.isArray(value) ? value.join(', ') : value)
  }

  const hasBody = req.method !== 'GET' && req.method !== 'HEAD'
  return new Request(url, {
    method: req.method,
    headers,
    body: hasBody ? req : undefined,
    duplex: hasBody ? 'half' : undefined,
  })
}

async function sendWebResponse(res, response) {
  const headers = {}
  for (const [name, value] of response.headers) headers[name] = value

  if (!response.body) {
    res.writeHead(response.status, headers)
    res.end()
    return
  }

  const buffer = Buffer.from(await response.arrayBuffer())
  res.writeHead(response.status, headers)
  res.end(buffer)
}

async function handleRequest(req, res) {
  const providedSecret = req.headers['x-nimbus-secret']
  if (providedSecret !== secret) {
    res.writeHead(401, { 'Content-Type': 'text/plain' })
    res.end('Unauthorized')
    return
  }

  const { pathname } = new URL(req.url, 'http://127.0.0.1')
  const handler = resolveRoute(req.method, pathname)
  if (!handler) {
    res.writeHead(404, { 'Content-Type': 'text/plain' })
    res.end('Not Found')
    return
  }

  const response = await handler(toWebRequest(req))
  await sendWebResponse(res, response)
}

const server = createServer((req, res) => {
  handleRequest(req, res).catch((err) => {
    console.error('Unhandled error:', err)
    if (!res.headersSent) res.writeHead(500, { 'Content-Type': 'text/plain' })
    res.end('Internal Error')
  })
})

server.listen(0, '127.0.0.1', () => {
  const { port } = server.address()
  process.stdout.write(`NIMBUS_SIDECAR_READY ${JSON.stringify({ port })}\n`)
})

// Die with the parent: the Swift app closes our stdin (end/close) when it
// shuts down or force-quits, so we don't leak an orphaned Node holding the port.
process.stdin.resume()
process.stdin.on('end', () => process.exit(0))
process.stdin.on('close', () => process.exit(0))
