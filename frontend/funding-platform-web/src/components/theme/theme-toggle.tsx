import { useTranslation } from 'react-i18next'

import type { ThemePreference } from '@/components/theme/theme-context'
import { useTheme } from '@/hooks/use-theme'

const options: ThemePreference[] = ['system', 'light', 'dark']

export function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const { t } = useTranslation()

  return (
    <select
      aria-label={t('actions.changeTheme')}
      className="h-10 w-24 min-w-0 shrink-0 cursor-pointer rounded-lg border bg-card px-2.5 text-sm font-semibold text-card-foreground transition-colors hover:bg-accent"
      onChange={(event) => setTheme(event.target.value as ThemePreference)}
      value={theme}
    >
      {options.map((option) => (
        <option key={option} value={option}>
          {t(`theme.${option}`)}
        </option>
      ))}
    </select>
  )
}
