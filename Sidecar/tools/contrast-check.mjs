// Ported from nimbus/app/api/tools/tools/contrast-check/route.ts, minus
// session/quota.
import tinycolor from 'tinycolor2'

function linearize(c) {
  const s = c / 255
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
}

function relativeLuminance(r, g, b) {
  return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
}

function contrastRatio(l1, l2) {
  const lighter = Math.max(l1, l2)
  const darker = Math.min(l1, l2)
  return (lighter + 0.05) / (darker + 0.05)
}

async function handleContrastCheck(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const foreground = data.get('foreground')
  const background = data.get('background')

  if (!foreground || !background) {
    return Response.json({ error: 'Provide both colors (text color and background color).' }, { status: 400 })
  }

  try {
    const tcFg = tinycolor(foreground)
    const tcBg = tinycolor(background)

    if (!tcFg.isValid()) {
      return Response.json({ error: 'Invalid text color. Use hex, rgb, hsl, or a name (e.g. #000, white).' }, { status: 400 })
    }
    if (!tcBg.isValid()) {
      return Response.json({ error: 'Invalid background color. Use hex, rgb, hsl, or a name (e.g. #fff, black).' }, { status: 400 })
    }

    const rgbFg = tcFg.toRgb()
    const rgbBg = tcBg.toRgb()

    const lFg = relativeLuminance(rgbFg.r, rgbFg.g, rgbFg.b)
    const lBg = relativeLuminance(rgbBg.r, rgbBg.g, rgbBg.b)

    const ratio = Math.round(contrastRatio(lFg, lBg) * 100) / 100

    const aaNormal = ratio >= 4.5
    const aaLarge = ratio >= 3
    const aaaNormal = ratio >= 7
    const aaaLarge = ratio >= 4.5

    return Response.json({
      foreground: {
        hex: tcFg.getAlpha() === 1 ? tcFg.toHexString() : tcFg.toHex8String(),
        rgb: `rgb(${Math.round(rgbFg.r)}, ${Math.round(rgbFg.g)}, ${Math.round(rgbFg.b)})`,
      },
      background: {
        hex: tcBg.getAlpha() === 1 ? tcBg.toHexString() : tcBg.toHex8String(),
        rgb: `rgb(${Math.round(rgbBg.r)}, ${Math.round(rgbBg.g)}, ${Math.round(rgbBg.b)})`,
      },
      ratio,
      wcag: { aaNormal, aaLarge, aaaNormal, aaaLarge },
    })
  } catch (error) {
    console.error('Error checking contrast:', error)
    return Response.json({ error: 'Internal error while checking contrast.' }, { status: 500 })
  }
}

export function registerContrastCheck(registerRoute) {
  registerRoute('POST', '/api/tools/tools/contrast-check', handleContrastCheck)
}
