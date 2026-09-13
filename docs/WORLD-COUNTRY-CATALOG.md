# Financiadores: catálogo mundial de países — 2026-09-12

## Causa y corrección

El selector no estaba limitado a Chile en React: `GET /api/v1/catalogs` devolvía
el catálogo activo de `FundingPlatform_Countries`, cuya migración inicial sólo
insertaba Chile (`152`, `CL`, `CHL`). Agregar opciones únicamente en la interfaz
no permitiría guardarlas porque el servidor valida su existencia en SQL.

La migración **048_world_country_catalog.sql** agrega las identidades faltantes
para completar 249 países y territorios con códigos ISO. Conserva Chile y todas
las referencias existentes. No cambia nombres, fechas, estado activo ni IDs de
filas existentes; si hay una colisión de ID/Iso2/Iso3, falla antes de insertar.
Es aditiva y puede repetirse sin duplicar filas. La transacción es del migrador.

El campo sigue siendo un solo país del financiador, opcional. “Sin país informado”
es `null`, no “Todos los países”. La cobertura mundial de una convocatoria es otro
campo: este cambio no altera elegibilidad, alcance global ni fondos publicados.
Tampoco agrega regiones/subdivisiones extranjeras ni activa adjuntos.

## Procedencia del catálogo

- Códigos numéricos, ISO-2/ISO-3 y nombres ES/EN: tablas `downloadTableES` y
  `downloadTableEN` de [Naciones Unidas, M49](https://unstats.un.org/unsd/methodology/m49/overview/),
  consultadas el 2026-09-12. Se extrajeron 248 filas con ambos códigos ISO válidos;
  no se incluyeron continentes, agrupaciones estadísticas o códigos globales.
- Se completa con `158/TW/TWN`, código ISO recogido en el
  [vocabulario de localizaciones W3C DPVCG](https://www.w3.org/community/reports/dpvcg/CG-FINAL-loc-20240801/#TW),
  que referencia [ISO OBP](https://www.iso.org/obp/ui/#iso:code:3166:TW).
  Etiqueta corta de interfaz: Taiwán / Taiwan. Los códigos son identificadores técnicos,
  no una afirmación sobre soberanía o reconocimiento diplomático.
- El snapshot queda versionado en SQL. No se consulta una API de países durante
  la navegación, ni se agrega dependencia, servicio de pago o sincronización periódica.

## Interfaz y alcance compartido

Las etiquetas ES/EN están separadas en `src/i18n/catalogs/countries-es.ts` y
`countries-en.ts`. Sólo se traducen coincidencias exactas de código y nombre
revisado, conservando el comportamiento existente para etiquetas personalizadas.
Financiadores ordena las opciones alfabéticamente por el idioma visible sin
cambiar el ID seleccionado. El selector cabe en móvil incluso con nombres largos.

La lista común también sirve a organizaciones, fondos, proyectos y directorios que
leen ese catálogo. Se conservan sus filtros de países activos. Una desactivación
previa deliberada no es revertida por esta migración.

## Validación local previa a aislar la publicación

Los totales siguientes corresponden al workspace de desarrollo, que también contiene
trabajo pendiente de otros bloques. El release de países se aisló y volvió a validar
con CI; no incluye la búsqueda unificada ni la preparación de adjuntos.

- 1.031 pruebas de frontend aprobadas; las nuevas usan las 249 filas de la migración,
  verifican orden/idiomas/IDs y guardado con administrador y propietario financiador.
- 931 unitarias .NET aprobadas, incluidas cinco pruebas nuevas de sintaxis Azure SQL,
  unicidad, identidades internacionales, preservación y detección de colisiones.
- Build, lint y tipos E2E aprobados.
- Cuatro pruebas de navegador aprobadas con las 249 opciones: administrador y
  propietario financiador, a 320 y 1280 píxeles, ES/EN, selección, creación, edición
  y reapertura con API sintética. Accesibilidad y desbordamiento aprobados; capturas
  de móvil/escritorio revisadas visualmente. El navegador interactivo no estaba
  disponible y se usó la suite Playwright local del proyecto.
- Smoke SQL `048_world_country_catalog_smoke.sql`: comprueba las 249 identidades y
  crea/actualiza un financiador sintético con Estados Unidos y Japón, siempre en
  borrador y con rollback. En este corte local sólo estaba preparado y parseado;
  su ejecución real quedó aprobada en el release documentado más abajo.

## Publicación Azure dev — 2026-09-12

PR 19 fusionado; commit `1e96564e60b2bb53459bf4254133f7bed05279a7` publicado en
Azure dev. Migración 048 aplicada, reapply con cero cambios y 48/48 smokes SQL
aprobados con rollback de fixtures. La API pública devuelve las 249 identidades
esperadas. El frontend sirve ese SHA y su suite de navegador en Azure está aprobada.
Recargar la página para renovar el catálogo de la sesión anterior.
No se reprovisionó infraestructura ni se cambió el SKU o la autopausa de SQL.
[Evidencia y estado final](runbooks/world-country-catalog-dev-release-2026-09-12.md).
