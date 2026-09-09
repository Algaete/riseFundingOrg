import { Link, Outlet } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { FundingEditorialScopeContext, funderOwnerScope } from './editorial-scope'

export function FunderWorkspaceLayout() {
  const { t } = useTranslation()
  return <FundingEditorialScopeContext value={funderOwnerScope}>
    <div className="space-y-6">
      <nav aria-label={t('funderWorkspace.title')} className="flex flex-wrap gap-4 rounded-xl border bg-card p-4">
        <Link className="font-semibold text-primary underline" to="/funder-workspace/funders">{t('funderWorkspace.profiles')}</Link>
        <Link className="font-semibold text-primary underline" to="/funder-workspace/funding">{t('funderWorkspace.opportunities')}</Link>
      </nav>
      <p className="text-sm text-muted-foreground">{t('funderWorkspace.intro')}</p>
      <Outlet />
    </div>
  </FundingEditorialScopeContext>
}
