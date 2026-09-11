import type { Ref } from 'react'
import { useTranslation } from 'react-i18next'
import { editorialFieldMessage } from '@/i18n/editorial-messages'
import { fundingFormFieldLabels, type FundingFormError, type FundingFormField } from './funding-form-validation'

export function FundingFormValidationSummary({ errors, summaryRef, onSelectField }: {
  errors: FundingFormError[]
  summaryRef: Ref<HTMLDivElement>
  onSelectField: (field: FundingFormField) => void
}) {
  const { t } = useTranslation()
  if (errors.length === 0) return null
  return (
    <div aria-label={t('adminFunding.saveBlocked')} className="rounded-lg border border-destructive/30 bg-destructive/10 p-4 text-sm text-foreground" ref={summaryRef} role="alert" tabIndex={-1}>
      <p className="font-semibold">{t('adminFunding.saveBlocked')}</p>
      <ul className="mt-2 list-disc space-y-2 pl-5">
        {errors.map(({ field, message }) => (
          <li key={`${field}:${message}`}>
            <button className="text-left underline underline-offset-2" onClick={() => onSelectField(field)} type="button">
              {`${t(`adminFunding.${fundingFormFieldLabels[field]}`)}: ${editorialFieldMessage(message)}`}
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
