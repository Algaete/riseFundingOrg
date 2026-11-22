# Catálogo revisado y recuperación de Azure SQL — 22 de noviembre de 2026

## Comportamiento

El primer acceso después de la pausa de Azure SQL produjo HTTP 500 mientras Azure informaba `Resuming`; el mismo catálogo respondió HTTP 200 al terminar la reanudación. Se conserva la pausa automática de 60 minutos.

La fábrica de conexiones con identidad administrada ahora reintenta **abrir la conexión**, hasta cuatro intentos con espera exponencial de 5–15 segundos. No se asigna reintento a comandos SQL ni se repiten transacciones o peticiones HTTP de escritura. La cancelación corta la espera. Los errores permanentes conservan su tratamiento previo. Si se agotan los intentos temporales, la API responde 503 con mensaje genérico, `Retry-After: 10`, `Cache-Control: no-store` y correlación; no expone mensajes SQL.

El catálogo y el inicio de sesión explican una carga de más de cinco segundos. El cliente no multiplica los intentos ya agotados en el servidor; el catálogo permite reintentar expresamente. Las pruebas de navegador cubren recuperación, accesibilidad y ausencia de desbordamiento en 1280 y 390 píxeles.

## Cinco fichas nuevas

| Ficha | Monto original | Recepción comprobada | Condición clave |
| --- | --- | --- | --- |
| [Primer Rufford](https://apply.ruffordsmallgrants.org/help/faqs) | GBP 7.000 | Todo el año | Responsable en inicio de carrera y ONG/universidad administradora; [Chile elegible](https://apply.ruffordsmallgrants.org/help/eligibility). |
| [SST](https://www.sstfoundation.org/wp-content/uploads/2026/07/Funding-guidelines-2026-final.pdf) | CHF 25.000 | Plazo no confirmado | Proyecto vinculado a turismo sostenible; no se presenta como abierto. |
| [Front Line Defenders](https://www.frontlinedefenders.org/en/programme/protection-grants) | EUR 7.500 | Plazo no confirmado | Protección de personas defensoras en riesgo; no se presenta como abierto. |
| [HawkWatch](https://hawkwatch.org/investing-in-others/grrcg/) | USD 3.500 | Hasta 31-12-2026, 23:59 MST | Rapaz prioritaria, responsable local y entidad receptora. |
| [FPA Forjadores 2027](https://fondos.mma.gob.cl/ial_forjadores_fpa2027/) | CLP 1.000.000 | Hasta 15-12-2026, 14:00 Chile continental | Inscripción del grupo antes del 20-11-2026, 23:59. |

Las fuentes oficiales y las condiciones manuales están en `database/Curation/chile-reviewed-catalog-2026-11-22.json`. Los plazos desconocidos quedan fuera de “Solo abiertos” y del matching vigente. Las categorías obligatorias impiden presentar conservación como compatible con un proyecto exclusivamente de salud. No se convierte moneda ni se confunde el aporte con el presupuesto total del proyecto.

La migración 066 agrega GBP y CHF sin cambiar decisiones existentes de activación. La 067 incorpora al listado público el tipo de plazo, su precisión, el cierre UTC y la zona horaria; las fichas muestran recepción continua, hora exacta y restricciones, incluyendo sus traducciones revisadas. El lote se limita a cinco identificadores nuevos y reutiliza el financiador MMA existente. Conserva versiones y recomendaciones históricas. Todas las fuentes nuevas son manuales, sin programación de extracción.

## Fuentes descartadas o pendientes

- [Waitt ROC](https://www.waittfoundation.org/roc-grants): restringido a países socios enumerados; Chile no figura.
- [Impulso Rural](https://fundacionluksic.cl/noticias/impulso-rural-convocatoria-de-fundacion-luksic-apoyara-con-maquinaria-a-negocios-de-mas-de-250-comunas-de-chile/): dirigido a dueños de negocios, no se publica como fondo para ONG.
- FPA Censo del Pingüino de Humboldt: corresponde a la ficha ya existente; no se duplica por variación del título.
- MBZ: no se pudo verificar directamente la fuente oficial; no se publica sobre la sola información de agregadores.
- Santander y FFOP: recepción vigente sin confirmar; pendientes de revisión.

El catálogo pasa de 10 a 15 fichas públicas al aplicar el lote. Eso no equivale a 15 convocatorias abiertas ni cumple aún la meta comercial de 50–60 vigentes.

## Publicación y comprobación

1. CI de la revisión y de main aprobada; desplegar el SHA exacto.
2. Ejecutar `check-dev-database.sh --release` con la confirmación y SHA exigidos por el script. Verificar migraciones 066–067 y repetición sin pendientes.
3. Compilar `FundingPlatform.PilotCatalog` en Release; ejecutar `curate-pilot-dev.sh --preview-resume`.
4. Aplicar con `RF_CATALOG_REVIEWED_CONFIRMATION=PUBLISH-FIVE-REVIEWED-CHILE-OPPORTUNITIES-20261122` y `--apply-resume`. Ambos modos retiran su regla temporal de una sola IP.
5. Comprobar las cinco fichas desde la API pública y la interfaz; contrastar montos, plazos y condiciones. Verificar la carga real tras una pausa si se observa una ventana de inactividad suficiente.

Las pruebas locales quedan en `artifacts/resume-20261122/` (no versionado). La verificación local del lote revierte su transacción y comprueba idempotencia, rechazo de replay alterado, moneda, fechas, foco obligatorio y reutilización del financiador.

Validación local de la recuperación: 1.183 pruebas unitarias, 493 de integración y 1.284 del frontend. La extensión del contrato público agrega cuatro casos de integración y uno de frontend, y comprueba restricciones originales/traducidas. Pasan 67 scripts SQL, 23 contratos de mapa y 13 de traducciones; la publicación local verifica también los plazos devueltos por el procedimiento público real. Compilación, lint y tipos E2E correctos. Las pruebas de navegador cubren demora y recuperación, y la demora visual de doce segundos también se comprobó manualmente en la vista local. CI vuelve a ejecutar las suites completas sobre la revisión final.
