import { useEffect, useState, type ReactNode } from 'react'

import {
  ThemeContext,
  type ThemePreference,
} from '@/components/theme/theme-context'

const storageKey = 'funding-platform-theme'

function storedTheme(): ThemePreference {
  const value = window.localStorage.getItem(storageKey)
  return value === 'light' || value === 'dark' || value === 'system'
    ? value
    : 'system'
}

function applyTheme(theme: ThemePreference) {
  const dark =
    theme === 'dark' ||
    (theme === 'system' &&
      window.matchMedia('(prefers-color-scheme: dark)').matches)
  document.documentElement.classList.toggle('dark', dark)
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<ThemePreference>(storedTheme)

  useEffect(() => {
    applyTheme(theme)
    window.localStorage.setItem(storageKey, theme)

    const media = window.matchMedia('(prefers-color-scheme: dark)')
    const handleChange = () => {
      if (theme === 'system') applyTheme(theme)
    }
    media.addEventListener('change', handleChange)
    return () => media.removeEventListener('change', handleChange)
  }, [theme])

  const setTheme = (nextTheme: ThemePreference) => setThemeState(nextTheme)

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  )
}
