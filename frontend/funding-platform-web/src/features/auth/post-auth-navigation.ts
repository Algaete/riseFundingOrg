import { organizationApi } from '@/features/organizations/organization-api'

const defaultAuthenticatedPath = '/dashboard'

export function getSafeAuthenticatedPath(requestedPath?: string | null) {
  if (!requestedPath?.startsWith('/') || requestedPath.startsWith('//')) {
    return defaultAuthenticatedPath
  }

  return requestedPath
}

export async function resolvePostAuthenticationPath(
  requestedPath: string | null | undefined,
  roles: readonly string[],
) {
  const safePath = getSafeAuthenticatedPath(requestedPath)
  const isPlatformAdministrator = roles.some(
    (role) => role === 'Admin' || role === 'SuperAdmin',
  )

  if (isPlatformAdministrator) {
    return safePath === defaultAuthenticatedPath ? '/admin' : safePath
  }

  try {
    const organizations = await organizationApi.list()
    return organizations.length === 0 ? '/onboarding' : safePath
  } catch {
    // Organization discovery must not invalidate an otherwise valid login.
    return safePath
  }
}
