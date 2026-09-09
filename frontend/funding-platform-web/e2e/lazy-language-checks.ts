import { expect, test, type Page } from '@playwright/test'
import { fits } from './workspace-checks'

export function registerLazyLanguageTests(accessibility: (page: Page) => Promise<void>) {
  test('descarga idiomas por módulo y reutiliza los recursos ya cargados', async ({ page }) => {
    const englishChunks = new Set<string>()
    page.on('request', request => {
      if (/\/assets\/en-[^/]+\.js$/.test(request.url())) englishChunks.add(request.url())
    })
    await page.goto('/')
    await expect(page.getByRole('combobox', { name: 'Idioma', exact: true })).toBeVisible()
    expect(englishChunks.size).toBe(0)
    await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
    await expect(page.getByRole('combobox', { name: 'Language', exact: true })).toHaveValue('en')
    // The home now includes public country/sector filters: shell plus catalogs only.
    expect(englishChunks.size).toBe(2)
    await page.getByRole('link', { name: 'Sign in', exact: true }).click()
    await expect(page.getByRole('textbox', { name: 'Email address', exact: true })).toBeVisible()
    const loginChunks = englishChunks.size
    expect(loginChunks).toBeGreaterThan(1)
    expect(loginChunks).toBeLessThan(8)
    await page.getByRole('textbox', { name: 'Email address', exact: true }).fill('draft@example.invalid')
    await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
    await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
    await expect(page.getByRole('textbox', { name: 'Email address', exact: true })).toHaveValue('draft@example.invalid')
    expect(englishChunks.size).toBe(loginChunks)
  })

  test('un fallo de descarga conserva idioma, formulario y preferencia a 320px', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 })
    await page.goto('/login')
    await page.getByLabel('Correo electrónico', { exact: true }).fill('draft@example.invalid')
    await page.route('**/assets/en-*.js', route => route.abort('failed'))
    await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
    await expect(page.getByRole('alert')).toHaveText('No se pudo cargar el idioma. Intenta nuevamente.')
    await expect(page.getByRole('combobox', { name: 'Idioma', exact: true })).toHaveValue('es')
    await expect(page.getByRole('combobox', { name: 'Idioma', exact: true })).toBeEnabled()
    await expect(page.getByLabel('Correo electrónico', { exact: true })).toHaveValue('draft@example.invalid')
    expect(await page.evaluate(() => localStorage.getItem('funding-platform-language'))).not.toBe('en')
    await accessibility(page)
    await fits(page)
  })

  test('una entrada directa carga el idioma guardado antes de mostrar el formulario', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('funding-platform-language', 'en'))
    await page.goto('/register')
    await expect(page.getByRole('textbox', { name: 'Email', exact: true })).toBeVisible()
    await expect(page.locator('html')).toHaveAttribute('lang', 'en')
    await expect(page.getByRole('combobox', { name: 'Language', exact: true })).toHaveValue('en')
    await expect(page.locator('body')).not.toContainText('auth.register')
    await accessibility(page)
  })
}
