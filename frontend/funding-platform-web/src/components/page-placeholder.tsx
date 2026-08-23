import { ArrowRight, CheckCircle2, Construction } from 'lucide-react'
import type { ReactNode } from 'react'

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface PagePlaceholderProps {
  title: string
  description: string
  eyebrow?: string
  children?: ReactNode
}

export function PagePlaceholder({
  title,
  description,
  eyebrow = 'MVP · Fase 1',
  children,
}: PagePlaceholderProps) {
  return (
    <section className="space-y-6">
      <div className="max-w-3xl">
        <p className="mb-2 text-xs font-bold uppercase tracking-[0.18em] text-primary">
          {eyebrow}
        </p>
        <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">{title}</h1>
        <p className="mt-3 text-base leading-7 text-muted-foreground">
          {description}
        </p>
      </div>

      {children ?? (
        <div className="grid gap-4 lg:grid-cols-3">
          <Card className="lg:col-span-2">
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <Construction className="size-5 text-primary" />
                Módulo preparado
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm text-muted-foreground">
              <p>
                La ruta, navegación responsive y jerarquía visual ya forman parte
                del shell de la aplicación.
              </p>
              <p className="flex items-center gap-2 text-foreground">
                <CheckCircle2 className="size-4 text-primary" />
                La lógica de negocio se integrará en las siguientes entregas.
              </p>
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Próximo paso</CardTitle>
            </CardHeader>
            <CardContent className="flex items-center gap-2 text-sm text-muted-foreground">
              Conectar contrato OpenAPI
              <ArrowRight className="size-4" />
            </CardContent>
          </Card>
        </div>
      )}
    </section>
  )
}
