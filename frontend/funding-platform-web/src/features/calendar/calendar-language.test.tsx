import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CalendarWorkspacePage } from './calendar-pages'
import { calendarApi } from './calendar-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { workspaceOrganizationId, workspaceProfile } from '@/test/fixtures/project-workspace'
import { trackingCalendar } from '@/test/fixtures/tracking-workspace'
import { language, trackingPage } from '@/test/tracking-test-harness'

afterEach(() => vi.restoreAllMocks())
it('keeps month bounds, date-only grouping, UTC midnight and entity links across language changes', async () => {
  vi.spyOn(organizationApi, 'list').mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2027-02-01T12:00:00Z' }])
  const read = vi.spyOn(calendarApi, 'get').mockResolvedValue(trackingCalendar)
  const { router } = trackingPage(<CalendarWorkspacePage />, '/calendar?month=2027-02')
  await screen.findByText('00:00 UTC')
  const links = screen.getAllByRole('link', { name: /Abrir/ }).map(link => link.getAttribute('href'))
  await language('en')
  expect(screen.getByRole('heading', { name: 'Monday, February 15, 2027' })).toBeInTheDocument()
  expect(screen.getByText('00:00 UTC')).toBeInTheDocument()
  expect(screen.getByText(/All day · Approximate date/)).toBeInTheDocument()
  expect(screen.getAllByRole('link', { name: /Open/ }).map(link => link.getAttribute('href'))).toEqual(links)
  expect(router.state.location.search).toBe('?month=2027-02')
  expect(read).toHaveBeenCalledTimes(1)
  expect(read.mock.calls[0].slice(0, 3)).toEqual([workspaceOrganizationId, '2027-02-01', '2027-02-28'])
  await userEvent.setup().click(screen.getByRole('button', { name: 'Next month' }))
  expect(read.mock.calls[1].slice(0, 3)).toEqual([workspaceOrganizationId, '2027-03-01', '2027-03-31'])
})
