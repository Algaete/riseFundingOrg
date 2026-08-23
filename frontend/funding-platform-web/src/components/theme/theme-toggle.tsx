import { Laptop, Moon, Sun } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { Button } from '@/components/ui/button'
import { useTheme } from '@/hooks/use-theme'

const nextTheme = {
  system: 'light',
  light: 'dark',
  dark: 'system',
} as const

const icons = {
  system: Laptop,
  light: Sun,
  dark: Moon,
} as const

const labels = {
  system: 'Sistema',
  light: 'Claro',
  dark: 'Oscuro',
} as const

export function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const { t } = useTranslation()
  const Icon = icons[theme]

  return (
    <Button
      type="button"
      size="icon"
      variant="ghost"
      onClick={() => setTheme(nextTheme[theme])}
      aria-label={t('actions.changeTheme') + ': ' + labels[theme]}
      title={labels[theme]}
    >
      <Icon className="size-4" aria-hidden="true" />
    </Button>
  )
}
