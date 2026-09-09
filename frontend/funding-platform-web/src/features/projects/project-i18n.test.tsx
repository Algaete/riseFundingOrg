import { QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { createAppQueryClient } from '@/api/query-client'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi, publicProjectApi } from '@/features/projects/project-api'
import { ProjectDetailPage, ProjectsPage } from '@/features/projects/project-pages'
import { PublicProjectPage } from '@/features/projects/project-publication-pages'
import { setInterfaceLanguage } from '@/i18n'
import { workspaceCatalogs, workspaceOrganizationId, workspaceProfile, workspaceProject, workspaceProjectId, workspacePublicProject } from '@/test/fixtures/project-workspace'

function renderWorkspace(path = `/projects/${workspaceProjectId}`) {
  render(<QueryClientProvider client={createAppQueryClient()}><MemoryRouter initialEntries={[path]}><Routes>
    <Route path="/projects" element={<ProjectsPage />} />
    <Route path="/projects/:projectId" element={<ProjectDetailPage />} />
    <Route path="/projects/public/:slug" element={<PublicProjectPage />} />
  </Routes></MemoryRouter></QueryClientProvider>)
}

describe('project language changes', () => {
  beforeEach(() => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2026-09-01T12:00:00Z' }])
    vi.spyOn(organizationApi, 'catalogs').mockResolvedValue(workspaceCatalogs)
    vi.spyOn(projectApi, 'list').mockResolvedValue([workspaceProject])
    vi.spyOn(projectApi, 'get').mockResolvedValue(workspaceProject)
    vi.stubEnv('VITE_PROJECT_ASSETS_ENABLED', 'false')
  })
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllEnvs() })

  it('preserves unsaved text, stage, SDGs, optional fields and the original ETag when saving', async () => {
    const update = vi.spyOn(projectApi, 'update').mockImplementation(async (_organizationId, _projectId, _etag, input) => ({ ...workspaceProject, ...input, eTag: '"0000000000000002"' }))
    renderWorkspace()
    const title = await screen.findByLabelText(/Título/)
    fireEvent.change(title, { target: { value: 'Título Ñandú editado' } })
    await userEvent.selectOptions(screen.getByLabelText('Etapa del proyecto'), '3')
    await userEvent.click(screen.getByRole('checkbox', { name: /ODS 17/ }))
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByLabelText(/Title/)).toHaveValue('Título Ñandú editado')
    expect(screen.getByLabelText('Project stage')).toHaveValue('3')
    expect(screen.getByRole('checkbox', { name: /SDG 17/ })).toBeChecked()
    expect(screen.getByRole('button', { name: 'Submit for review' })).toBeDisabled()
    await userEvent.click(screen.getByRole('button', { name: 'Save changes' }))
    await waitFor(() => expect(update).toHaveBeenCalledOnce())
    expect(update.mock.calls[0]).toEqual([workspaceOrganizationId, workspaceProjectId, workspaceProject.eTag, expect.objectContaining({ title: 'Título Ñandú editado', projectStage: 3, sustainableDevelopmentGoalIds: [6, 17], summary: workspaceProject.summary, countryIds: [152] })])
  })

  it('translates visible date validation without submitting or clearing dates', async () => {
    const update = vi.spyOn(projectApi, 'update')
    renderWorkspace()
    await screen.findByLabelText(/Título/)
    fireEvent.change(screen.getByLabelText('Término'), { target: { value: '2026-01-01' } })
    await userEvent.click(screen.getByRole('button', { name: 'Guardar cambios' }))
    expect(await screen.findByText('La fecha de término no puede ser anterior al inicio.')).toBeVisible()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('The end date cannot be before the start date.')).toBeVisible()
    expect(screen.getByLabelText(/End/)).toHaveValue('2026-01-01')
    expect(update).not.toHaveBeenCalled()
  })

  it.each([1, 2, 4])('keeps publication status %s locked across language changes', async publicationStatus => {
    vi.mocked(projectApi.get).mockResolvedValue({ ...workspaceProject, publicationStatus })
    renderWorkspace()
    await screen.findByLabelText(/Título/)
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByLabelText(/Title/)).toBeDisabled()
    expect(screen.queryByRole('button', { name: 'Save changes' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Submit for review' })).not.toBeInTheDocument()
  })

  it('keeps an archive confirmation open but does not execute it when changing language', async () => {
    const archive = vi.spyOn(projectApi, 'archive')
    renderWorkspace()
    await userEvent.click(await screen.findByRole('button', { name: 'Archivar' }))
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('button', { name: 'Confirm archive' })).toBeVisible()
    expect(archive).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))
    expect(screen.queryByRole('button', { name: 'Confirm archive' })).not.toBeInTheDocument()
  })

  it('translates the public frame, stage, dates and amounts without translating source content', async () => {
    const get = vi.spyOn(publicProjectApi, 'get').mockResolvedValue(workspacePublicProject)
    renderWorkspace('/projects/public/proyecto-sintetico')
    await screen.findByRole('heading', { name: workspaceProject.title })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'About the project' })).toBeVisible()
    expect(screen.getByText('Implementation')).toBeVisible()
    expect(screen.getByText('January 1, 2027 — December 31, 2027')).toBeVisible()
    expect(screen.getByText('$75,000.00')).toBeVisible()
    expect(screen.getByText(workspaceProject.description!)).toBeVisible()
    expect(screen.getByText('Clean Water and Sanitation')).toHaveAttribute('lang', 'en')
    expect(get).toHaveBeenCalledOnce()
  })
})
