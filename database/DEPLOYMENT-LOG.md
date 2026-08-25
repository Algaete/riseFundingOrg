# Registro de despliegues de base de datos

Este registro contiene únicamente metadatos operativos no sensibles de los cambios
`FundingPlatform_*` aplicados a la base compartida `res`.

## Preflight FASE 2 — 2026-08-12T03:06:48Z

- Base objetivo verificada: `res` (`Online`, Azure SQL Standard S0).
- Migración prevista: baseline `001`, aditiva y limitada a objetos `FundingPlatform_*`.
- Backups automáticos: activos con redundancia geográfica.
- Ventana PITR verificada: 7 días; punto restaurable más antiguo observado
  `2026-08-05T03:03:39Z`.
- Geo-backup observado: disponible a `2026-08-12T02:05:28Z`.
- LTR e inmutabilidad: no configuradas; decisión pendiente antes del piloto productivo.
- Validación transaccional: correcta; el rollback de `--validate` dejó 0 objetos
  `FundingPlatform_*` antes de la aplicación real.

## Aplicación baseline 001 — registro actualizado 2026-08-12T03:43:15Z

- Base objetivo verificada y aplicada: `res`.
- Migración: `001_initial_schema.sql`.
- SHA-256 registrado: `a6fe03d9ae312ee907ab63500be1c5dd7a8158327ed4a3ae5d97e163ad39884c`.
- Estado posterior: 1 de 1 migraciones aplicada en `FundingPlatform_SchemaVersions`.
- Inventario propio: 41 tablas de negocio más la tabla de metadata
  `FundingPlatform_SchemaVersions`, 4 tipos de tabla (TVP) y 8 procedimientos
  almacenados.
- Segunda ejecución de `--apply`: 0 aplicadas / 0 pendientes; resultado idempotente.
- La hora anterior corresponde a la actualización de este registro. No se conservó
  una hora distinta de ejecución del `--apply`.

El baseline queda limitado a catálogos y seed Chile, identidad base,
organizaciones/perfiles, oportunidades/fuentes canónicas, entitlements Free y outbox.
FASE 6 incorporó posteriormente evidence editorial y el límite seguro de documentos; FASE 7A
agregó la adquisición durable y el contenido bruto de Grants.gov; FASE 7B agregó extracción PDF,
gobierno de fuentes, retención y recepción Defender/Event Grid fail-closed. La activación de los
recursos Defender/Event Grid continúa como operación de infraestructura. FASE 8A agregó catálogo
organizacional, filtros, detalle completo, favoritos privados y Full-Text con fallback literal;
FASE 8B preparó localmente marketplace de proyectos, postulaciones y calendario derivado, pero su
migración `019` no se desplegó ni se validó contra ninguna base. FASE 9A completó localmente el motor
determinístico y preparó la migración `020`, también sin conexión ni despliegue. FASE 9B-A prepara
localmente la migración `021` para embeddings project-first y evaluación corpus-level sólo en sombra;
tampoco se conectó ni se desplegó. El proveedor real, IA generativa, billing y alertas conservan fases
posteriores del roadmap.

No se registra la cadena de conexión, la identidad de despliegue ni ningún secreto.

## Aplicación de identidad 002/003/004 — FASE 3

- Base objetivo verificada: `res`.
- `002_identity_security.sql` aplicada con SHA-256
  `18f752e8d63753260d485c316164060d126141650689d0854215e2bec45606e7`.
- `003_superadmin_bootstrap.sql` aplicada con SHA-256
  `2063267368e3285a239e3de607072ee2c04374bdf8c9968fe28eba23ed44e931`.
- `004_security_token_reissue_cooldown.sql` aplicada con SHA-256
  `5080d21b056ac35ed48509c233082afacd5ac4d41e2af6eb0d8a14d43fa10375`.
- Validación previa transaccional completada; después de aplicar, los tres smoke tests
  iniciales y el smoke de cooldown se ejecutaron en Azure SQL: cuatro scripts, cuatro
  lotes y rollback de todos sus fixtures.
- No se creó un SuperAdmin ni se envió un correo real durante la aplicación.
- Los secretos criptográficos permanecen en Key Vault y el key ring de Data Protection
  permanece cifrado en Blob; ningún valor secreto forma parte de las migraciones.

No se conserva una hora de aplicación independiente y por eso no se fabrica una en
este registro.

## Aplicación de onboarding 005 — FASE 4

- Base objetivo verificada: `res`.
- `005_organization_onboarding.sql` aplicada con SHA-256
  `6a0ceecefd8069fe1ad415ca123b43293a0cf2dd6502c355e33bd2f670ac5302`.
- `--validate` ejecutó una migración/un lote y revirtió todos los cambios antes de aplicar.
- `--status` confirmó cinco migraciones locales y cinco aplicadas, sin cambios de checksum.
- La suite SQL ejecutó cinco scripts/cinco lotes y revirtió todos los fixtures.
- El smoke 005 comprobó alta transaccional, owner membership, aislamiento A/B, snapshots v1/v2,
  reemplazo N:N, `RowVersion` y eventos de outbox.
- No se añadieron tablas ni secretos; los procedimientos nuevos siguen la convención
  `FundingPlatform_usp_*` y reciben identificadores públicos en el límite de la API.

## Aplicación 006/007 — inicio de FASE 5

- Base objetivo verificada: `res`.
- `006_entra_sso.sql` aplicada con SHA-256
  `7c9b3aee0935226bb96cb5f446fff8712f5ac3e733dbfb924b135c6a308e0e1c`.
- `007_projects_core.sql` aplicada con SHA-256
  `11e915f71a46059afd8e38ec5e020ba54de3cca8730d50ba8b9a5a37d53cf5b3`.
- La validación transaccional previa ejecutó dos scripts/dos lotes y revirtió los cambios.
- La aplicación ejecutó dos scripts/dos lotes.
- La suite posterior ejecutó siete scripts/siete lotes y revirtió todos sus fixtures.
- El smoke SSO comprobó alta de identidad y consumo atómico de handoff. El smoke Project comprobó
  dos proyectos distintos, aislamiento entre dos organizaciones, funding gap, snapshots v1/v2,
  `RowVersion` y outbox.
- No se configuró ni almacenó un secreto de Entra durante la migración.

## Aplicación 008 — cierre de FASE 5 (observado 2026-08-21T15:34:36Z)

- Base objetivo verificada con `SELECT 1`: `res`.
- `008_project_publication_workflow.sql` aplicada con SHA-256
  `4b0d326325c5f46ddd6269a562fcc796d1bc416a6c394b60be39936f87d3a561`.
- La validación definitiva ejecutó una migración/dos lotes dentro de una transacción y
  revirtió todos los cambios antes de aplicar.
- La aplicación ejecutó una migración/dos lotes. `--status` confirmó ocho migraciones
  locales y ocho aplicadas, sin cambios de checksum; inventario observado: 587 objetos
  propios `FundingPlatform_*`.
- La suite SQL ejecutó ocho scripts/ocho lotes y revirtió todos los fixtures. El smoke 008
  cubrió readiness, ETag, idempotencia y conflicto de clave, rechazo/reenvío/aprobación,
  archivo, cola/detalle admin, proyección pública fail-closed, ausencia de PII y trazabilidad
  de `ProjectVersion + OrganizationProfileVersion` en eventos/outbox.
- Una segunda ejecución de `--apply` devolvió 0 migraciones/0 lotes.
- La hora del encabezado es la observación posterior del despliegue; no se presenta como la
  marca exacta de commit registrada por Azure SQL.

## Aplicación 009 — resultados de vinculación Entra (observado 2026-08-21T17:46:16Z)

- Base objetivo verificada: `res`.
- `009_entra_link_outcomes.sql` aplicada con SHA-256
  `02f111574184fe111585b2021337959ce9c149ff2820ad70e2dbf37298987c07`.
- La validación previa ejecutó una migración/un lote dentro de una transacción y revirtió
  todos los cambios.
- La aplicación ejecutó una migración/un lote. `--status` confirmó nueve migraciones
  locales y nueve aplicadas, sin cambios de checksum.
- La suite SQL ejecutó nueve scripts/nueve lotes y revirtió todos sus fixtures. El smoke 009
  comprobó vinculación inicial, reintentos idempotentes y ausencia de identidades duplicadas.
- La migración no modifica, fusiona ni elimina usuarios o identidades existentes.

## Aplicación 010/011 — cierre de FASE 6 (observado 2026-08-21T20:29:15Z)

- Base objetivo verificada por el migrador: `res`.
- `010_funders_editorial_workflow.sql` aplicada con SHA-256
  `a52da9a2c4e47ccc992c7584cbb06645cf4dc223dccdc380cf43684210ae6a11`.
- `011_source_document_upload.sql` aplicada con SHA-256
  `85fe96b107cd820500ecbdcd325ac7f7e71a20aebc6b61247cda9c06a6587498`.
- La validación previa ejecutó dos migraciones/44 lotes dentro de una transacción y revirtió
  todos los cambios. La aplicación real ejecutó dos migraciones/44 lotes.
- El primer gate SQL detectó que el smoke histórico 002 esperaba el result set anterior de
  `RefreshToken_Rotate`. Se actualizó únicamente ese fixture para incluir
  `MfaAuthenticatedAtUtc`; no se modificó ninguna migración aplicada. La ejecución definitiva
  pasó 11 scripts/11 lotes y revirtió todos los fixtures.
- `--status` confirmó 11 migraciones locales y 11 aplicadas, sin cambios de checksum, y 831
  objetos propios `FundingPlatform_*` observados. Una segunda ejecución de `--apply` devolvió
  0 migraciones/0 lotes.
- El smoke 010 cubre funders/oportunidades, evidence, staging, ETag, idempotencia, correcciones,
  taxonomías activas y proyecciones públicas fail-closed. El smoke 011 cubre intent, lease,
  reanudación, cuarentena, estados de scan, retry, replay, redacción y outbox.
- La hora del encabezado es la observación posterior del cierre y no se presenta como la marca
  exacta del commit de Azure SQL. No se registraron credenciales, SAS, tokens ni rutas privadas
  de Blob.

## Aplicación 012 — grant operativo SuperAdmin (observado 2026-08-21T22:03:33Z)

- Base objetivo verificada por el migrador: `res`.
- `012_superadmin_role_grant.sql` aplicada con SHA-256
  `ec60c00e646c781c8a2c90be13ef570931d5f5d2e68fff9a42a615fe1742f278`.
- `--validate` ejecutó una migración/tres lotes y revirtió todos los cambios antes de aplicar.
- `--status` confirmó 12 migraciones locales y 12 aplicadas, sin cambios de checksum, y 833
  objetos propios `FundingPlatform_*` observados.
- La suite SQL ejecutó 12 scripts/12 lotes y revirtió todos los fixtures. El smoke 012 comprobó
  grant, replay idempotente, cuentas inexistentes/no elegibles, MFA inalterado, rotación de seguridad,
  revocación de refresh tokens, auditoría sin PII y ownership transaccional.
- Una segunda ejecución de `--apply` devolvió 0 migraciones/0 lotes.
- La operación autorizada dejó una única cuenta SuperAdmin, mostrada por las herramientas solo como
  `a***2@gmail.com`; sus sesiones refresh anteriores quedaron revocadas y MFA quedó pendiente de setup.
- La hora del encabezado corresponde al evento auditado del grant, no a la marca exacta de commit de
  la migración. No se registraron contraseñas, tokens, security stamps ni cadenas de conexión.

## Aplicación 013/014/015 — cierre de adquisición durable FASE 7A (observado 2026-08-22)

- Base objetivo verificada por el migrador: `res`.
- `013_source_link_identity_alignment.sql` quedó aplicada antes del nuevo pipeline y alinea la
  clave de identidad de vínculos externos existentes con la referencia canónica editable.
- `014_durable_acquisition.sql` quedó validada y aplicada; `--status` confirmó su registro sin
  discrepancia de checksum.
- SHA-256 `013`:
  `412a7eade922d644099244084b61524f29f4181a92a20ac98f871f5899f88358`.
- SHA-256 `014`:
  `1d744783127a8107d22c6218b12c7be74161464dd034fca94d4a3a2822500b6e`.
- SHA-256 smoke `014`:
  `beead55a6d68222d2d75b8b5744cd15e1dcdbf457f61d2648d5c56bbe40196f5`.
- El vertical agrega Grants.gov como API oficial gobernada, runs/items/errores, raw inmutable,
  snapshot normalizado durable, leases, idempotencia, scheduler, outbox, Queue y watchdog. Toda
  oportunidad importada permanece en borrador y exige revisión humana para publicarse.
- El smoke de runtime posterior a la aplicación detectó un defecto acotado en el patrón SQL que
  validaba correlation IDs con guion. `014` no se modificó: la reparación quedó en
  `015_import_run_correlation_format.sql`, forward-only.
- SHA-256 `015`:
  `ee0a75641df9de32210ff54979b06c5a10542ffca1cc07fd8437eed34471f88c`.
- SHA-256 smoke `015`:
  `b6598cc6df6d667d17b257d20f5cac1572ad958dbd506bc4dbd4dcb5e8913fa8`.
- `--validate` de `015` ejecutó una migración/dos lotes y revirtió los cambios. `--apply` ejecutó
  una migración/dos lotes.
- La suite definitiva pasó 15 scripts/15 lotes con rollback. Una segunda ejecución de `--apply`
  devolvió 0 migraciones/0 lotes.
- `--status` confirmó la base `res`, 15 migraciones locales/15 aplicadas sin discrepancias y 940
  objetos propios `FundingPlatform_*`.
- No se registraron payloads raw, palabras clave, correlation IDs, credenciales ni cadenas de
  conexión en este log.

La fecha del encabezado es la fecha de observación del cierre; no se presenta como hora exacta de
commit de Azure SQL.

## Aplicación 016 — cierre de FASE 7B (observado 2026-08-22)

- Base objetivo verificada por el migrador: `res`.
- `016_governed_document_extraction.sql` quedó aplicada con SHA-256
  `96d435dcee7f898a44b59f918c61e52717211476c365231f6f3518288430ec52`.
- El smoke `016_governed_document_extraction_smoke.sql`, ajustado solo como fixture durante 8A sin
  cambiar la migración `016`, tiene como SHA-256 vigente
  `4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c`.
- `--validate` ejecutó una migración/74 lotes dentro de una transacción y revirtió todo. La
  aplicación real ejecutó una migración/74 lotes.
- La suite definitiva pasó 16 scripts/16 lotes con rollback. Una segunda ejecución de `--apply`
  devolvió 0 migraciones/0 lotes.
- `--status` confirmó 16 migraciones locales/16 aplicadas sin discrepancias y 1227 objetos propios
  `FundingPlatform_*`.
- Los fixtures históricos ajustados al contrato vigente quedaron en SHA-256: smoke `010`
  `8e602c3cef17d13959478a6bc425cb6e9bc1d238a5262682c3911cf928378d23`, smoke `011`
  `f7c0b320a1f7276e284425f8c17c9efd357056d2ca15acb9b1daa8d62b1e183b` y smoke `014`
  `beead55a6d68222d2d75b8b5744cd15e1dcdbf457f61d2648d5c56bbe40196f5`. Las migraciones
  publicadas permanecieron inmutables.
- El esquema agrega gobierno exacto de fuentes, extracción/acotación documental, recibos mínimos de
  Defender, decisiones humanas de duplicados, retención/redacción y el rol de mínimo privilegio
  `FundingPlatform_ExtractionWorkerRole` con seis grants `EXECUTE`.
- Esta ejecución solo cambió Azure SQL. No creó identidades administradas, RBAC, Event Grid ni
  Defender for Storage, no activó servicios pagados y no se presenta como E2E real de Defender.
- No se registraron contenido extraído/raw, rutas/ETags/hashes de Blob, IDs de identidades reales,
  credenciales ni cadenas de conexión.

La fecha del encabezado es la fecha de observación del cierre; no se presenta como hora exacta de
commit de Azure SQL.

## Aplicación 017 — identidad de funder primary (observado 2026-08-22)

- `016` permanece aplicada e inmutable; la reparación se entregó como
  `017_primary_funder_identity_hardening.sql`, forward-only.
- SHA-256 de la migración (600 líneas/13 lotes):
  `214848f1384ba2f6b428fd550e363c538aee509284de49bd2c8feb1a744382ad`.
- SHA-256 del smoke (517 líneas/un lote):
  `b38a14a457e197efdd1b283613622bc61a370855898d539793714478bcb27862`.
- `--validate` ejecutó una migración/13 lotes dentro de una transacción y revirtió todo. `--apply`
  ejecutó una migración/13 lotes.
- La suite posterior pasó 17 scripts/17 lotes con rollback. Una segunda ejecución de `--apply`
  devolvió 0 migraciones/0 lotes.
- `--status` confirmó 17 migraciones locales/17 aplicadas sin discrepancias y 1251 objetos propios
  `FundingPlatform_*`.
- El cambio impide que un nombre normalizado baste para vincular una oportunidad a un funder: exige
  una identidad HTTPS canónica fuerte coincidente o registra el conflicto para revisión y bloquea
  catálogo/publicación mientras siga abierto.
- No elimina vínculos históricos cuya autoría no puede probarse, no reemplaza primary links curados
  y no autopublica contenido.
- No se habilitaron ni facturaron Defender/Event Grid o RSS, ni se registraron URLs/hashes del
  ledger, credenciales o cadenas de conexión.

## Aplicación 018 y Full-Text — cierre de FASE 8A (observado 2026-08-22)

- Base objetivo verificada por el migrador: `res`.
- `018_funding_search_and_favorites.sql` quedó aplicada con SHA-256
  `4b1fd2c54220a5209e39a3ed78c890220617707325e4ffdf236a54f4809492c4` (947 líneas/10 lotes).
- El smoke `018_funding_search_and_favorites_smoke.sql` quedó con SHA-256
  `ad078055fff7bfc41b03a3bfa56ecc3e198d9c9688940213b71016fa36b76caa` (575 líneas/un lote).
- El provisioning no transaccional `001_funding_opportunity_full_text.sql` quedó con SHA-256
  `4dad7d2263baa0b55c65ea8e5925a4194a0e5cd6de854f3d85742a542cc4b2c5` (176 líneas/tres lotes).
- `--validate` ejecutó una migración/10 lotes dentro de una transacción y revirtió todo; `--apply`
  ejecutó una migración/10 lotes.
- El primer `--test` posterior revirtió sus cambios y expuso un fixture `016` cuyo timestamp estaba
  un segundo por delante de `SYSUTCDATETIME()`. Solo el smoke se corrigió para usar su `@NowUtc` y
  pasó aislado 5/5; la migración `016` permaneció aplicada e inmutable. Su fixture final tiene 2140
  líneas y SHA-256 `4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c`.
- La suite definitiva pasó 18 scripts/18 lotes con rollback. Una segunda ejecución de `--apply`
  devolvió 0 migraciones/0 lotes.
- El estado previo a provisionar confirmó 18 migraciones locales/18 aplicadas, 1266 objetos propios
  y Full-Text no aprovisionado; en ese estado la búsqueda literal de respaldo permanecía operativa.
- `--provision-full-text` ejecutó un script/tres lotes fuera de una transacción y reportó inicialmente
  poblando. El estado posterior confirmó Full-Text listo; la suite volvió a pasar 18/18 con rollback.
- Una segunda provisión ejecutó el mismo manifiesto idempotente (un script/tres lotes) y terminó
  nuevamente lista. El `--status` final confirmó 18/18 migraciones sin discrepancias, 1267 objetos
  propios `FundingPlatform_*` y Full-Text listo.
- `018` agrega búsqueda/detalle organizacional y favoritos privados. No implementa compatibilidad,
  matching, elegibilidad, IA o embeddings y no altera el catálogo público existente.
- El modo híbrido conserva un complemento literal sobre seis columnas para no perder coincidencias.
  Se registra como deuda P2 de rendimiento: se medirán planes/Query Store antes de escalar al volumen
  objetivo; este cierre no afirma un p95 de producción.
- Esta ejecución no creó servicios Azure externos ni activó recursos pagados. No se registraron
  términos buscados, favoritos reales, credenciales, cadenas de conexión ni contenido de fondos.

## Preparación local 019 — FASE 8B, sin despliegue (2026-08-24)

- Se preparó `019_project_marketplace_applications_calendar.sql` con SHA-256
  `eeb6962329261b6736b4e3584d1409e622f1a26a2947bbe3b3ae25a660df53ef`
  (1184 líneas, 14 separadores `GO`/15 lotes).
- Se preparó `019_project_marketplace_applications_calendar_smoke.sql` con SHA-256
  `7feccc8bb44f63f776df0b16f313ac9e06c8a421d51904764fe24d1da9732ab9`
  (860 líneas, un separador `GO`/dos lotes).
- Los artefactos cubren guardas públicas fail-closed del marketplace, postulaciones privadas con
  idempotencia/rowversion y calendario derivado; no agregan matching, IA, alertas ni billing.
- Por instrucción del propietario no se abrió una conexión a Azure SQL ni a otro entorno DB y no se
  ejecutaron `--validate`, `--apply`, `--test` o `--status` para `019`.
- Por lo anterior, el último estado observado de `res` sigue siendo el cierre 8A de 18/18
  migraciones. Este registro no inventa una aplicación 19/19, lotes ejecutados, object count,
  idempotencia de despliegue ni smoke SQL exitoso.
- El parsing local con ScriptDom terminó correctamente y pasaron 4/4 pruebas de arquitectura 8B.
  Estas verificaciones estáticas no sustituyen una corrida transaccional real en SQL Server/Azure
  SQL. La aplicación de `019` requerirá un cambio
  posterior, explícito y autorizado, con preflight, backup/PITR y registro de resultados observados.
- No se crearon recursos Azure, no se activaron servicios pagados y no se registraron credenciales,
  cadenas de conexión, PII ni datos reales de postulaciones.

## Preparación local 020 — FASE 9A, sin despliegue (2026-08-24)

- Se preparó `020_deterministic_project_matching.sql` con SHA-256
  `984450d06cb17447be8b3af595caa6415ce9e59f2b5e4d53bc3466ce2b25921e`
  (1718 líneas, 15 separadores `GO`/16 lotes).
- Se preparó `020_deterministic_project_matching_smoke.sql` con SHA-256
  `a827cc9234831c757583b2e6776c13d2550985dcce566653dc171616f3e036f6`
  (924 líneas, sin separadores `GO`/un lote).
- Los artefactos cubren perfiles/reglas/pesos inmutables, ejecuciones históricas por proyecto,
  matches y desglose explicable, idempotencia durable, catálogo reproducible y TOP 200 determinístico.
- El perfil `v1` evalúa nueve reglas con hard gates `Pass`/`Fail`/`Unknown`. Los datos desconocidos
  aportan cero y reducen cobertura sin renormalizar; un hard `Fail` clasifica `Incompatible` con
  score no aplicable. Los otros estados de presentación son `Compatible` y `Datos insuficientes`.
- La superficie API/UI permite calcular sincrónicamente, listar historial y consultar un detalle con
  versiones, vigencia, score, cobertura, razones, advertencias y evidencia allowlisted.
- Por instrucción del propietario no se abrió una conexión a Azure SQL ni a otro entorno DB y no se
  ejecutaron `--validate`, `--apply`, `--test` o `--status` para `019` o `020`.
- Por lo anterior, el último estado observado de `res` continúa siendo el cierre 8A de 18/18
  migraciones. Este registro no inventa 19/19 o 20/20, lotes aplicados, object count, idempotencia de
  despliegue ni smokes SQL exitosos. La activación futura debe aplicar `019` antes de `020`, con
  preflight, backup/PITR y registro de resultados observados.
- El parsing estático T-SQL 170 y la inspección AST de ambos artefactos terminaron limpios. Estas
  comprobaciones no sustituyen una ejecución transaccional contra SQL Server/Azure SQL.
- El gate local de aplicación pasó build .NET (0 warnings/0 errores), 281/281 pruebas unitarias,
  123/123 de integración, lint frontend, 21 archivos/104 pruebas Vitest y build de producción. El foco
  archived/matching pasó 2 archivos/6 pruebas. Ningún gate abrió una conexión SQL.
- FASE 9A no usa OpenAI, IA, embeddings ni similitud semántica y sus resultados son orientativos:
  no constituyen una recomendación ni confirman elegibilidad.
- No se crearon recursos Azure, no se activaron servicios pagados y no se registraron credenciales,
  cadenas de conexión, PII ni datos reales de matching.

## Preparación local 021 — FASE 9B-A, sin despliegue (2026-08-25)

- Se preparó `021_shadow_semantic_evaluation.sql` con SHA-256
  `f6a7cc2a7faba60edce4611c58f56850cf6fd1000b50d7a2f55a53ab188737c3` (3995 líneas/48 lotes).
- Se preparó `021_shadow_semantic_evaluation_smoke.sql` con SHA-256
  `64ad6a521c0eaa6bbb3674b8b0966e572731110eafef57c84b87726baa94cfbc` (1710 líneas/un lote).
- Los artefactos cubren configuración semántica inmutable, corpus humano versionado, jobs/leases,
  reservas de presupuesto y ledger, `VECTOR(1536)`, corridas shadow, métricas agregadas e
  idempotencia. El sujeto privado es la versión exacta del proyecto; el sujeto global es la versión
  exacta del contenido público de la oportunidad. No se crea un embedding institucional.
- `021` no siembra una configuración activa ni un corpus real etiquetado. Los fixtures del smoke se
  revierten y no se registran como datos evaluados; una carga futura requiere revisión y cambio
  controlado.
- La evaluación no actualiza runs, matches, score, clasificación, vigencia u orden de 9A y no agrega
  rutas al frontend. Su administración es exclusivamente Admin/SuperAdmin con MFA reciente.
- Los vectores y resultados shadow quedan inmutables para reproducibilidad. 9B-A no agrega una
  purga; retención/borrado y ciclo de vida con proveedor real son gates de 9B-B.
- `021` crea los roles `FundingPlatform_SemanticWorkerRole` (11 SP de procesamiento) y
  `FundingPlatform_SemanticAdminRole` (backfill + cuatro SP administrativos), con DML directo
  denegado sobre las 11 tablas semánticas. No crea usuarios ni membresías. Un despliegue futuro debe
  asignarlos respectivamente a los principals distintos del worker general/API; esto no crea una
  UAMI semántica adicional ni reemplaza sus otros permisos mínimos. Ninguno será `db_owner`, tendrá
  DML semántico directo o recibirá ambos roles semánticos.
- El único adapter incluido es el fake léxico determinístico de desarrollo/testing, con costo cero y
  sin red. No se llamó a OpenAI, no se entrenó un modelo, no se usó Azure ML y no se habilitó un
  proveedor hosted.
- Por instrucción del propietario no se abrió una conexión a Azure SQL ni a otro entorno DB y no se
  ejecutaron `--validate`, `--apply`, `--test` o `--status` para `019`, `020` o `021`.
- Por lo anterior, el último estado observado de `res` continúa siendo el cierre 8A de 18/18
  migraciones. Este registro no declara 19/19, 20/20 o 21/21, lotes aplicados, object count,
  idempotencia de despliegue ni smokes SQL exitosos. La activación futura debe aplicar `019`, `020` y
  `021` en ese orden, con preflight, backup/PITR y registro de resultados observados.
- El parsing local ScriptDom terminó correctamente para los 48 lotes de la migración y el lote del
  smoke. El gate local pasó build .NET con 0 warnings/0 errores, 324/324 pruebas unitarias, 136/136
  de integración, lint frontend, 21 archivos/104 pruebas Vitest y build de producción. Ninguna de
  estas validaciones abrió una conexión SQL; el parsing estático no sustituye una ejecución
  transaccional contra SQL Server/Azure SQL.
- 9B-B conserva como pendientes el proveedor real y sus evals, DPA/retención/ciclo de vida de datos,
  Structured Outputs, explicaciones generativas y cualquier promoción de la señal semántica.
- No se crearon recursos Azure, no se activaron servicios pagados y no se registraron credenciales,
  cadenas de conexión, PII, prompts, respuestas crudas ni entradas canónicas.
