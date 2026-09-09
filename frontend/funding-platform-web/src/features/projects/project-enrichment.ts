export interface ProjectImpactIndicator {
  name: string | null
  unit: string | null
  baseline: number | null
  target: number | null
}

export interface ProjectEnrichment {
  problem: string | null
  solution: string | null
  beneficiaryCount: number | null
  locality: string | null
  latitude: number | null
  longitude: number | null
  locationVisibility: number
  impactIndicators: ProjectImpactIndicator[]
  soughtPartners: string | null
  soughtProfessionals: string | null
  seekingConsortium: boolean | null
}

export function enrichmentInput(value?: ProjectEnrichment | null): ProjectEnrichment {
  return {
    problem: null, solution: null, beneficiaryCount: null, locality: null,
    latitude: null, longitude: null, locationVisibility: 0,
    soughtPartners: null, soughtProfessionals: null, seekingConsortium: null,
    ...value,
    impactIndicators: value?.impactIndicators ?? [],
  }
}
