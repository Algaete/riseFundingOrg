import type { GapRecommendations } from '@/features/matching/gap-recommendations-api'

export const gapOrganizationId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
export const gapProfessionalId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
export const gapRecommendations: GapRecommendations = {
  engineVersion: 'gap-actions-v1', projectTitle: 'Proyecto sintético', opportunityTitle: 'Fondo Ñandú original',
  contentVersion: 6, classificationCurrent: true, evidenceUrl: 'https://example.invalid/terms', evaluatedAtUtc: '2026-09-12T12:00:00Z',
  items: [
    { code: 'international-partner', origins: ['funding'], declaredNeed: null, state: 'suggestions',
      evaluatedCandidateCount: 200, totalCandidateCount: 230, isTruncated: true,
      candidates: [{ id: gapOrganizationId, name: 'Fundación Aliada Ñandú', summary: 'Organización sintética de colaboración internacional.',
        href: `/marketplace/organizations/${gapOrganizationId}`, sharedCategoryIds: [1, 2], sharedSkills: [], homeCountryId: 250 }] },
    { code: 'professionals', origins: ['project'], declaredNeed: 'Consultoría GIS', state: 'suggestions',
      evaluatedCandidateCount: 8, totalCandidateCount: 8, isTruncated: false,
      candidates: [{ id: gapProfessionalId, name: 'Profesional sintético GIS', summary: 'Perfil sintético disponible para explorar colaboraciones.',
        href: `/collaboration/consortia?professionalId=${gapProfessionalId}`, sharedCategoryIds: [1], sharedSkills: ['gis'], homeCountryId: 152 }] },
  ],
}
