# Mapa de proyectos — bloque 3

## Ampliación local — 2026-09-12

El mapa básico está desplegado como parte del release anterior. Esta ampliación está
**implementada localmente, no aplicada a SQL ni desplegada**. No activa adjuntos ni
modifica infraestructura, capacidad SQL, autopausa o temporizadores.

### Filtros nuevos y enlace con matching

- Tipo de organización usando el catálogo compartido, ahora incluido también en
  `GET /api/v1/marketplace/catalogs`.
- Brecha por financiar mínima/máxima, inclusivas, de 0 a 999999999999 y hasta cuatro
  decimales. Se usa `FundingGap`, no presupuesto total ni monto habitual de la organización.
  Moneda obligatoria con un monto; sin conversión entre monedas. El presupuesto
  desconocido ya está excluido por la guarda de publicación existente; brecha cero
  sí coincide cuando el intervalo lo admite.
- Necesidad de financiamiento (brecha mayor que cero), aliados, profesionales y
  consorcio. Las últimas tres usan declaraciones existentes del proyecto, no un acuerdo
  confirmado. Las condiciones seleccionadas se combinan con AND.
- Desde matching financiador/fondo → proyectos, “Ver estos resultados en el mapa”
  transmite únicamente los IDs públicos de la página actual. No comparte origen,
  criterios privados ni puntajes; no conserva el orden del ranking ni representa todo
  el universo de coincidencias. Una selección vacía no se convierte en mapa completo.

Parámetros adicionales: `organizationTypeId`, `minimumFundingGap`, `maximumFundingGap`,
`currency`, `seekingFunding`, `seekingPartners`, `seekingProfessionals`, `seekingConsortium`
y `projectIds` repetible (1–50 GUID distintos no vacíos). La API valida antes de SQL.
El repositorio serializa únicamente esos IDs como JSON parametrizado; no SQL dinámico.
La migración `049_project_map_advanced_filters.sql` agrega parámetros opcionales al
procedimiento existente y conserva las dos estructuras de resultados para clientes anteriores.

Todos los filtros se aplican antes de contar y paginar. La selección por IDs no evita
la función de publicación ni el consentimiento de ubicación; proyectos retirados,
borradores o de organizaciones no aptas no deben reaparecer por conocer su ID.
Los conteos de ubicaciones públicas/no públicas usan el mismo conjunto filtrado.

Frontend modularizado en `map-filters.ts`, `map-filters-form.tsx`, página de composición
y vista geográfica existente. URL validada, formularios ES/EN, filtros conservados al
paginar y opción explícita de retirar la selección del matching. No consulta mientras
se escribe, ni usa polling, reintentos, foco o reconexión automáticos. Volver a montar
la página revalida resultados que superaron 60 segundos; GET no usa caché HTTP del cliente.
Esto conserva uso bajo demanda, pero las consultas de usuarios pueden despertar SQL.

### Evidencia del candidato aislado y cierre pendiente

- 943 unitarias .NET y 340 pruebas HTTP con repositorios simulados aprobadas.
- 1.052 pruebas frontend aprobadas; compilación de producción, lint y tipos E2E correctos.
  Este candidato se aisló sobre main, sin los cambios de adjuntos pendientes.
- Pruebas de navegador de filtros avanzados a 320/1024 px, accesibilidad, preservación
  de selección/moneda, paginación y rechazo de montos sin moneda aprobadas. Capturas
  revisadas visualmente. Regresión completa de navegador: **210 aprobadas**, una
  omitida por metadatos exclusivos de Azure que no existen en localhost. Incluye
  el enlace matching → mapa y las pruebas sintéticas de sesión entre ventanas.
- Migración, smoke `049` y fixtures parseados con ScriptDom. Preflight real en Azure SQL:
  **1 migración, 3 lotes, 49/49 smokes y 23 comprobaciones de resultados correctas**.
  Todo se revirtió; no se aplicó la migración permanentemente. Regla temporal de una
  IP retirada y ausencia de reglas temporales comprobada al terminar.
- La skill de navegador no encontró una instancia interactiva; se utilizó la suite
  Playwright existente en localhost con respuestas sintéticas, sin la cuenta del usuario.

Orden de publicación: migración `049` → API → frontend. Ejecutar smokes `027`, `040`,
`041`, `044`, `049` (y regresión completa de SQL) en dev; reapply sin cambios. Luego
verificar el contrato HTTP y los resultados SQL reales por separado: el migrador
ejecuta `ProjectMapSqlVerifier` en `--preflight` y `--test`, siempre dentro de la
transacción que se revierte al finalizar, también ante error. Consume ambos resultados
del procedimiento usando los mismos parámetros que el repositorio de producción.
Los 12 proyectos sintéticos cubren USD/EUR, brecha cero/desconocida, organizaciones
distintas, necesidades combinadas, paginación, selección de IDs y retirada de
publicación/consentimiento. Incluye un registro malformado sin coordenadas para
comprobar la defensa de lectura; no es un ejemplo válido del flujo de edición.
No deja cuentas ni proyectos de prueba publicados, ni reutiliza registros reales.
El preflight real está aprobado; faltan aplicación definitiva, reapply, prueba
posterior y publicación secuencial de API/frontend antes de cerrar el release.
No restaurar `041` mientras siga activa la API nueva: ésta envía los parámetros adicionales.

## Corte histórico del mapa básico

Implementado localmente. Ruta `/marketplace/map`, enlazada desde el catálogo.
API anónima `GET /api/v1/marketplace/project-map`, limitada por `marketplace-read`.

## Contrato y privacidad

Filtros `q` (200 caracteres), país, área de impacto, ODS, etapa y estado independientes.
Página 1–10000; tamaño 1–200, interfaz 100. Orden estable por ID descendente.
La respuesta separa `totalCount` de proyectos mapeables y `withoutPublicLocationCount`:
ambos respetan los filtros y la guarda existente de publicación/organización/adjuntos.
No incluye borradores, coordenadas privadas, correos, contactos ni documentos.

Solo `locationVisibility = 2` y un par válido de coordenadas permiten un punto.
SQL y API redondean a dos decimales. No se deduce una ubicación a partir del país,
localidad o dirección. Los proyectos sin punto continúan disponibles en el catálogo.
La caché pública dura hasta 60 segundos: una retirada de consentimiento puede tardar
ese intervalo en desaparecer de una respuesta ya cacheada.

Mapa base autocontenido Natural Earth, sin fronteras políticas, geocodificación,
teselas externas ni claves nuevas. Proyección simple para descubrimiento, no navegación.
Agrupa solo los resultados de la página actual y lo informa explícitamente.
Zoom y desplazamiento tienen botones de teclado; una lista paralela permite abrir
las fichas sin interactuar con puntos. No hay contactos ni matching implícitos.

## Verificación y despliegue posterior

Migración forward-only `041_project_map.sql`; conserva la función de publicación
existente y concede solo EXECUTE sobre la nueva consulta al rol API.
Smoke `041` de lectura: inspecciona guardas/permisos, rechaza páginas sin límite y
ejecuta ambos resultados. El smoke transaccional `040` sigue cubriendo la proyección
de ubicaciones privadas/públicas; no se ejecutó SQL contra una base real en este corte.

Verificación local: 803 unitarias .NET, 243 HTTP con repositorios simulados,
914 frontend (71 archivos), 162 navegador aprobadas; una comprobación de SHA Azure
omitida en local. Compilación, lint y tipos E2E aprobados. Navegador cubre 320/1024px,
ES/EN sin borrar filtros ni repetir consultas, agrupación, paginación, vacío/reintento,
claro/oscuro y accesibilidad. Las APIs son sintéticas; no se escriben datos reales.

Despliegue posterior: aplicar `041` tras `040`, ejecutar smokes `027`, `040`, `041`
en dev y publicar API antes del frontend. Validar puntos con consentimiento real
controlado y retirada de publicación antes de aceptación. Sin push ni Azure aquí.
