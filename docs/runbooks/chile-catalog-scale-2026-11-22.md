# Ampliación revisada del catálogo — 22 de noviembre de 2026

Se revisaron 55 programas o canales de financiamiento. El lote incorpora 14 fichas: 13 con recepción confirmada (incluye consultas iniciales y programas especializados) y una con plazo no confirmado. El catálogo pasa de 15 a 29 fichas públicas. **No se acredita todavía la meta de 50–60 convocatorias abiertas.** La cantidad abierta depende de la fecha; ITI cierra el 22 de noviembre y Pfizer el 25.

Las decisiones, fuentes y motivos de descarte están en `database/Curation/chile-catalog-research-2026-11-22.json`. Las fichas publicables y su evidencia están en `database/Curation/chile-catalog-scale-2026-11-22.json`. Un formulario accesible no basta para clasificar una oportunidad como abierta. Avisos vigentes de suspensión o cierre prevalecen sobre FAQ antiguas y resultados de buscadores.

| Programa | Recepción y condición principal |
| --- | --- |
| GEF/FPA Comunidades | 22-12-2026; CLP 15 millones, domicilio legal en Atacama/Ñuble/Los Ríos, antigüedad y experiencia de un año, contrapartida 1:1. |
| Gilead Latinoamérica | Continua; Chile explícito; prioridad VIH y enfermedades hepáticas, entidad sin fines de lucro registrada. |
| Cisco Global Impact | Consulta inicial continua; hasta USD 75.000 para primera subvención, tecnología y más de 65% de población económicamente desatendida. |
| International Trans Fund SEED | 01-12-2026; USD 10.000–25.000 para nuevos beneficiarios, liderazgo trans y presupuesto anual menor a USD 100.000. |
| Sophie Danforth | 01-01-2027; conservación mundial con entidad receptora, monto máximo no publicado y restricciones expresas a redacción de postulaciones con IA. |
| ALIPH emergencia | Continua; patrimonio cultural en riesgo vinculado a conflictos, en principio hasta USD 75.000. |
| Pulitzer Global Reporting | Continua; periodismo con compromiso de publicación, no campañas institucionales. |
| NBC conservación | Cortes anuales 1 febrero/1 julio; próximo corte calculado 01-02-2027, hasta USD 3.000, responsable local y conservación neotropical. |
| Wikimedia Rapid Fund | Próximo corte 01-02-2027; USD 500–5.000, proyecto y experiencia en Wikimedia, límites por ayudas abiertas y monto anual. |
| EA Animal Welfare | Continua; bienestar animal y costo efectividad. |
| EA Infrastructure | Continua; proyectos vinculados a altruismo eficaz, distinto de CBG cerrado. |
| Oak Special Interest | Consulta inicial continua; propuesta formal solo por invitación, afinidad estratégica y presupuesto disponible. |
| Reporters Respond | Plazo desconocido; emergencia de medios y periodistas, fuera de Solo abiertos. |
| Pfizer ATM-AVI RWE | 25-11-2026 23:59 Nueva York; hasta USD 50.000, investigación clínica específica con responsable cualificado. |

## Incertidumbres conservadas

- Las bases GEF dicen **23:59** en portada y **19:59** en sección 9, ambas de Chile continental. Se publica fecha con precisión de día, sin inventar UTC, y se explica la contradicción y la conveniencia de presentar antes de las 19:59.
- El PDF de Pfizer Quality Improvement señala 17-11-2026 mientras resultados indexados señalan 01-12-2026. Esa convocatoria queda pendiente; no se confunde con la convocatoria RWE del lote.
- No se convierten promedios de adjudicaciones en montos máximos. Montos ausentes permanecen desconocidos.
- Una consulta inicial de Cisco u Oak no es invitación a enviar una propuesta completa. Las fichas lo indican en el título, descripción y condiciones.
- D-Prize, Crowder–Messersmith y NED requieren confirmar elegibilidad de ejecución en Chile. No basta que acepten solicitantes de cualquier nacionalidad.

## Validación y publicación

El publicador tiene una lista cerrada de 14 identificadores nuevos, transacción obligatoria, control de colisiones y rechazo de lote parcial o replay alterado. Reutiliza el financiador MMA y una sola identidad de EA Funds. Las fuentes permanecen manuales, sin cron ni costos de servicios adicionales.

`--verify-scale-local` usa únicamente la base desechable `res` en `127.0.0.1,14363`, prepara las 15 fichas anteriores y revierte al terminar. Comprueba publicación de las 29 fichas por el procedimiento público real, fechas y monedas de cada nueva ficha, regiones y contrapartida GEF, límite presupuestario ITF, conservación de incertidumbres, financiadores compartidos y replay sin cambios. Compara las filas y versiones de las 15 fichas previas antes y después.

1. Compilar `tools/FundingPlatform.PilotCatalog` en Release y ejecutar la validación local.
2. Aprobar CI de PR y main, publicar el SHA exacto mediante los workflows existentes.
3. Ejecutar `infra/scripts/curate-pilot-dev.sh --preview-scale` para verificar el lote en una transacción revertida.
4. Aplicar con `RF_CATALOG_SCALE_CONFIRMATION=PUBLISH-FOURTEEN-REVIEWED-CHILE-OPPORTUNITIES-20261122` y `--apply-scale`; repetir para comprobar cero cambios.
5. Comparar lista y detalle públicos de las 14 fichas, conservar las 15 anteriores y verificar Solo abiertos, filtros territoriales y vistas de escritorio/móvil.
6. Verificar retiro de cada regla SQL temporal de una sola IP. No se requieren migraciones ni cambios de capacidad o facturación.

Evidencias de ejecución en `artifacts/scale-20261122/` (no versionadas). El registro de investigación es reutilizable para futuras revisiones; los pendientes no se publican automáticamente.
