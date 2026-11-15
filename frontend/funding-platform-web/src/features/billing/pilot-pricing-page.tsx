import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { formatNumber } from '@/i18n/formats'
const prices = [{ monthly: 9990, annual: 95904 }, { monthly: 14990, annual: 143904 }, { monthly: 19990, annual: 191904 }] as const
export function PilotPricingPage() {
  const { t } = useTranslation()
  const [range, setRange] = useState('')
  const price = range === '' ? undefined : prices[Number(range)]
  return <div className="mx-auto max-w-5xl space-y-8 px-4 py-12 sm:px-6">
    <header className="space-y-3 text-center"><h1 className="text-3xl font-bold sm:text-4xl">{t('pilotPricing.title')}</h1><p className="text-muted-foreground">{t('pilotPricing.intro')}</p></header>
    <div className="grid gap-6 md:grid-cols-2">
      <Card className="min-w-0 border-primary"><CardHeader><CardTitle>{t('pilotPricing.free')}</CardTitle><p>{t('pilotPricing.freeHelp')}</p></CardHeader><CardContent className="space-y-5">
        <p className="text-3xl font-bold">{formatNumber(0)} CLP</p>
        <ul className="list-disc space-y-3 pl-5">{([0, 1, 2] as const).map(index => <li key={index}>{t(`pilotPricing.freeFeatures.${index}`)}</li>)}</ul>
        <Button asChild className="h-auto whitespace-normal"><Link to="/register">{t('pilotPricing.start')}</Link></Button>
      </CardContent></Card>
      <Card className="min-w-0"><CardHeader><CardTitle>{t('pilotPricing.premium')}</CardTitle><p>{t('pilotPricing.premiumHelp')}</p></CardHeader><CardContent className="space-y-4">
        <label className="block space-y-2"><span className="font-medium">{t('pilotPricing.budget')}</span><select className="w-full min-w-0 rounded-lg border border-input bg-background p-3" value={range} onChange={event => setRange(event.target.value)}>
          <option value="">{t('pilotPricing.choose')}</option>{([0, 1, 2] as const).map(index => <option key={index} value={index}>{t(`pilotPricing.tiers.${index}`)}</option>)}
        </select></label>
        {price && <div aria-live="polite" className="space-y-2"><p>{t('pilotPricing.monthly')}: <strong>{formatNumber(price.monthly)} CLP</strong></p><p>{t('pilotPricing.annual')}: <strong>{formatNumber(price.annual)} CLP</strong></p><p className="text-sm">{t('pilotPricing.discount')}</p></div>}
        <p className="rounded-lg bg-muted p-4 text-sm">{t('pilotPricing.notice')}</p>
      </CardContent></Card>
    </div>
    <section className="rounded-xl border border-border p-6"><h2 className="text-xl font-bold">{t('pilotPricing.emerging')}</h2><p className="my-3 text-muted-foreground">{t('pilotPricing.emergingHelp')}</p><Button asChild variant="outline"><Link to="/contact">{t('pilotPricing.contact')}</Link></Button></section>
  </div>
}
