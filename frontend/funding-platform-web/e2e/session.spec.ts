import { expect, test } from '@playwright/test'
import { execFileSync } from 'node:child_process'
import { createServer } from 'node:https'

// Only the reserved fixture hosts resolve to loopback; other hosts keep normal DNS/TLS.
test.use({
  launchOptions: { args: [
    '--host-resolver-rules=MAP funding-session-app.test 127.0.0.1, MAP unrelated-session-site.test 127.0.0.1, MAP funding-session-api.test 127.0.0.1',
  ] },
})

test.describe('CHIPS con servidor HTTPS sintético', () => {
test.use({ ignoreHTTPSErrors: true })

test('sesión cross-site: conserva la cookie entre ventanas, aísla otros sitios y permite salir', async ({ context, page }) => {
  // Different registrable sites, resolved only to loopback. Generate test-only TLS in memory.
  // Use actual HTTP responses: intercepted fulfillment may alter cookie semantics.
  const pem = execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', '/dev/stdout', '-out', '/dev/stdout', '-subj', '/CN=funding-session-api.test', '-days', '1'],
  { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
  let app: string, other: string, api: string, html: string
  const cookieName = '__Secure-fp_refresh_partitioned'
  const attributes = '; Path=/api/v1/auth; HttpOnly; Secure; SameSite=None; Partitioned'
  const unexpected: string[] = []
  const server = createServer({ key: pem, cert: pem }, (request, response) => {
    const origin = `https://${request.headers.host}`
    if ([app, other].includes(origin)) {
      response.writeHead(200, { 'content-type': 'text/html' })
      response.end(html)
      return
    }
    const caller = request.headers.origin ?? ''
    if (origin !== api || ![app, other].includes(caller) ||
        !['/api/v1/auth/login', '/api/v1/auth/refresh', '/api/v1/auth/logout'].includes(request.url ?? '')) {
      unexpected.push('unexpected fixture request')
      response.writeHead(403).end()
      return
    }
    const headers: Record<string, string> = {
      'access-control-allow-origin': caller,
      'access-control-allow-credentials': 'true',
      'cache-control': 'no-store',
      'content-type': 'text/plain',
    }
    let active = (request.headers.cookie ?? '').split(';').some(value => value.trim() === `${cookieName}=synthetic-only`)
    if (request.url?.endsWith('/login')) {
      headers['set-cookie'] = `${cookieName}=synthetic-only; Max-Age=2592000${attributes}`
      active = true
    } else if (request.url?.endsWith('/logout')) {
      headers['set-cookie'] = `${cookieName}=; Expires=Thu, 01 Jan 1970 00:00:00 GMT${attributes}`
      active = false
    }
    response.writeHead(200, headers)
    response.end(active ? 'Activa' : 'Sin sesión')
  })
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve))
  const address = server.address()
  if (!address || typeof address === 'string') throw new Error('Loopback fixture failed to bind')
  app = `https://funding-session-app.test:${address.port}`
  other = `https://unrelated-session-site.test:${address.port}`
  api = `https://funding-session-api.test:${address.port}`
  html = `<!doctype html><html lang="es"><title>Sesión sintética</title><body>
    <button data-action="login">Iniciar</button><button data-action="refresh">Comprobar</button>
    <button data-action="logout">Salir</button><output aria-live="polite">Sin comprobar</output>
    <script>document.querySelectorAll('button').forEach(button => button.onclick = async () => {
      document.querySelector('output').textContent = 'Comprobando';
      const response = await fetch('${api}/api/v1/auth/' + button.dataset.action, {method:'POST', credentials:'include'});
      document.querySelector('output').textContent = await response.text();
    });</script></body></html>`
  await context.route('**/*', async route => {
    if ([app, other, api].includes(new URL(route.request().url()).origin)) { await route.continue(); return }
    unexpected.push(route.request().url())
    await route.abort('blockedbyclient')
  })
  try {
    await page.goto(app)
    await page.getByRole('button', { name: 'Iniciar' }).click()
    await expect(page.getByRole('status')).toHaveText('Activa')
    await page.reload()
    await page.getByRole('button', { name: 'Comprobar' }).click()
    await expect(page.getByRole('status')).toHaveText('Activa')

    const secondWindow = await context.newPage()
    await secondWindow.goto(app)
    await secondWindow.getByRole('button', { name: 'Comprobar' }).click()
    await expect(secondWindow.getByRole('status')).toHaveText('Activa')

    const unrelatedWindow = await context.newPage()
    await unrelatedWindow.goto(other)
    await unrelatedWindow.getByRole('button', { name: 'Comprobar' }).click()
    await expect(unrelatedWindow.getByRole('status')).toHaveText('Sin sesión')
    await unrelatedWindow.getByRole('button', { name: 'Iniciar' }).click()
    await expect(unrelatedWindow.getByRole('status')).toHaveText('Activa')

    await secondWindow.getByRole('button', { name: 'Salir' }).click()
    await expect(secondWindow.getByRole('status')).toHaveText('Sin sesión')
    await page.getByRole('button', { name: 'Comprobar' }).click()
    await expect(page.getByRole('status')).toHaveText('Sin sesión')
    await unrelatedWindow.getByRole('button', { name: 'Comprobar' }).click()
    await expect(unrelatedWindow.getByRole('status')).toHaveText('Activa')
    expect(unexpected).toEqual([])
  } finally {
    server.closeAllConnections()
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()))
  }
})
})

test('la aplicación serializa la renovación entre dos ventanas y libera el bloqueo al terminar', async ({ context, page }) => {
  const unexpected: string[] = []
  let requests = 0
  let inFlight = 0
  let maximumInFlight = 0
  let releaseFirst!: () => void
  const firstResponse = new Promise<void>(resolve => { releaseFirst = resolve })
  await context.route('**/api/v1/**', async route => {
    unexpected.push(route.request().url())
    await route.abort('blockedbyclient')
  })
  await context.route('**/api/v1/auth/external/providers', route => route.fulfill({ json: [] }))
  await context.route('**/api/v1/auth/refresh', async route => {
    requests++
    inFlight++
    maximumInFlight = Math.max(maximumInFlight, inFlight)
    if (requests === 1) await firstResponse
    inFlight--
    await route.fulfill({ status: 401, json: { title: 'Synthetic guest', status: 401 } })
  })
  try {
    await page.goto('/login', { waitUntil: 'domcontentloaded' })
    await expect.poll(() => requests).toBe(1)
    const secondWindow = await context.newPage()
    await secondWindow.goto(new URL('/login', page.url()).href, { waitUntil: 'domcontentloaded' })
    await expect.poll(() => secondWindow.evaluate(async () => {
      const locks = await navigator.locks.query()
      return locks.pending?.filter(lock => lock.name?.startsWith('funding-platform:auth-cookie:')).length
    })).toBe(1)
    expect(requests).toBe(1)
    releaseFirst()
    await expect(page.getByRole('heading', { name: 'Bienvenido de vuelta' })).toBeVisible()
    await expect(secondWindow.getByRole('heading', { name: 'Bienvenido de vuelta' })).toBeVisible()
    await expect.poll(() => requests).toBe(2)
    await secondWindow.reload()
    await expect.poll(() => requests).toBe(3)
    expect(maximumInFlight).toBe(1)
    expect(unexpected).toEqual([])
  } finally {
    releaseFirst()
  }
})
