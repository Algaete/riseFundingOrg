import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import { App } from '@/App'
import { initializeInterfaceLanguage } from '@/i18n'
import '@/index.css'

void initializeInterfaceLanguage().then(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode><App /></StrictMode>,
  )
})
