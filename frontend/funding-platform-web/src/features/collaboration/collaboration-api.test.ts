import { collaborationApi } from './collaboration-api'

const page = { totalCount: 0, page: 1, pageSize: 20 }
const readers = [
  ['consorcios', () => collaborationApi.consortia()],
  ['profesionales', () => collaborationApi.professionals()],
  ['organizaciones para invitar', () => collaborationApi.connections('organization')],
] as const

function respond(body: unknown, status = 200) {
  vi.stubGlobal('fetch', vi.fn().mockImplementation(() => Promise.resolve(new Response(JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  }))))
}

describe('colecciones de colaboración recibidas de la API', () => {
  afterEach(() => vi.unstubAllGlobals())

  describe.each(readers)('%s', (_name, read) => {
    it.each([null, undefined, []])('normaliza una página vacía con items=%j', async items => {
      respond({ ...page, items })
      expect(await read()).toEqual({ ...page, items: [] })
    })

    it('conserva elementos y metadatos de paginación', async () => {
      const body = { items: [{ name: 'TEST · Consorcio' }], totalCount: 21, page: 2, pageSize: 20 }
      respond(body)
      expect(await read()).toEqual(body)
    })

    it('acepta una página sin elementos fuera del total sin perder el total', async () => {
      respond({ ...page, page: 2, totalCount: 1, items: null })
      expect(await read()).toEqual({ ...page, page: 2, totalCount: 1, items: [] })
    })

    it.each([null, {}, { ...page, items: {} }, { ...page, items: '[]' },
      { ...page, totalCount: 1, items: null }, { ...page, items: [null] },
      { ...page, totalCount: -1, items: [] }])('rechaza una respuesta inconsistente sin presentarla como vacía: %j', async body => {
      respond(body)
      await expect(read()).rejects.toThrow()
    })

    it('conserva los errores HTTP', async () => {
      respond({ title: 'No disponible', status: 503 }, 503)
      await expect(read()).rejects.toMatchObject({ name: 'ApiError', response: { status: 503 } })
    })
  })

  it.each([null, undefined, []])('normaliza participantes vacíos sin alterar permisos: %j', async participants => {
    const consortium = { consortiumId: 'test', canManage: false, canViewRoster: false, acceptedCount: 0 }
    respond({ consortium, participants })
    expect(await collaborationApi.consortium('test')).toEqual({ consortium, participants: [] })
  })

  it('conserva los participantes presentes', async () => {
    const body = { consortium: { consortiumId: 'test' }, participants: [{ participantId: 'participant' }] }
    respond(body)
    expect(await collaborationApi.consortium('test')).toEqual(body)
  })

  it.each([null, {}, { consortium: null, participants: [] }, { consortium: {}, participants: {} }])('rechaza un detalle inválido: %j', async body => {
    respond(body)
    await expect(collaborationApi.consortium('test')).rejects.toThrow()
  })
})
