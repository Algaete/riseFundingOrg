import { useTranslation } from 'react-i18next'

import type { ThemePreference } from '@/components/theme/theme-context'
import { useTheme } from '@/hooks/use-theme'

const options: Array<{ label: string; value: ThemePreference }> = [
  { label: 'Sistema', value: 'system' },
  { label: 'Claro', value: 'light' },
  { label: 'Oscuro', value: 'dark' },
]

export function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const { t } = useTranslation()

  return (
    <select
      aria-label={t('actions.changeTheme')}
      className="h-10 cursor-pointer rounded-lg border bg-card px-2.5 text-sm font-semibold text-card-foreground transition-colors hover:bg-accent"
      onChange={(event) => setTheme(event.target.value as ThemePreference)}
      value={theme}
    >
      {options.map((option) => (
        <option key={option.value} value={option.value}>
          {option.label}
        </option>
      ))}
    </select>
  )
}
