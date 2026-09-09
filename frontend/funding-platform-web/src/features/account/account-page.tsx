import { useMutation, useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { useSearchParams } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { authApi } from '@/features/auth/auth-api'
import { useAuth } from '@/features/auth/use-auth'

export function AccountWorkspacePage() {
  const { t } = useTranslation()
  const auth = useAuth()
  const [searchParams] = useSearchParams()
  const providers = useQuery({ queryKey: ['external-auth-providers'], queryFn: authApi.externalProviders, retry: false })
  const entraEnabled = providers.data?.some(provider => provider.code === 'entra' && provider.enabled) ?? false
  const link = useMutation({ mutationFn: authApi.createExternalLinkIntent, onSuccess: result => window.location.assign(result.startUrl) })
  const linkStatus = searchParams.get('sso')

  return <div className="space-y-6">
    <div><h1 className="text-3xl font-bold">{t('account.title')}</h1><p className="mt-2 text-muted-foreground">{t('account.description')}</p></div>
    <Card>
      <CardHeader><CardTitle>{t('account.sso')}</CardTitle></CardHeader>
      <CardContent className="space-y-3">
        {linkStatus === 'linked' && <p role="status" className="rounded-lg bg-accent p-3 text-sm">{t('account.linked')}</p>}
        {linkStatus === 'already_linked' && <p role="status" className="rounded-lg bg-accent p-3 text-sm">{t('account.alreadyLinked')}</p>}
        {linkStatus === 'link_failed' && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-foreground">{t('account.linkFailed')}</p>}
        {link.isError && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-foreground">{t('account.prepareFailed')}</p>}
        <p className="break-words rounded-lg border p-3 text-sm">{t('account.activeAccount')} <strong className="break-all">{auth.session?.user.email}</strong></p>
        <p className="text-sm text-muted-foreground">{t('account.help')}</p>
        {providers.isPending
          ? <p className="text-sm" role="status">{t('account.providersLoading')}</p>
          : providers.isError
            ? <div className="space-y-2"><p className="text-sm" role="alert">{t('account.providersFailed')}</p><Button disabled={providers.isFetching} onClick={() => void providers.refetch()} variant="outline">{t('account.retry')}</Button></div>
            : entraEnabled
              ? <Button className="h-auto max-w-full whitespace-normal break-all py-2 text-left" disabled={link.isPending} onClick={() => link.mutate()} variant="outline">{link.isPending ? t('account.preparing') : t('account.linkMicrosoft', { email: auth.session?.user.email ?? t('account.thisAccount') })}</Button>
              : <p className="text-sm font-medium">{t('account.disabled')}</p>}
      </CardContent>
    </Card>
  </div>
}
