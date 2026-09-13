import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { workspaceProfile, workspaceProject } from '@/test/fixtures/project-workspace'
import { ConsortiumListPage } from './consortium-list-page'

function setup(response: unknown, status = 200) {
  let listResponse = response
  let listStatus = status
  const fetch = vi.fn((input: RequestInfo | URL, options?: RequestInit) => {
    const path = new URL(String(input), 'https://example.invalid').pathname
    if (options?.method !== 'GET') throw new Error('Unexpected write')
    const body = path.endsWith('/consortia') ? listResponse : path.endsWith('/projects') ? [workspaceProject] : [workspaceProfile]
    return Promise.resolve(new Response(JSON.stringify(body), {
      status: path.endsWith('/consortia') ? listStatus : 200,
      headers: { 'Content-Type': 'application/json' },
    }))
  })
  vi.stubGlobal('fetch', fetch)
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  render(<MemoryRouter><QueryClientProvider client={client}><ConsortiumListPage /></QueryClientProvider></MemoryRouter>)
  return { fetch, recover: () => { listResponse = { items: [], totalCount: 0, page: 1, pageSize: 20 }; listStatus = 200 } }
}

describe('lista de consorcios', () => {
  afterEach(() => vi.unstubAllGlobals())

  it.each([null, undefined, []])('muestra el estado vacío con items=%j y mantiene usable el formulario', async items => {
    const { fetch } = setup({ items, totalCount: 0, page: 1, pageSize: 20 })
    expect(await screen.findByText('No hay resultados.')).toBeVisible()
    await userEvent.selectOptions(await screen.findByLabelText('Organización coordinadora *'), workspaceProfile.publicId)
    await userEvent.selectOptions(await screen.findByLabelText('Proyecto *'), workspaceProject.publicId)
    expect(screen.getByRole('button', { name: 'Crear consorcio' })).toBeEnabled()
    expect(screen.getByRole('button', { name: 'Anterior' })).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Siguiente' })).toBeDisabled()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(fetch.mock.calls.every(([, options]) => options?.method === 'GET')).toBe(true)
  })

  it.each([
    [{ title: 'private database text' }, 503],
    [{ items: {}, totalCount: 0, page: 1, pageSize: 20 }, 200],
    [{ items: null, totalCount: 1, page: 1, pageSize: 20 }, 200],
  ])('muestra un error recuperable, no un estado vacío, ante %j', async (body, status) => {
    const { recover } = setup(body, status)
    expect(await screen.findByRole('alert')).toHaveTextContent('No fue posible completar la operación.')
    expect(screen.queryByText('No hay resultados.')).not.toBeInTheDocument()
    expect(screen.queryByText('private database text')).not.toBeInTheDocument()
    recover()
    await userEvent.click(screen.getByRole('button', { name: 'Volver a cargar' }))
    expect(await screen.findByText('No hay resultados.')).toBeVisible()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })
})
