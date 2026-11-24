# Catálogo revisado — 24 de noviembre de 2026

Este lote agrega diez líneas de seis financiadores, conservando las 45 fichas anteriores. Resultado previsto al revisar: 55 fichas públicas y 50 abiertas o continuas. Son oportunidades para perfiles específicos; no todas sirven a cualquier ONG chilena. Het Actiefonds tiene tres vías oficiales distintas y Thrive tiene dos: no se cuentan como financiadores diferentes.

Fuentes y requisitos por ficha: `database/Curation/chile-catalog-more-2026-11-24.json`. Investigación y descartes: `database/Curation/chile-catalog-research-2026-11-24.json`. La cobertura se registra solo para Chile y sus 16 regiones durante el piloto, aun cuando el programa acepte otros países.

| Línea | Monto y condición principal |
| --- | --- |
| Vegan Grants | Recepción continua; monto no publicado. Activismo con mensaje vegano, dirigido a públicos no veganos o influyentes; prepostulación en inglés. |
| Thrive Grant | USD 10.000–30.000; siguiente corte el 01-12-2026 a las 23:59 GMT. Trayectoria demostrada; se prioriza a antiguas beneficiarias. |
| Thrive Seed | Hasta USD 5.000; mismo corte. Iniciativas nuevas, pequeñas y personas sin registro de ONG. |
| Het Actiefonds regular | Hasta EUR 2.500; acciones directas no violentas; presentar al menos un mes antes. |
| Rainforest Trust | Notas conceptuales todo el año; propuestas completas por invitación. ONG registrada, nueva protección o ampliación de áreas y criterios de biodiversidad. |
| OTF Internet Freedom | USD 10.000–900.000, hasta 24 meses; tecnología contra censura y vigilancia represiva, con contrato y pagos por entregables. |
| OTF respuesta rápida | Emergencias digitales; apoyo técnico o financiero. El rango habitual USD 1–50.000 no es un límite obligatorio. |
| EA Funds IA transformativa | Recepción continua para investigación, gobernanza y capacidades relacionadas con riesgos de IA avanzada. Los montos habituales no son límites. |
| Het Actiefonds justicia climática | Hasta EUR 2.500 por grupo y año; fortalecimiento de movimientos, redes y estrategias. |
| Het Actiefonds urgente | Hasta EUR 250; acción ante un hecho imprevisto, no una actividad planificada que busca fondos a última hora. |

## Precisión editorial

- Los dos programas Thrive publican recepción actual y cuatro cortes anuales. Se representa el siguiente corte conocido, sin inventar apertura. Su preferencia por presupuestos institucionales inferiores a USD 500.000 no se convierte en condición excluyente.
- Het Actiefonds excluye proyectos con presupuesto superior a EUR 20.000. Se permite exactamente EUR 20.000; la preferencia por organizaciones pequeñas no se transforma en un máximo institucional obligatorio. No evalúa en agosto y prohíbe solicitudes redactadas por IA; ambas condiciones quedan visibles.
- Rainforest Trust permite considerar propuestas sólidas fuera de trópicos y subtrópicos si cumplen los demás criterios. Esto permite evaluar proyectos chilenos, sin prometer elegibilidad. USD 10.000 es el promedio de estudios de factibilidad, no un máximo.
- OTF respuesta rápida y EA Funds presentan montos habituales, no límites de elegibilidad: sus campos de mínimo y máximo permanecen desconocidos. OTF no financia digitalización general de una ONG; EA Funds no financia cualquier chatbot.
- Las páginas oficiales OTF respondieron 200 mediante HTTP público aunque el lector web devolvía 403. Se revisó el contenido público sin cuentas ni elusión de autenticación.
- Digital Defenders y CIVICUS están pausados; Roddenberry no anuncia programas abiertos; DRK no incluye Chile en sus territorios actuales. No se publican como abiertos.

## Publicación y verificación

El publicador acepta exclusivamente diez IDs y slugs, exige transacción, valida versiones y colisiones, conserva las 45 fichas anteriores y rechaza una repetición con contenido alterado. Reutiliza los financiadores compartidos, incluido EA Funds ya existente. Las fuentes permanecen manuales y sin cron.

1. Compilar `tools/FundingPlatform.PilotCatalog` y ejecutar `--verify-more-local` en la base descartable `res` de `127.0.0.1,14363`. Se revierte toda la transacción: inserción de diez, repetición sin cambios, 55 fichas públicas, límites críticos, UTC, fuentes, financiadores y filtros de las 16 regiones.
2. Integrar tras CI del PR y comprobar CI del commit de main. Este lote es de datos: registrar por separado el commit del catálogo y el de la aplicación publicada; no requiere desplegar API ni frontend.
3. Ejecutar `bash infra/scripts/curate-pilot-dev.sh --preview-more`, con reversión.
4. Aplicar con `RF_CATALOG_MORE_CONFIRMATION=PUBLISH-TEN-REVIEWED-CHILE-OPPORTUNITIES-20261124` y `--apply-more`. Repetir para comprobar cero cambios. El script comprueba PITR y elimina al salir su regla SQL temporal de una sola IP.
5. Comparar las diez fichas públicas con el lote y las 45 previas con su captura anterior. Verificar cinco páginas sin duplicados, Solo abiertos, categorías, tipos y las 16 regiones, conservando la restricción territorial GEF. Revisar las fichas seleccionadas en escritorio y móvil.
6. Registrar resultados efectivos y limitaciones en `artifacts/expand-20261124/`, no versionado. Un fallo de acceso al navegador no se registra como revisión visual aprobada.

No se añaden servicios pagados ni se modifica capacidad de Azure. No se crean cuentas ni se presentan postulaciones a los financiadores.
