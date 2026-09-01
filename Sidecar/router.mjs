const routes = new Map()

function key(method, pathname) {
  return `${method} ${pathname}`
}

/**
 * Registers a handler for a method + exact pathname.
 * handler: (request: Request) => Promise<Response>
 */
export function registerRoute(method, pathname, handler) {
  routes.set(key(method, pathname), handler)
}

export function resolveRoute(method, pathname) {
  return routes.get(key(method, pathname)) ?? null
}
