// No route.ts on the Next site — this ported route is new (contract: Slice B,
// "JSON Creator"). The logic comes from `nimbus/components/json-creator.tsx`
// (`nodeToValue`/`arrayItemToValue`), adapted to the flattened
// `{key, value, type}` list model the Swift side already uses (no nested
// children/items, unlike the site's recursive tree). For `object`/`array`
// typed properties, the Value field carries that sub-value's raw JSON text;
// parsing it is the one piece of logic the flattened model needs that the
// site's recursive version didn't.
class JsonCreatorError extends Error {}

function itemToValue(item, label) {
  const type = item?.type
  switch (type) {
    case 'string':
      return item.value ?? ''
    case 'number':
      return item.value === '' || item.value === undefined ? 0 : Number(item.value)
    case 'boolean':
      return item.value === 'true'
    case 'null':
      return null
    case 'object':
    case 'array':
      try {
        return JSON.parse(item.value ?? '')
      } catch {
        throw new JsonCreatorError(`Invalid JSON in the Value field for "${label}".`)
      }
    default:
      return undefined
  }
}

async function handleJsonCreator(request) {
  let data
  try {
    data = await request.formData()
  } catch {
    return Response.json({ error: 'Invalid request payload' }, { status: 400 })
  }

  const structure = String(data.get('structure') ?? '')
  if (structure !== 'object' && structure !== 'array') {
    return Response.json({ error: 'Structure must be "object" or "array".' }, { status: 400 })
  }

  let properties
  try {
    properties = JSON.parse(String(data.get('properties') ?? '[]'))
  } catch {
    return Response.json({ error: 'Invalid properties data.' }, { status: 400 })
  }
  if (!Array.isArray(properties)) {
    return Response.json({ error: 'Invalid properties data.' }, { status: 400 })
  }

  try {
    let json
    if (structure === 'object') {
      const obj = {}
      for (const item of properties) {
        const key = String(item?.key ?? '').trim()
        if (key === '') continue
        obj[key] = itemToValue(item, key)
      }
      json = obj
    } else {
      // Arrays have no key — order is the only thing that matters.
      json = properties.map((item, index) => itemToValue(item, `item ${index + 1}`))
    }
    return Response.json({ json })
  } catch (error) {
    if (error instanceof JsonCreatorError) {
      return Response.json({ error: error.message }, { status: 400 })
    }
    console.error('Error in json-creator:', error)
    return Response.json({ error: 'Internal error while building JSON.' }, { status: 500 })
  }
}

export function registerJsonCreator(registerRoute) {
  registerRoute('POST', '/api/tools/code/json-creator', handleJsonCreator)
}
