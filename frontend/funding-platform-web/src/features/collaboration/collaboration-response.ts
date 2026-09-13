// SQL-backed responses may omit an empty collection or encode it as null.
// Normalize at the API boundary; components and invitation pickers receive arrays.
// Malformed responses still reject the query so LoadState can offer a retry.
export function collaborationList<T>(items: T[] | null | undefined): T[] {
  if (items == null) return []
  if (!Array.isArray(items) || items.some(item => item == null)) {
    throw new Error('Invalid collaboration collection response.')
  }
  return items
}

interface PageResponse<T> { items?: T[] | null; totalCount: number; page: number; pageSize: number }

export function collaborationPage<T>(response: PageResponse<T> | null | undefined) {
  if (!response || !Number.isSafeInteger(response.totalCount) || response.totalCount < 0 ||
      !Number.isSafeInteger(response.page) || response.page < 1 ||
      !Number.isSafeInteger(response.pageSize) || response.pageSize < 1) {
    throw new Error('Invalid collaboration page response.')
  }
  const items = collaborationList(response.items)
  if (items.length === 0 && (response.page - 1) * response.pageSize < response.totalCount) {
    throw new Error('Missing collaboration page items.')
  }
  return { ...response, items }
}
