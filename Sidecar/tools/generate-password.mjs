// Ported from nimbus/app/api/tools/tools/generate-password/route.ts, minus
// session/quota. Deviation (contract, Slice B item 1): the Next route 400s on
// an empty `input`, but the Swift field is optional — password generation is
// moved outside the `input.length > 0` guard so a password always comes back;
// only the letter-to-number/uppercase transforms stay conditioned on input.
const SYMBOLS = ['@', '!', '*', '$']
const MIN_LENGTH = 8
const MAX_LENGTH = 64
const DEFAULT_LENGTH = 14

function randomSymbol() {
  return SYMBOLS[Math.floor(Math.random() * SYMBOLS.length)]
}

async function handleGeneratePassword(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  let input = String(data.get('input') ?? '')
  const letterToNumber = String(data.get('letterToNumber') ?? 'false') === 'true'
  const enableUpperCase = String(data.get('enableUpperCase') ?? 'false') === 'true'
  const length = Number(data.get('length'))
  const targetLength = Math.min(MAX_LENGTH, Math.max(MIN_LENGTH, Number.isFinite(length) ? length : DEFAULT_LENGTH))

  input = input.toLowerCase().replace(/\s/g, '')

  if (input.length > 0) {
    if (letterToNumber) {
      input = input.replace(/a/gi, '4').replace(/i/gi, '1').replace(/o/gi, '0')
    }
    if (enableUpperCase) {
      input = input
        .split('')
        .map(v => (Math.round(Math.random()) ? v.toUpperCase() : v.toLowerCase()))
        .join('')
    }
  }

  let password = randomSymbol() + input + randomSymbol() + Math.random().toString(32).slice(-2)
  while (password.length < targetLength) {
    password += Math.random().toString(36).substring(2, 3)
  }
  if (password.length > targetLength) {
    password = password.slice(0, targetLength)
  }

  return Response.json({ password })
}

export function registerGeneratePassword(registerRoute) {
  registerRoute('POST', '/api/tools/tools/generate-password', handleGeneratePassword)
}
