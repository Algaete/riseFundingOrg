# Catálogo revisado — 23 de noviembre de 2026

Este lote agrega 16 oportunidades con recepción confirmada y elegibilidad internacional o chilena, conservando las 29 fichas previas. Resultado previsto: 45 fichas públicas y 40 abiertas o continuas al 23 de noviembre. **La meta de 50–60 abiertas sigue pendiente.** No todas sirven a cualquier ONG: varias exigen actividad, liderazgo, trayectoria o un tipo de establecimiento específico.

Fuentes y evidencia por ficha: `database/Curation/chile-catalog-next-2026-11-23.json`. Decisiones de investigación, descartes y pendientes: `database/Curation/chile-catalog-research-2026-11-23.json`. No se infiere apertura por formularios históricos, resultados de buscadores o calendarios anuales.

| Oportunidad | Condición principal y plazo |
| --- | --- |
| FAE establecimientos RBD | Colegio subvencionado con perfil artístico; hasta CLP 10 millones; 03-12 a las 15:00 de Santiago. Gestión e investigación requieren contrapartida de 10%. |
| Erase Indifference | Iniciativas ejecutadas que movilizan testigos de discriminación; premios EUR 10.000–20.000; 04-12, 23:59 CET. |
| MAPFRE innovación social | Dos integrantes equivalentes a jornada completa, uno a tiempo completo, y más de EUR 100.000 de ingresos/inversión 2024–2026 sin préstamos; 01-12, 23:59 CET. |
| Allianz MoveNow | Liderazgo 18–30 años, al menos 51% de control joven, entidad de hasta cinco años; 18-12, 17:00 UTC. Restricción expresa sobre IA. |
| Coefficient incubadoras | Incubación de organizaciones de alto impacto y costo efectividad; primera etapa hasta 18-12, 23:59 Pacífico. Propuesta completa solo por invitación. |
| Awesome Conservation and Climate | Proyecto ambiental concreto de pequeña escala, USD 1.000; 27-11, hora no publicada. |
| Keeling Curve Prize | Soluciones climáticas operativas; USD 50.000; 15-01-2027, 23:59 UTC−12. Puede cerrar al completar 500 postulaciones elegibles; restricciones de IA. |
| Food Planet Prize | Nominación y autonominación continua de innovaciones alimentarias con beneficio ambiental. Monto de futura edición desconocido. |
| Box Impact Fund | Digitalización de ONG, USD 25.000; entidades fuera de EE. UU. tienen límite de USD 5.000 para inversión de capital en software/hardware; 30-11, 17:00 Pacífico. |
| IFFS | Seguridad de pescadores comerciales; recepción continua, contacto y aprobación inicial obligatorios antes de presentar. |
| Awesome On the Water | Capítulo mundial distinto, proyectos creativos vinculados al agua, USD 1.000 mensuales. |
| Lush Charity Pot | Reabierto el 01-11; GBP 100–10.000, ingresos anuales estrictamente menores de GBP 350.000. |
| SAVE THE NIGHT | Cultura nocturna inclusiva y segura, representante de al menos 21 años al 01-10; 01-12, 23:59 CET. Excluye antiguos ganadores y fiestas aisladas; exige exclusividad de marcas. |
| Terre de Femmes | Mujeres o colectivo de mujeres, proyecto de arbolado urbano con ONG de al menos un año; EUR 10.000; portal cierra 30-11 a las 22:59 UTC. |
| Global Schools Prize | Solo escuelas de educación obligatoria o su entidad titular; cuenta bancaria escolar y dos firmantes; 16-12, hora no publicada. |
| Lloyd’s Register Foundation | Ingeniería y seguridad, entidad registrada, hasta GBP 10.000 y 12 meses; 14-12, 23:59 GMT. |

## Criterios de precisión

- SAVE THE NIGHT ofrece una bolsa conjunta de EUR 156.000, no un máximo individual conocido. Food Planet muestra montos de la edición 2026, que no se trasladan a futuras nominaciones.
- Global Schools entrega USD 50.000 a ganadores de categoría y USD 500.000 adicionales al ganador general: USD 550.000 es el máximo acumulado inferido de esa estructura, explicado en la ficha.
- El cierre Keeling UTC−12 corresponde al día siguiente en UTC: 16-01-2027 a las 11:59. `Etc/GMT+12` conserva el signo de la zona IANA.
- Cuando solo se conoce el día, no se inventa una hora. Cuando las bases prohíben o limitan generación con IA, la restricción queda visible.
- La página oficial de Lloyd’s respondió 403 al lector web y 200 al acceso HTTP público; se revisó su contenido completo. Ninguna ficha requiere consultar datos de cuentas.

## Publicación y verificación

El publicador limita el lote a 16 IDs y slugs exactos, exige transacción, comprueba versiones y colisiones, preserva las 29 fichas y sus versiones, y rechaza cambios a un lote ya aplicado. Reutiliza el financiador Ministerio de las Culturas de PAOCC. Cada fuente queda manual y sin cron.

1. Compilar el publicador y ejecutar `--verify-next-local` en la base descartable `res`, exclusivamente en `127.0.0.1,14363`. La transacción se revierte; se comprueban 45 resultados públicos, requisitos críticos, monedas, UTC, repetición sin duplicados y rechazo de replay alterado.
2. Integrar después de CI de PR y comprobar CI del commit de main. El lote no cambia API, frontend ni infraestructura: registrar por separado el commit del catálogo y el de la aplicación publicada.
3. Ejecutar `bash infra/scripts/curate-pilot-dev.sh --preview-next`, con reversión.
4. Aplicar con `RF_CATALOG_NEXT_CONFIRMATION=PUBLISH-SIXTEEN-REVIEWED-CHILE-OPPORTUNITIES-20261123` y `--apply-next`; repetir para comprobar cero cambios. El script verifica PITR y retira la regla SQL temporal de una sola IP al salir.
5. Comparar todas las fichas nuevas en lista y detalle públicos, conservar los campos y versiones de las 29 previas, verificar Solo abiertos y filtros. Revisar visualmente listado, restricciones y fechas en escritorio y móvil.
6. Registrar resultados efectivos, CI y evidencia en `artifacts/expand-20261123/` (no versionado). Una limitación del navegador no equivale a una prueba visual aprobada.

No se activan robots, servicios de IA pagados, cambios de capacidad ni suscripciones adicionales.
