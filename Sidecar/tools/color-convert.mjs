// Ported from nimbus/app/api/tools/tools/color-convert/route.ts, minus
// session/quota.
import tinycolor from 'tinycolor2'

async function handleColorConvert(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const color = data.get('color')
  if (!color) {
    return Response.json({ error: 'Color is required (e.g. #ffffff, rgb(255,255,255), red)' }, { status: 400 })
  }

  try {
    const tc = tinycolor(color)
    if (!tc.isValid()) {
      return Response.json({ error: 'Invalid color format. Try hex, rgb, hsl, or a color name (e.g. red).' }, { status: 400 })
    }

    const rgbObj = tc.toRgb()

    return Response.json({
      original: color,
      hex: tc.getAlpha() === 1 ? tc.toHexString() : tc.toHex8String(),
      rgb: `rgb(${Math.round(rgbObj.r)}, ${Math.round(rgbObj.g)}, ${Math.round(rgbObj.b)})`,
      rgba: `rgba(${Math.round(rgbObj.r)}, ${Math.round(rgbObj.g)}, ${Math.round(rgbObj.b)}, ${rgbObj.a})`,
      hsl: tc.toHslString(),
    })
  } catch (error) {
    console.error('Error converting color:', error)
    return Response.json({ error: 'Internal error while processing the request' }, { status: 500 })
  }
}

export function registerColorConvert(registerRoute) {
  registerRoute('POST', '/api/tools/tools/color-convert', handleColorConvert)
}
