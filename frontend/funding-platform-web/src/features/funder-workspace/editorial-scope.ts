import { createContext, useContext } from 'react'
import { createFundingEditorialApis } from '@/features/funding/admin-funding-api'

function scope(owner: boolean) {
  return {
    owner,
    basePath: owner ? '/funder-workspace' : '/admin',
    // Admin and owner cache/idempotency namespaces must never exchange privileged data.
    key: (value: string) => owner ? `funder-workspace:${value}` : value,
    apis: createFundingEditorialApis(owner ? 'funder-workspace' : 'admin'),
  }
}
export const funderOwnerScope = scope(true)
export const FundingEditorialScopeContext = createContext(scope(false))
export const useFundingEditorialScope = () => useContext(FundingEditorialScopeContext)
