import { useState, type FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { marketplaceApi } from '@/features/marketplace/marketplace-api'
import { useAuth } from '@/features/auth/use-auth'
import { catalogName } from '@/i18n/catalog-labels'
import { contactTopics, engagementApi, serviceCodes, type Inquiry, type InquiryInput } from './engagement-api'
import { container, control, panel, Failure, Field, Paging } from './engagement-ui'

export function ServicesPage() {
  const { t } = useTranslation()
  return <div className={container}><h1 className="text-4xl font-bold">{t('engagement.servicesTitle')}</h1><p className="max-w-3xl">{t('engagement.servicesHelp')}</p>
    <div className="grid gap-5 md:grid-cols-2">{serviceCodes.map(code => <article key={code} className={`${panel} flex flex-col items-start`}><h2 className="text-xl font-bold">{t(`engagement.services.${code}.title`)}</h2><p className="flex-1">{t(`engagement.services.${code}.description`)}</p><Button asChild><Link to={`/contact?service=${code}`}>{t('engagement.quote')}</Link></Button></article>)}</div>
    <p className="rounded-lg border p-4">{t('engagement.serviceDisclaimer')}</p>
  </div>
}

export function ContactPage() {
  const { t } = useTranslation(); const [params] = useSearchParams()
  const [countrySearch, setCountrySearch] = useState('')
  const [data, setData] = useState<InquiryInput>(() => {
    const service = serviceCodes.find(code => code === params.get('service')) ?? null
    return { requestId: crypto.randomUUID(), name: '', email: '', organization: null, countryId: 0, topic: service ? 'service' : 'funding', serviceCode: service, projectReference: null, fundingReference: null, deadline: null, description: '', consentToContact: false, website: '' }
  })
  const catalogs = useQuery({ queryKey: ['marketplace', 'catalogs'], queryFn: ({ signal }) => marketplaceApi.catalogs(signal) })
  const mutation = useMutation({ mutationFn: () => engagementApi.contact(data), retry: false })
  // Preserve the request ID across retries, but not after the user changes its payload.
  const change = (patch: Partial<InquiryInput>) => { setData(current => ({ ...current, ...patch, requestId: crypto.randomUUID() })); mutation.reset() }
  function submit(e: FormEvent) { e.preventDefault(); mutation.mutate() }
  if (mutation.isSuccess) return <div className={container}><h1 className="text-3xl font-bold">{t('engagement.received')}</h1><p role="status">{t('engagement.receivedHelp')}</p><p className="break-all">{t('engagement.reference')}: {mutation.data.requestId}</p><Button asChild variant="outline"><Link to="/services">{t('engagement.servicesTitle')}</Link></Button></div>
  const countries = Array.isArray(catalogs.data?.countries) ? catalogs.data.countries : []
  const term = countrySearch.trim().toLocaleLowerCase()
  return <div className={`${container} max-w-3xl`}><h1 className="text-4xl font-bold">{t('navigation.contact')}</h1><p>{t('engagement.contactHelp')}</p>
    <form onSubmit={submit} className={panel}><p>{t('engagement.required')}</p><fieldset className="space-y-5" disabled={mutation.isPending}>
      <h2 className="text-xl font-bold">{t('engagement.stepNeed')}</h2>
      <Field label={`${t('engagement.topic')} *`}><select className={control} value={data.topic} onChange={e => change({ topic: e.target.value, serviceCode: e.target.value === 'service' ? serviceCodes[0] : null })}>{contactTopics.map(topic => <option key={topic} value={topic}>{t(`engagement.topics.${topic}`)}</option>)}</select></Field>
      {data.topic === 'service' && <Field label={`${t('engagement.service')} *`}><select className={control} required value={data.serviceCode ?? ''} onChange={e => change({ serviceCode: e.target.value })}>{serviceCodes.map(code => <option key={code} value={code}>{t(`engagement.services.${code}.title`)}</option>)}</select></Field>}
      <Field label={t('engagement.projectReference')}><input className={control} maxLength={1000} value={data.projectReference ?? ''} onChange={e => change({ projectReference: e.target.value || null })} /></Field>
      <Field label={t('engagement.fundingReference')}><input className={control} maxLength={1000} value={data.fundingReference ?? ''} onChange={e => change({ fundingReference: e.target.value || null })} /></Field>
      <Field label={t('engagement.deadline')}><input className={control} type="date" min="2000-01-01" max="2100-12-31" value={data.deadline ?? ''} onChange={e => change({ deadline: e.target.value || null })} /></Field>
      <Field label={`${t('engagement.description')} *`}><textarea className={`${control} min-h-36`} required minLength={20} maxLength={5000} value={data.description} onChange={e => change({ description: e.target.value })} /></Field>
      <p className="text-sm text-muted-foreground">{t('engagement.noSensitiveData')}</p><p className="text-sm">{t('engagement.documentsLater')}</p>
      <h2 className="text-xl font-bold">{t('engagement.stepContact')}</h2>
      <Field label={`${t('engagement.name')} *`}><input className={control} autoComplete="name" required minLength={2} maxLength={150} value={data.name} onChange={e => change({ name: e.target.value })} /></Field>
      <Field label={`${t('engagement.email')} *`}><input className={control} type="email" autoComplete="email" required maxLength={254} value={data.email} onChange={e => change({ email: e.target.value })} /></Field>
      <Field label={t('engagement.organization')}><input className={control} autoComplete="organization" maxLength={250} value={data.organization ?? ''} onChange={e => change({ organization: e.target.value || null })} /></Field>
      <Field label={t('engagement.searchCountry')}><input className={control} type="search" value={countrySearch} onChange={e => setCountrySearch(e.target.value)} /></Field>
      <Field label={`${t('engagement.country')} *`}><select className={control} required disabled={!countries.length} value={data.countryId || ''} onChange={e => change({ countryId: Number(e.target.value) })}><option value="">{t('engagement.choose')}</option>{countries.filter(c => c.id === data.countryId || catalogName('countries', c).toLocaleLowerCase().includes(term)).map(c => <option key={c.id} value={c.id}>{catalogName('countries', c)}</option>)}</select></Field>
      <Failure error={catalogs.error} />
      <label className="hidden" aria-hidden="true">Website<input tabIndex={-1} autoComplete="off" value={data.website} onChange={e => change({ website: e.target.value })} /></label>
      <label className="flex items-start gap-2"><input type="checkbox" required checked={data.consentToContact} onChange={e => change({ consentToContact: e.target.checked })} />{t('engagement.contactConsent')} *</label>
      <p className="text-sm text-muted-foreground">{t('engagement.serviceDisclaimer')}</p><Failure error={mutation.error} />
      <Button type="submit" disabled={!data.countryId || !data.consentToContact || mutation.isPending}>{t(mutation.isPending ? 'engagement.sending' : 'engagement.send')}</Button>
    </fieldset></form>
  </div>
}

function InquiryCard({ item, onReviewed }: { item: Inquiry; onReviewed: () => void }) {
  const { t } = useTranslation()
  const [status, setStatus] = useState(item.status)
  const mutation = useMutation({ mutationFn: () => engagementApi.reviewInquiry(item, status), onSuccess: onReviewed, retry: false })
  const d = item.data
  return <article className={panel}><h2 className="text-xl font-bold">{t(`engagement.topics.${d.topic}`, { defaultValue: d.topic })} · {d.name}</h2><p>{d.organization} · {item.countryName}</p><a className="text-primary underline" href={`mailto:${encodeURIComponent(d.email)}`}>{d.email}</a>
    <p className="text-sm break-all">{t('engagement.reference')}: {item.requestId}</p>
    {d.serviceCode && <p>{t(`engagement.services.${d.serviceCode}.title`, { defaultValue: d.serviceCode })}</p>}
    {d.projectReference && <p className="break-words">{t('engagement.projectReference')}: {d.projectReference}</p>}
    {d.fundingReference && <p className="break-words">{t('engagement.fundingReference')}: {d.fundingReference}</p>}
    {d.deadline && <p>{t('engagement.deadline')}: {d.deadline}</p>}
    <p className="whitespace-pre-wrap break-words">{d.description}</p><p>{t(`engagement.notification${item.notificationStatus}`, { defaultValue: '—' })}</p>
    <Field label={t('engagement.reviewStatus')}><select className={control} disabled={mutation.isPending} value={status} onChange={e => setStatus(Number(e.target.value))}>{[0, 1, 2].map(s => <option key={s} value={s}>{t(`engagement.inquiryStatus${s}`, { defaultValue: '—' })}</option>)}</select></Field>
    <Failure error={mutation.error} /><Button disabled={mutation.isPending || status === item.status} onClick={() => mutation.mutate()}>{t('engagement.saveStatus')}</Button>
  </article>
}
export function AdminInquiriesPage() {
  const { t } = useTranslation(); const auth = useAuth(); const [page, setPage] = useState(1)
  const query = useQuery({ queryKey: ['admin-inquiries', auth.session?.user.publicId, page], queryFn: ({ signal }) => engagementApi.inquiries(page, signal), retry: false })
  return <div className="space-y-6"><h1 className="text-3xl font-bold">{t('navigation.inquiries')}</h1><p>{t('engagement.inboxHelp')}</p><Failure error={query.error} />
    {query.isPending && <p role="status">{t('engagement.loading')}</p>}{query.data?.items?.length === 0 && <p>{t('engagement.emptyInbox')}</p>}
    {(query.data?.items ?? []).map(item => <InquiryCard key={`${item.requestId}:${item.revision}`} item={item} onReviewed={() => { void query.refetch() }} />)}
    {query.data && <Paging page={page} total={query.data.totalCount} onPage={setPage} disabled={query.isFetching} />}
  </div>
}
