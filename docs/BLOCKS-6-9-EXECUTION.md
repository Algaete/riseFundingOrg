# Bloques restantes: 6–9

Solicitud: continuar los cuatro bloques restantes sin confirmaciones entre pasos.
El tablero tiene tres bloques funcionales pendientes; el cuarto corresponde a validación
integrada y despliegue dev. No se incluyen producción, cambios de cuentas, compra de servicios,
acceso a fuentes restringidas ni ampliación de privilegios permanentes.

- [x] 6. Matching ampliado: financiador/oportunidad → proyectos; proyecto/organización →
  organizaciones y profesionales; criterios, brechas y datos desconocidos explícitos.
- [ ] 7. Oportunidades e ingesta: clasificación/filtros ampliados, fuente/actualización,
  conector de feed autorizado y revisión editorial; ninguna autopublicación ni scraping restringido.
- [ ] 8. Multimedia: video y documentos adicionales privados con formatos/límites explícitos,
  inspección, cuarentena/scan, descarga segura y retención; sin publicación automática.
- [ ] 9. Verificación integrada y despliegue dev: pruebas, preflight SQL/infraestructura,
  release reproducible API/worker/frontend y comprobación real de funciones habilitadas.

Cada cierre requiere pruebas y commit local. Los permisos, servicios de pago y credenciales
que falten para activar integraciones se registrarán como bloqueos reales, no como completados.

## Cierre local del bloque 6

Ruta `/matching/ecosystem`; motor determinista `ecosystem-rules-v1`. Solo candidatos públicos
u opt-in; origen privado limitado a su titular. Clasifica coincidencias, brechas y datos desconocidos,
muestra evidencia y cobertura; no convierte moneda, no presume elegibilidad por domicilio del
financiador, no puntúa «Otros» y no envía invitaciones. Evalúa los 200 candidatos visibles más
recientes y avisa cuando hay más; no se presenta como ranking exhaustivo ni predicción de éxito.

Validación focalizada: 18 pruebas .NET unitarias/permisos, 4 HTTP, 7 frontend y 2 E2E ES/EN
320/1024 px, accesibilidad, build y tipos aprobados. Migración/smoke 044 preparados; ejecución
SQL y disponibilidad en Azure pendientes del bloque 9. La búsqueda desde financiador requiere
prioridades explícitas; la elegibilidad legal/regional definitiva y el consentimiento siguen siendo humanos.
