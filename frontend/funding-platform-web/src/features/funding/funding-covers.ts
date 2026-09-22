// Versioned keys shared with FundingCoverRules and SQL 056. Unknown/legacy keys
// use our bundled default; a server-supplied key is never interpolated into a URL.
export const fundingCoverKeys = ['auto', 'nature-v1', 'education-v1', 'community-v1', 'research-v1'] as const
export type FundingCoverKey = typeof fundingCoverKeys[number]
export const fundingCoverLibrary = {
  'nature-v1': { src: '/images/funding-covers/nature-v1.jpg', label: 'coverNature' },
  'education-v1': { src: '/images/funding-covers/education-v1.jpg', label: 'coverEducation' },
  'community-v1': { src: '/images/funding-covers/community-v1.jpg', label: 'coverCommunity' },
  'research-v1': { src: '/images/funding-covers/research-v1.jpg', label: 'coverResearch' },
} as const
export function resolveFundingCover(key?: string | null) {
  return key && Object.hasOwn(fundingCoverLibrary, key)
    ? fundingCoverLibrary[key as keyof typeof fundingCoverLibrary]
    : fundingCoverLibrary['community-v1']
}
export function isFundingCoverKey(key: string): key is FundingCoverKey {
  return fundingCoverKeys.some(value => value === key)
}
