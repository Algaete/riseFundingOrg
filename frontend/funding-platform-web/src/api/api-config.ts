export function getApiBaseUrl() {
  return (import.meta.env.VITE_API_BASE_URL ?? '/api/v1').replace(/\/$/, '')
}

export function getExternalAuthBaseUrl() {
  const configured = import.meta.env.VITE_EXTERNAL_AUTH_BASE_URL
  if (configured) return configured.replace(/\/$/, '')
  return getApiBaseUrl()
}
