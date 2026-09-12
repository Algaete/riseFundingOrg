import { apiClient } from '@/api/http-client'
import { searchSource } from './search-api'
import { searchSources, type SearchCriteria } from './search-model'

const criteria: SearchCriteria = { scope: 'all', q: 'agua', countryId: '', categoryId: '', page: 1 }

describe('unified search projection adapter', () => {
  afterEach(() => vi.restoreAllMocks())

  it.each(searchSources)('uses only GET and propagates cancellation without browser caching: %s', async source => {
    const get = vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [], totalCount: 0, page: 1, pageNumber: 1, pageSize: 6 })
    const signal = new AbortController().signal
    expect(await searchSource(source, criteria, signal, 'member')).toEqual({ items: [], totalCount: 0, page: 1, pageSize: 6 })
    expect(get).toHaveBeenCalledExactlyOnceWith(expect.any(String), { signal, cache: 'no-store' })
  })

  it('keeps published project projections and constructs internal links, not user URLs', async () => {
    const item = { publicId: 'project', slug: 'agua/segura', title: '<script>not markup</script>', summary: 'Resumen', organization: { name: 'Entidad' } }
    vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [item, { ...item, publicId: 'draft', publicationStatus: 0 }], totalCount: 1, pageNumber: 2, pageSize: 20 })
    const page = await searchSource('projects', { ...criteria, scope: 'projects', page: 2 }, new AbortController().signal)
    expect(page.items).toEqual([{ id: 'project', title: item.title, summary: 'Resumen', subtitle: 'Entidad', href: '/marketplace/projects/agua%2Fsegura' }])
    expect(page.page).toBe(2)
  })

  it('never returns private contact fields or opted-out professional profiles', async () => {
    const item = { profileId: 'professional', data: { displayName: 'Nombre', headline: 'Especialidad', biography: 'Experiencia', skills: ['GIS'], isDiscoverable: true, email: 'private@example.invalid' } }
    vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [item, { ...item, profileId: 'private', data: { ...item.data, isDiscoverable: false } }], totalCount: 1, page: 1, pageSize: 6 })
    const page = await searchSource('professionals', criteria, new AbortController().signal)
    expect(page.items).toEqual([{ id: 'professional', title: 'Nombre', summary: 'Especialidad', biography: 'Experiencia', skills: ['GIS'] }])
  })

  it.each(['funding', 'organizations'] as const)('does not follow website or application URLs for %s', async source => {
    vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [{ id: 'entity', slug: 'fondo', title: 'Fondo', name: 'Entidad', summary: 'Resumen', description: 'Descripción', sourceName: 'Fuente', websiteUrl: 'https://untrusted.example.invalid', sourceUrl: 'https://untrusted.example.invalid' }], totalCount: 1, page: 1, pageSize: 6 })
    const page = await searchSource(source, criteria, new AbortController().signal, 'member')
    expect(page.items[0].href).toBe(source === 'funding' ? '/funding/fondo' : '/marketplace/organizations/entity')
    expect(JSON.stringify(page)).not.toContain('untrusted')
  })
})
