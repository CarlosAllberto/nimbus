// Ported from nimbus/app/api/tools/web/responsive-font-clamp/route.ts, minus
// session/quota. No parity deviations (Slice B item 4 in the contract):
// `mobileFont` empty is already the "automatic" signal on both sides.
const REM_ROOT_PX = 16
const RECOMMENDED_MOBILE_RATIO = 2 / 3
const MIN_MOBILE_FONT_PX = 16
const RECOMMENDED_NOTE =
  'mobileUsed = max(16, round(desktopFont * 0.6667)); avoids repeated sizes across a list'
const MAX_DESKTOP_SIZES = 20

function roundDecimals(n, places) {
  const f = 10 ** places
  return Math.round(n * f) / f
}

function toEvenPx(value) {
  const rounded = Math.round(value)
  return rounded % 2 === 0 ? rounded : rounded + 1
}

function parseDesktopFontList(deskRaw) {
  if (deskRaw === undefined || deskRaw === null || deskRaw === '') {
    return { ok: false, error: 'Enter at least one desktop font size (desktopFont).' }
  }
  const parts = String(deskRaw).split(',').map(s => s.trim()).filter(Boolean)
  if (parts.length === 0) {
    return { ok: false, error: 'Desktop font size list is empty. Example: 64, 48, 32' }
  }
  if (parts.length > MAX_DESKTOP_SIZES) {
    return { ok: false, error: `A maximum of ${MAX_DESKTOP_SIZES} sizes per request.` }
  }
  const values = []
  for (let i = 0; i < parts.length; i++) {
    const n = Number(parts[i])
    if (!Number.isFinite(n) || n <= 0) {
      return { ok: false, error: `Invalid size at position ${i + 1}: "${parts[i]}". Use numbers greater than zero.` }
    }
    values.push(n)
  }
  return { ok: true, values }
}

function formatCssClamp(desktopFontPx, mobileUsedPx, minViewport, maxViewport, unit, rootPx) {
  const slope = (desktopFontPx - mobileUsedPx) / (maxViewport - minViewport)
  const interceptPx = mobileUsedPx - slope * minViewport
  const slopeStr = roundDecimals(slope, 6).toString()
  const minPx = Math.min(mobileUsedPx, desktopFontPx)
  const maxPx = Math.max(mobileUsedPx, desktopFontPx)

  if (unit === 'px') {
    const interceptStr = roundDecimals(interceptPx, 4).toString()
    const clampMiddle = `calc(${interceptStr}px + ${slopeStr} * 100vw)`
    const clampValue = `clamp(${minPx}px, ${clampMiddle}, ${maxPx}px)`
    return { clampValue, cssProperty: `font-size: ${clampValue};`, slope, interceptPx }
  }

  const toRem = px => roundDecimals(px / rootPx, 4)
  const interceptRem = toRem(interceptPx)
  const minRem = toRem(minPx)
  const maxRem = toRem(maxPx)
  const clampMiddle = `calc(${interceptRem}rem + ${slopeStr} * 100vw)`
  const clampValue = `clamp(${minRem}rem, ${clampMiddle}, ${maxRem}rem)`
  return { clampValue, cssProperty: `font-size: ${clampValue};`, slope, interceptPx }
}

async function handleResponsiveFontClamp(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const parsed = parseDesktopFontList(data.get('desktopFont'))
  if (!parsed.ok) {
    return Response.json({ error: parsed.error }, { status: 400 })
  }
  const desktopList = parsed.values

  const minViewport = Number(data.get('minViewport'))
  const maxViewport = Number(data.get('maxViewport'))

  if (!Number.isFinite(minViewport) || minViewport <= 0) {
    return Response.json({ error: 'Minimum viewport width (minViewport) must be a number greater than zero.' }, { status: 400 })
  }
  if (!Number.isFinite(maxViewport) || maxViewport <= 0) {
    return Response.json({ error: 'Maximum viewport width (maxViewport) must be a number greater than zero.' }, { status: 400 })
  }
  if (minViewport >= maxViewport) {
    return Response.json({ error: 'The minimum width must be less than the maximum width.' }, { status: 400 })
  }

  const unit = String(data.get('unit') ?? '') === 'rem' ? 'rem' : 'px'
  const rootPx = REM_ROOT_PX

  const mobileRaw = data.get('mobileFont')
  const mobileEmpty = mobileRaw === undefined || mobileRaw === null || String(mobileRaw).trim() === ''

  let fixedMobilePx = null
  let mobileMode

  if (mobileEmpty) {
    mobileMode = 'recommended'
  } else {
    const mf = Number(mobileRaw)
    if (!Number.isFinite(mf) || mf <= 0) {
      return Response.json(
        { error: 'Mobile font size must be a number greater than zero, or leave it empty for the recommended size.' },
        { status: 400 },
      )
    }
    mobileMode = 'fixed'
    fixedMobilePx = roundDecimals(mf, 2)
  }

  let recommendedByIndex = null
  if (mobileMode === 'recommended') {
    const ordered = desktopList
      .map((desktopFontPx, idx) => ({ idx, desktopFontPx }))
      .sort((a, b) => a.desktopFontPx - b.desktopFontPx)

    recommendedByIndex = new Array(desktopList.length)
    let prevAssigned = null

    for (const item of ordered) {
      let mobileCandidate = Math.max(MIN_MOBILE_FONT_PX, toEvenPx(item.desktopFontPx * RECOMMENDED_MOBILE_RATIO))

      if (prevAssigned != null && mobileCandidate <= prevAssigned) {
        mobileCandidate = prevAssigned + 2
      }

      const evenDesktopMax = Math.floor(item.desktopFontPx / 2) * 2
      mobileCandidate = Math.min(mobileCandidate, evenDesktopMax)
      mobileCandidate = Math.max(MIN_MOBILE_FONT_PX, mobileCandidate)

      recommendedByIndex[item.idx] = mobileCandidate
      prevAssigned = mobileCandidate
    }
  }

  const results = desktopList.map((desktopFontPx, idx) => {
    let mobileUsed
    let formulaNote

    if (mobileMode === 'recommended') {
      mobileUsed = recommendedByIndex?.[idx] ?? MIN_MOBILE_FONT_PX
      formulaNote = RECOMMENDED_NOTE
    } else {
      mobileUsed = Math.max(MIN_MOBILE_FONT_PX, toEvenPx(fixedMobilePx))
    }

    const { clampValue, cssProperty, slope, interceptPx } = formatCssClamp(
      desktopFontPx, mobileUsed, minViewport, maxViewport, unit, rootPx,
    )

    return {
      cssProperty,
      clampValue,
      meta: {
        mobileUsed,
        desktopFont: desktopFontPx,
        minViewport,
        maxViewport,
        slope: roundDecimals(slope, 8),
        interceptPx: roundDecimals(interceptPx, 6),
        mobileMode,
        unit,
        rootPx: unit === 'rem' ? rootPx : undefined,
        ...(formulaNote ? { note: formulaNote } : {}),
      },
    }
  })

  return Response.json({ results })
}

export function registerResponsiveFontClamp(registerRoute) {
  registerRoute('POST', '/api/tools/web/responsive-font-clamp', handleResponsiveFontClamp)
}
