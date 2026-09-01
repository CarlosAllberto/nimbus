// Ported from nimbus/app/api/tools/tools/whatsapp-link/route.ts, minus
// session/quota.
async function handleWhatsappLink(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const phone = String(data.get('phone') ?? '')
  const text = String(data.get('text') ?? '')
  const type = String(data.get('type') ?? '')

  if (!phone) {
    return Response.json({ error: 'Phone number is required' }, { status: 400 })
  }

  const cleanPhone = phone.replace(/\D/g, '')
  const encodedText = text ? encodeURIComponent(text) : ''

  let link = ''
  switch (type) {
    case 'api':
      link = `https://api.whatsapp.com/send/?phone=${cleanPhone}${encodedText ? `&text=${encodedText}` : ''}`
      break
    case 'web':
      link = `https://web.whatsapp.com/send/?phone=${cleanPhone}${encodedText ? `&text=${encodedText}` : ''}`
      break
    case 'wa.me':
    default:
      link = `https://wa.me/${cleanPhone}${encodedText ? `?text=${encodedText}` : ''}`
      break
  }

  return Response.json({ link })
}

export function registerWhatsappLink(registerRoute) {
  registerRoute('POST', '/api/tools/tools/whatsapp-link', handleWhatsappLink)
}
