import { expect, test } from '@playwright/test'

const email = process.env.E2E_USER_EMAIL
const password = process.env.E2E_USER_PASSWORD

test.use({ screenshot: 'off', trace: 'off', video: 'off' })

function parseApprovedOrigins(variableName: string) {
  const values = (process.env[variableName] ?? '')
    .split(',')
    .map((value) => value.trim().replace(/\/$/, ''))
    .filter(Boolean)

  return values.map((value) => {
    const target = new URL(value)
    const isLoopback = target.protocol === 'http:'
      && ['127.0.0.1', 'localhost', '::1'].includes(target.hostname)
    if (
      target.username
      || target.password
      || target.origin !== value
      || (!isLoopback && target.protocol !== 'https:')
    ) {
      throw new Error(
        `${variableName} sólo acepta orígenes HTTPS exactos; HTTP se permite únicamente en loopback.`,
      )
    }

    return target.origin
  })
}

function requireApprovedAuthenticationTarget() {
  const configuredBaseUrl = process.env.PLAYWRIGHT_BASE_URL
  if (!configuredBaseUrl) {
    throw new Error(
      'PLAYWRIGHT_BASE_URL es obligatorio para la suite autenticada; inicia Vite manualmente si pruebas en local.',
    )
  }

  const target = new URL(configuredBaseUrl)
  const isLoopback = target.protocol === 'http:'
    && ['127.0.0.1', 'localhost', '::1'].includes(target.hostname)
  const approvedFrontendOrigins = parseApprovedOrigins('E2E_ALLOWED_ORIGINS')
  const approvedApiOrigins = parseApprovedOrigins('E2E_ALLOWED_API_ORIGINS')

  const normalizedBaseUrl = configuredBaseUrl.replace(/\/$/, '')
  if (
    target.username
    || target.password
    || target.origin !== normalizedBaseUrl
    || (!isLoopback && target.protocol !== 'https:')
    || !approvedFrontendOrigins.includes(target.origin)
  ) {
    throw new Error(
      'PLAYWRIGHT_BASE_URL debe ser un origen exacto aprobado: HTTPS, salvo HTTP en loopback, y coincidir con E2E_ALLOWED_ORIGINS.',
    )
  }
  if (approvedApiOrigins.length === 0) {
    throw new Error('E2E_ALLOWED_API_ORIGINS debe aprobar explícitamente el origen que recibirá las credenciales.')
  }

  return new Set(approvedApiOrigins)
}

test('inicia una sesión manual de prueba y llega al espacio privado', async ({ page }) => {
  test.skip(!email || !password, 'Requiere credenciales efímeras fuera del repositorio.')
  const approvedApiOrigins = requireApprovedAuthenticationTarget()
  let blockedPost: string | null = null
  let loginDestinationVerified = false

  await page.route('**/*', async (route) => {
    const request = route.request()
    if (request.method() !== 'POST') {
      await route.continue()
      return
    }

    const destination = new URL(request.url())
    const isKnownAuthenticationRequest = [
      '/api/v1/auth/refresh',
      '/api/v1/auth/login',
    ].includes(destination.pathname)
    if (!approvedApiOrigins.has(destination.origin) || !isKnownAuthenticationRequest) {
      blockedPost = `${destination.origin}${destination.pathname}`
      await route.abort('blockedbyclient')
      return
    }

    if (destination.pathname === '/api/v1/auth/login') {
      loginDestinationVerified = true
    }
    await route.continue()
  })

  await page.goto('/login')
  await expect(page.getByLabel('Correo electrónico')).toBeVisible()
  expect(blockedPost).toBeNull()
  await page.getByLabel('Correo electrónico').fill(email!)
  await page.getByLabel('Contraseña').fill(password!)
  await page.getByRole('button', { name: 'Ingresar' }).click()

  await expect.poll(() => loginDestinationVerified || blockedPost !== null).toBe(true)
  expect(blockedPost).toBeNull()
  expect(loginDestinationVerified).toBe(true)
  await expect(page).toHaveURL(/\/(dashboard|onboarding|admin)(?:[/?#]|$)/, {
    timeout: 20_000,
  })
  await expect(page.getByText('Comprobando sesión…')).not.toBeVisible()
})
