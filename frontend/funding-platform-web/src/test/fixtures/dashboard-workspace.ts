import { workspaceProfile, workspaceProject } from './project-workspace'

// Synthetic records shared by component and isolated browser tests.
export const dashboardOrganizations = [
  { ...workspaceProfile, updatedAtUtc: '2026-09-01T12:00:00Z' },
  { ...workspaceProfile, publicId: '44444444-4444-4444-4444-444444444444', name: 'Organización de colaboración territorial Ñandú', updatedAtUtc: '2026-09-01T12:00:00Z' },
]
export const dashboardApplications = {
  items: [{
    publicId: '55555555-5555-5555-5555-555555555555',
    project: { publicId: workspaceProject.publicId, slug: workspaceProject.slug, title: workspaceProject.title },
    fundingOpportunity: {
      publicId: '66666666-6666-6666-6666-666666666666', slug: 'fondo-sintetico', title: 'Fondo Agua Ñandú',
      sponsorName: 'Fundación sintética', closeDate: '2026-09-20', closeAtUtc: null, deadlinePrecision: 1,
    },
    status: 1 as const, notes: null, applicationDate: null, requestedAmount: null, currency: null,
    resultDate: null, ownerUserPublicId: '77777777-7777-7777-7777-777777777777', canEdit: true,
    createdAtUtc: '2026-09-01T12:00:00Z', updatedAtUtc: '2026-09-02T12:00:00Z', eTag: '"synthetic"',
  }],
  totalCount: 1234, pageNumber: 1, pageSize: 5,
}
export const dashboardCalendar = {
  from: '2026-09-01', to: '2026-10-31', items: [{
    eventKey: 'deadline:synthetic', eventType: 'application-deadline' as const,
    eventDate: '2026-09-20', eventAtUtc: null, datePrecision: 1, title: 'Cierre Fondo Agua Ñandú',
    status: 1 as const, fundingApplicationPublicId: dashboardApplications.items[0].publicId,
    projectPublicId: workspaceProject.publicId,
    fundingOpportunityPublicId: dashboardApplications.items[0].fundingOpportunity.publicId,
  }],
}
