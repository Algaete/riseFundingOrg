# Base de datos

Esta carpeta contiene los artefactos SQL versionados de FundingPlatform. El baseline
ejecutable de **FASE 2** fue validado y aplicado contra Azure SQL real.

## Estado Azure dev — 2026-08-27

Azure SQL dev tiene registradas y aplicadas `001`→`028`. La migración forward-only
`029_sql_hyphen_allowlist_compatibility.sql` permanece pendiente de aplicación. El preflight final
la ejecutó en siete lotes, completó 29/29 smokes y revirtió íntegramente la transacción: la cadena
local de 29 migraciones/355 lotes quedó validada sin agregar `029` al historial Azure. Full-Text,
reapply/status final, principals runtime y bootstrap SuperAdmin también están pendientes.

### Snapshot anterior al primer apply

La cadena completa `001`→`028` pasó `DatabaseMigrator --validate` contra
`sql-rf-dev-ag26rf01-centralus/risefunding-dev`: 28 migraciones/348 lotes dentro de una única
transacción, seguidos de rollback completo. En ese snapshot la base dev todavía no tenía historial
ni migraciones aplicadas. No se ejecutaron `--apply`, los 28 smokes mediante `--test`, Full-Text,
reapply/status, principals runtime o bootstrap de SuperAdmin.

Artefactos corregidos; las migraciones de esta lista quedaron validadas:

- `019_project_marketplace_applications_calendar.sql`: 1188 líneas/14 lotes, SHA-256
  `6d6e9a0a86a3ea7ff31c5ae43f31b4528aaa16d9ad14cd9a9f1cbecdbad3ebcd`;
- `019_project_marketplace_applications_calendar_smoke.sql` (corregido, todavía no ejecutado):
  905 líneas/un lote, SHA-256
  `eb346bf26c9226df80a93eb7bdd3f2900254f437e252ffaf94548254b4a8fbeb`;
- `021_shadow_semantic_evaluation.sql`: 3995 líneas/47 lotes, SHA-256
  `e7f10a5b9fa50969c69abaefac9f56c8b23022886f39ccd93f2c7546c4127993`;
- `022_governed_openai_provider.sql`: 789 líneas/10 lotes, SHA-256
  `a804657adabb4906da96fa2024025630782b4b0149c631f720513e401696a585`;
- `023_shadow_structured_explanations.sql`: 2164 líneas/25 lotes, SHA-256
  `4566bcacf528ed355033dbb80f0751ebb8e8a94cb5d6207126b426cf7a947ede`;
- `025_organization_networking.sql`: 717 líneas/10 lotes, SHA-256
  `06bf9e4351bb2054cb335a1e16cb9a4a6ec02c724dea1aafb005162eb801c6e4`.

Las secciones de preparación por fase preservan el estado y las huellas de sus cierres locales
originales. Este snapshot documenta la validación previa al apply y no reemplaza el estado posterior
de 28 migraciones aplicadas descrito arriba.

## Estado de FASE 2

La migración `001_initial_schema.sql`, con SHA-256
`a6fe03d9ae312ee907ab63500be1c5dd7a8158327ed4a3ae5d97e163ad39884c`, está aplicada
en la base compartida `res`. `--status` confirmó 1 de 1 migraciones aplicada y el
inventario resultante contiene 41 tablas de negocio más
`FundingPlatform_SchemaVersions`, 4 tipos de tabla (TVP) y 8 procedimientos
almacenados. Una segunda ejecución de `--apply` encontró 0 migraciones aplicables y
0 pendientes, confirmando la idempotencia del migrador.

## Estado de FASE 3

Las migraciones aditivas `002_identity_security.sql`,
`003_superadmin_bootstrap.sql` y `004_security_token_reissue_cooldown.sql` también
están aplicadas en `res` y conservan el
baseline 001 inmutable.

- `002` agrega seis tablas de seguridad y siete procedimientos para tokens de un solo
  uso, sesiones refresh rotativas, replay, MFA, recovery y auditoría de autenticación.
- `003` agrega el procedimiento de bootstrap único del primer SuperAdmin, protegido
  por application lock y sin permitir tomar control de un email existente.
- `004` conserva durante cinco minutos el enlace vigente de verificación o reset ante
  reenvíos repetidos, evitando que un doble clic lo invalide.
- Los tests `002_identity_security_smoke.sql` y
  `003_superadmin_bootstrap_smoke.sql`, junto con el smoke específico de `004`, se
  ejecutaron con el smoke 001: cuatro scripts, cuatro lotes y rollback completo de
  todos los fixtures.

SHA-256 registrados:

- `002`: `18f752e8d63753260d485c316164060d126141650689d0854215e2bec45606e7`
- `003`: `2063267368e3285a239e3de607072ee2c04374bdf8c9968fe28eba23ed44e931`
- `004`: `5080d21b056ac35ed48509c233082afacd5ac4d41e2af6eb0d8a14d43fa10375`

## Estado de FASE 4

La migración aditiva `005_organization_onboarding.sql` está aplicada en `res` con SHA-256
`6a0ceecefd8069fe1ad415ca123b43293a0cf2dd6502c355e33bd2f670ac5302`.
Agrega cinco procedimientos por `PublicId` para catálogos, listado, alta, lectura y actualización
del perfil. Reutiliza el agregado y los cuatro TVP del baseline, conserva las transacciones
auditadas y evita exponer IDs internos en la API.

`005_organization_onboarding_smoke.sql` ejecuta fixtures reversibles para comprobar creación
atómica, membresía owner/admin, aislamiento A/B del listado, snapshot v1, actualización con `RowVersion`,
snapshot v2, relaciones N:N y outbox. La corrida completa quedó en cinco scripts/cinco lotes,
todos revertidos.

## Estado de FASE 5

Las migraciones aditivas `006_entra_sso.sql`, `007_projects_core.sql`,
`008_project_publication_workflow.sql` y `009_entra_link_outcomes.sql` están aplicadas en `res`.

- `006` agrega identidades Microsoft Entra y handoffs de autenticación opacos, hasheados y de un solo uso.
- `007` agrega proyectos, snapshots/versiones, cinco relaciones normalizadas y cuatro SP tenant-safe.
- `008` agrega el historial append-only de publicación, columnas e invariantes del workflow y ocho
  SP para solicitud, archivo, revisión administrativa, cola, detalle y proyección pública segura.
- `009` diferencia una vinculación externa nueva de un reintento sobre la misma identidad y usuario,
  evitando mostrar un falso “vinculado ahora”.
- SHA-256 `006`: `7c9b3aee0935226bb96cb5f446fff8712f5ac3e733dbfb924b135c6a308e0e1c`.
- SHA-256 `007`: `11e915f71a46059afd8e38ec5e020ba54de3cca8730d50ba8b9a5a37d53cf5b3`.
- SHA-256 `008`: `4b0d326325c5f46ddd6269a562fcc796d1bc416a6c394b60be39936f87d3a561`.
- SHA-256 `009`: `02f111574184fe111585b2021337959ce9c149ff2820ad70e2dbf37298987c07`.
- `--validate` ejecutó `009` en un lote y revirtió todos sus cambios. Después de aplicar,
  `--status` confirmó 9/9 y `--test` ejecutó nueve scripts/nueve lotes con rollback completo.

Los proyectos siguen naciendo como `Draft`; solo pasan a público después de readiness,
solicitud tenant y aprobación explícita de Admin/SuperAdmin con MFA. Rechazo, reenvío,
archivo, concurrencia por rowversion e idempotencia por hash quedan cubiertos por el smoke 008.

## Estado de FASE 6

Las migraciones aditivas `010_funders_editorial_workflow.sql` y
`011_source_document_upload.sql` están aplicadas en `res`.

- `010` agrega funders, aliases, versiones y eventos editoriales; amplía las oportunidades
  con versionado, relaciones, evidence y staging externo; implementa CRUD, revisión,
  corrección, desactivación y lectura pública fail-closed. También conserva el instante MFA
  original a través de las rotaciones refresh.
- `011` agrega intents de upload, documentos verificados/cuarentenados y eventos de scan;
  sus SP separan rutas privadas de Blob de los contratos HTTP y hacen reanudables la
  finalización y el retry.
- SHA-256 `010`:
  `a52da9a2c4e47ccc992c7584cbb06645cf4dc223dccdc380cf43684210ae6a11`.
- SHA-256 `011`:
  `85fe96b107cd820500ecbdcd325ac7f7e71a20aebc6b61247cda9c06a6587498`.
- `--validate` ejecutó 2 migraciones/44 lotes y revirtió todo. `--status` confirmó 11/11
  aplicadas y 831 objetos propios. La suite ejecutó 11/11 smokes con rollback; una segunda
  aplicación devolvió 0 migraciones/0 lotes.

El upload de FASE 6 usa `DevelopmentFake` de forma visible para probar `Clean`,
`Malicious`, `Failed`, timeout y retry. FASE 7B agregó el receptor Event Grid autenticado y la
revalidación ETag/SHA fail-closed; en producción permanecen deshabilitados hasta que el operador
configure Defender/Event Grid y valide un E2E real. Una SAS create-only no impone tamaño ni MIME:
`/complete` los verifica por streaming antes de crear/promover el documento.

## Administración operativa posterior a FASE 6

La migración `012_superadmin_role_grant.sql` está aplicada en `res` con SHA-256
`ec60c00e646c781c8a2c90be13ef570931d5f5d2e68fff9a42a615fe1742f278`.
Agrega dos SP de operador local: listado de Admin/SuperAdmin y promoción segura de una cuenta
existente. El grant exige cuenta activa y confirmada, usa application lock, conserva el estado MFA,
rota el security stamp, incrementa la versión de seguridad, revoca sesiones refresh y registra un
evento de autenticación sin correo ni secretos. El smoke 012 verifica éxito, replay, rechazo,
auditoría, revocación y ownership transaccional con rollback.

El cierre de esa etapa confirmó 12/12 migraciones, 12/12 smokes SQL, 833 objetos propios y una
segunda aplicación sin cambios.

## Estado de FASE 7A

Las migraciones aditivas `013_source_link_identity_alignment.sql` y
`014_durable_acquisition.sql`, junto con el hotfix forward-only
`015_import_run_correlation_format.sql`, están aplicadas en `res`.

- `013` alinea `SourceItemKeyHash` con la referencia externa canónica usada por el flujo editorial,
  sin crear oportunidades ni alterar contenido publicado.
- `014` agrega gobierno y calendario de fuentes, `ImportRuns`, raw inmutable, snapshots normalizados
  durables, items, errores y SP transaccionales para creación, consulta, claim/renew, staging,
  cierre/retry, scheduler, outbox y watchdog.
- Grants.gov queda sembrado como proveedor oficial aprobado y con `AutoPublish=false`; el pipeline
  solo crea o actualiza borradores para revisión humana.
- El smoke ejecutado después de aplicar `014` detectó un defecto acotado en el patrón de validación
  de correlation IDs que contienen guion. Como `014` ya estaba aplicada e inmutable, `015` reemplaza
  el constraint/SP mediante una migración nueva y prueba correlations manuales/programadas.

SHA-256 registrados:

- `013`: `412a7eade922d644099244084b61524f29f4181a92a20ac98f871f5899f88358`;
- `014`: `1d744783127a8107d22c6218b12c7be74161464dd034fca94d4a3a2822500b6e`;
- smoke `014`: `beead55a6d68222d2d75b8b5744cd15e1dcdbf457f61d2648d5c56bbe40196f5`;
- `015`: `ee0a75641df9de32210ff54979b06c5a10542ffca1cc07fd8437eed34471f88c`;
- smoke `015`: `b6598cc6df6d667d17b257d20f5cac1572ad958dbd506bc4dbd4dcb5e8913fa8`.

El cierre observado el 2026-08-22 pasó `--validate` de `015` (una migración/dos lotes,
rollback), `--apply` (una/dos), `--test` (15 scripts/15 lotes, rollback), segunda aplicación
(0/0) y `--status`: 15 migraciones locales/15 aplicadas, sin discrepancias, y 940 objetos propios.

## Estado de FASE 7B

La migración aditiva `016_governed_document_extraction.sql` está aplicada en `res`.

- Agrega políticas de adquisición inmutables con endpoint/hosts exactos, licencia, robots, rate,
  tamaño y retención; recibos mínimos de Defender y trust policies exactas para Event Grid.
- Agrega jobs/resultados/evidencia de extracción, decisiones humanas de duplicados y retención que
  redacta contenido vencido. El staging continúa creando únicamente borradores y preserva el funder
  principal humano.
- Crea `FundingPlatform_ExtractionWorkerRole` con `EXECUTE` solo sobre seis SP: claim, renovación de
  lease, evidencia, complete, fail y requeue del watchdog. No concede tablas, schema, importación ni
  administración.
- SHA-256 migración `016`:
  `96d435dcee7f898a44b59f918c61e52717211476c365231f6f3518288430ec52`.
- SHA-256 vigente del smoke `016`, tras la corrección exclusiva del fixture durante 8A:
  `4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c`.
- SHA-256 de fixtures históricos ajustados al contrato vigente: smoke `010`
  `8e602c3cef17d13959478a6bc425cb6e9bc1d238a5262682c3911cf928378d23`, smoke `011`
  `f7c0b320a1f7276e284425f8c17c9efd357056d2ca15acb9b1daa8d62b1e183b` y smoke `014`
  `beead55a6d68222d2d75b8b5744cd15e1dcdbf457f61d2648d5c56bbe40196f5`. Ninguna migración
  aplicada se modificó.

El cierre observado el 2026-08-22 ejecutó `--validate` de `016` (una migración/74 lotes y
rollback), `--apply` (una/74), `--test` (16 scripts/16 lotes y rollback), segunda aplicación (0/0)
y `--status`: 16 migraciones locales/16 aplicadas, sin discrepancias, y 1227 objetos propios.

### Hardening forward-only 017

`017_primary_funder_identity_hardening.sql` está aplicado como corrección aditiva posterior a 016,
que permanece inmutable. Impide reutilizar un funder únicamente por nombre normalizado: exige
identidad HTTPS canónica fuerte coincidente, conserva primary links ya curados y registra
colisiones/legado incierto en un ledger mínimo para revisión humana, sin URLs/hashes en la proyección
administrativa. Un conflicto abierto bloquea catálogo/publicación.

- SHA-256 migración `017`:
  `214848f1384ba2f6b428fd550e363c538aee509284de49bd2c8feb1a744382ad` (600 líneas/13 lotes).
- SHA-256 smoke `017`:
  `b38a14a457e197efdd1b283613622bc61a370855898d539793714478bcb27862` (517 líneas/un lote).
- `--validate` ejecutó una migración/13 lotes y revirtió todo; `--apply` aplicó una/13; la suite
  posterior pasó 17 scripts/17 lotes con rollback; la segunda aplicación devolvió 0/0.
- `--status` confirmó 17 migraciones locales/17 aplicadas, sin discrepancias, y 1251 objetos
  propios `FundingPlatform_*`.

La migración crea el rol, pero no inventa ni vincula un principal Azure. En el despliegue, el
operador crea el usuario de la UAMI `C` exacta del consumidor extractor usando su `clientId` como
SID binario y la agrega al rol sin resolución de Microsoft Graph:

~~~sql
CREATE USER [<nombre-identidad>]
    WITH SID = <0x-sid-binario-del-client-id>, TYPE = E;
ALTER ROLE [FundingPlatform_ExtractionWorkerRole]
    ADD MEMBER [<nombre-identidad>];
~~~

El flujo actual no calcula ese literal manualmente: `DatabaseMigrator
--provision-runtime-identities` recibe nombre y `clientId`, comprueba el SID y la membresía exacta.

La conexión SqlClient del extractor usa `Authentication=Active Directory Managed Identity` y
`User Id=<client-id-de-C>`. Conectado como esa identidad, `USER_NAME()` debe devolver el
principal esperado; `HAS_PERMS_BY_NAME` debe devolver 1 para
`FundingPlatform_usp_SourceDocumentExtraction_Claim` y 0 para
`FundingPlatform_usp_SourceDocumentExtraction_AdminStart` y lectura directa de
`FundingPlatform_SourceDocuments`.

Antes de la aplicación real, `--validate` ejecutó el baseline dentro de una
transacción y su rollback dejó 0 objetos propios. El detalle operativo, incluido el
preflight de backups/PITR, está en [DEPLOYMENT-LOG.md](DEPLOYMENT-LOG.md).

## Estado de FASE 8A

La migración transaccional `018_funding_search_and_favorites.sql` está aplicada en `res`. Agrega
`FundingPlatform_GuidIdList`, favoritos privados con clave `(OrganizationId, UserId,
FundingOpportunityId)`, guardas fail-closed compartidas del catálogo, índices de acceso y cinco
procedimientos para búsqueda organizacional, detalle publicado y listar/agregar/quitar favoritos.
La búsqueda admite filtros N:N mediante TVP, órdenes allowlisted y paginación server-side; no usa el
perfil o un proyecto para calcular matching ni confirma elegibilidad.

El Full-Text de 8A no forma parte de la migración porque `CREATE FULLTEXT INDEX` no puede ejecutarse
dentro de su transacción. El script idempotente
`Provisioning/001_funding_opportunity_full_text.sql` se ejecuta de forma explícita:

~~~bash
./.dotnet/dotnet run --project tools/FundingPlatform.DatabaseMigrator/FundingPlatform.DatabaseMigrator.csproj -- --provision-full-text
~~~

El migrador valida que `018` esté aplicada con el checksum local exacto, toma application locks de
sesión, rechaza configuración incompatible y crea un catálogo dedicado con seis columnas neutrales,
change tracking `AUTO` y stoplist del sistema. `--apply` no ejecuta provisioning; `--validate` solo
valida su manifiesto y reporta el estado sin mutarlo; `--status` lo informa por separado. Sin índice
listo, el procedimiento usa la búsqueda literal de respaldo. Con el índice listo combina su ranking
con el complemento literal para preservar cobertura.

Esa cobertura tiene una deuda P2 consciente: una consulta textual sigue calculando coincidencias
literales sobre seis columnas aun en modo Full-Text. Antes del volumen objetivo se revisarán planes y
Query Store para decidir si el complemento debe acotarse; 8A no afirma que ya se haya demostrado su
p95 con 100.000 oportunidades.

Hashes finales:

- migración `018` (947 líneas/10 lotes):
  `4b1fd2c54220a5209e39a3ed78c890220617707325e4ffdf236a54f4809492c4`;
- smoke `018` (575 líneas/un lote):
  `ad078055fff7bfc41b03a3bfa56ecc3e198d9c9688940213b71016fa36b76caa`;
- provisioning `001` (176 líneas/tres lotes):
  `4dad7d2263baa0b55c65ea8e5925a4194a0e5cd6de854f3d85742a542cc4b2c5`.

El cierre observado el 2026-08-22 pasó `--validate` (una migración/10 lotes y rollback), `--apply`
(una/10), 18/18 smokes con rollback, segunda aplicación 0/0 y `--status` pre-provisioning con 18/18
migraciones, 1266 objetos y Full-Text no aprovisionado. La provisión ejecutó un script/tres lotes,
pasó de poblando a listo y, tras otro gate 18/18, una segunda provisión terminó nuevamente lista. El
estado final confirmó 18/18 migraciones sin discrepancias, 1267 objetos propios y Full-Text listo.

El primer `--test` posterior a aplicar `018` revirtió todo y descubrió que el smoke histórico `016`
creaba un job un segundo en el futuro respecto de `SYSUTCDATETIME()`. Solo se corrigió el reloj del
fixture a su `@NowUtc`; `016_governed_document_extraction.sql` permaneció inmutable. El smoke `016`
final tiene 2140 líneas y SHA-256
`4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c`.

## Estado de FASE 8B

La migración forward-only `019_project_marketplace_applications_calendar.sql` y su smoke están
preparados en el repositorio, pero **no están aplicados ni validados contra `res`, Azure SQL u otro
entorno de base de datos**. Por instrucción del propietario, este cierre no ejecutó `--validate`,
`--apply`, `--test` ni `--status`; en consecuencia no se declara una versión 19 aplicada, un conteo
de objetos posterior ni una corrida SQL exitosa de 8B.

`019` prepara dos tablas para postulaciones e idempotencia durable, claves compuestas que garantizan
la pertenencia organización/proyecto/responsable, constraints de estado, moneda, monto y fechas,
guardas reutilizables del marketplace y procedimientos para:

- buscar y paginar proyectos públicos, abrir su detalle y proyectar un perfil organizacional seguro;
- listar, crear, leer y actualizar postulaciones privadas con aislamiento tenant, ownership,
  `Idempotency-Key` y ETag/rowversion;
- derivar un calendario acotado desde cierres, postulaciones, proyectos y favoritos, sin una tabla de
  calendario duplicada;
- reconocer en el consumidor de auditoría los eventos allowlisted de creación/actualización sin
  enviar notas, montos ni otra carga privada.

El contrato público exige proyectos activos y `Published` pertenecientes a organizaciones activas
con perfil completo y catálogos vigentes. No proyecta usuarios, membresías, correos, identificadores
tributarios ni drafts. El contrato privado requiere sesión completa y membresía activa; todos los
miembros pueden leer, mientras que solo el owner de la postulación o un Admin de la organización
puede modificarla. Las postulaciones `Discarded` no generan hitos de calendario.

Los hashes y tamaños finales de ambos artefactos se registran sobre los archivos locales congelados;
identifican contenido versionado y **no** prueban que haya sido ejecutado en SQL Server:

- migración `019` (1184 líneas/15 lotes):
  `eeb6962329261b6736b4e3584d1409e622f1a26a2947bbe3b3ae25a660df53ef`;
- smoke `019` (860 líneas/dos lotes):
  `7feccc8bb44f63f776df0b16f313ac9e06c8a421d51904764fe24d1da9732ab9`.

El parsing local con ScriptDom terminó correctamente y las cuatro pruebas de arquitectura 8B
pasaron. Son comprobaciones estáticas; no equivalen a ejecutar los lotes contra un motor SQL.

## Estado de FASE 9A

La migración forward-only `020_deterministic_project_matching.sql` y su smoke están preparados
localmente. **No se aplicaron ni probaron contra `res`, Azure SQL u otro entorno de base de datos**:
no se ejecutaron `--validate`, `--apply`, `--test` o `--status`, no se declara una migración `020`
aplicada y el último estado observado de `res` continúa siendo 18/18. El historial forward-only exige
aplicar primero `019` y luego `020` mediante el migrador y el preflight autorizado.

Huellas de los artefactos locales congelados:

- migración `020` (1718 líneas/16 lotes):
  `984450d06cb17447be8b3af595caa6415ce9e59f2b5e4d53bc3466ce2b25921e`;
- smoke `020` (924 líneas/un lote):
  `a827cc9234831c757583b2e6776c13d2550985dcce566653dc171616f3e036f6`.

El parsing local T-SQL 170 y la inspección AST terminaron sin errores. Son gates estáticos y no
sustituyen una corrida transaccional real en SQL Server/Azure SQL.

El gate local de código de 9A pasó build .NET (0 warnings/0 errores), 281/281 pruebas unitarias,
123/123 de integración, lint frontend, 21 archivos/104 pruebas Vitest y build de producción; el foco
archived/matching pasó 2 archivos/6 pruebas. Ninguno de estos resultados ejecutó SQL contra una base.

`020` prepara perfiles, reglas y pesos inmutables; ejecuciones por proyecto; resultados por fondo;
desglose por regla; y solicitudes de idempotencia durable. Las funciones y procedimientos
allowlisted resuelven candidatos abiertos, huella del catálogo y ruleset, resumen vigente, alta
síncrona y consultas de historial/detalle. La transacción fija un snapshot reproducible de versiones,
usa todo el catálogo evaluable para su huella y materializa como máximo los primeros 200 candidatos
en orden determinístico. Un cambio posterior de proyecto, perfil, fondo, catálogo, calendario o
ruleset hace que el resultado deje de ser vigente sin reescribir el historial.

La configuración publicada, los runs, desgloses y requests son inmutables; en el perfil solo puede
alternarse `IsActive` para seleccionar/desactivar la versión operativa. Un match solo puede pasar de
vigente a reemplazado dentro del recálculo transaccional; no puede reactivarse ni alterar su score,
clasificación, versiones o evidencia histórica. El run también conserva slug/título del proyecto para
que una edición posterior no reetiquete el historial.

Una clave nueva exige proyecto/perfil vigentes y listos. El replay de la misma clave valida la
membresía y el tenant actuales, pero devuelve el run histórico antes de reevaluar readiness; así un
proyecto archivado o stale no vuelve imposible recuperar la respuesta durable original.

El perfil `deterministic-project-v1` suma nueve reglas y 100% de peso: geografía 20%, tipo de
organización 15%, figura jurídica 15%, años de operación 10%, experiencia previa 10%, categorías
10%, beneficiarios 5%, tipo de proyecto 5% y monto 10%. Las cinco primeras son condiciones
excluyentes con estado agregado `Pass`/`Fail`/`Unknown`. `Unknown` aporta cero y reduce cobertura,
sin renormalizar los demás pesos; un `Fail` produce `Incompatible` y score `NULL`, mientras un hard
gate `Unknown` sin fallos produce `InsufficientData`.

La persistencia contiene únicamente identificadores, snapshots/versiones, razones, parámetros y
evidencia estructurada allowlisted necesarios para explicar el cálculo. 9A no almacena prompts,
respuestas de modelos ni vectores: no usa IA, embeddings o similitud semántica y no declara una
recomendación ni confirma elegibilidad.

## Estado de FASE 9B-A

La migración forward-only `021_shadow_semantic_evaluation.sql` y su smoke están preparados
localmente. **No se aplicaron ni probaron contra `res`, Azure SQL u otro entorno de base de datos**:
no se ejecutaron `--validate`, `--apply`, `--test` o `--status`, no se declara una migración `021`
aplicada y el último estado observado de `res` continúa siendo 18/18. El orden forward-only exige
aplicar `019`, luego `020` y finalmente `021` mediante el migrador y el preflight autorizado.

Huellas de los artefactos locales congelados:

- migración `021` (3995 líneas/48 lotes):
  `f6a7cc2a7faba60edce4611c58f56850cf6fd1000b50d7a2f55a53ab188737c3`;
- smoke `021` (1710 líneas/un lote):
  `64ad6a521c0eaa6bbb3674b8b0966e572731110eafef57c84b87726baa94cfbc`.

El parsing local ScriptDom terminó correctamente para ambos artefactos (48 lotes y un lote,
respectivamente). Es un gate estático y no sustituye una corrida transaccional en un motor SQL.

`021` prepara configuraciones semánticas versionadas e inmutables salvo desactivación one-way tras
drenar jobs, evaluaciones y reservas activas; corpus revisados con casos
`Development`/`Test`; jobs de embeddings con claim, lease y reintentos acotados; reservas de
presupuesto previas a la llamada; ledger append-only de uso/costo; embeddings nativos
`VECTOR(1536)`; corridas, snapshots de casos, items agregables e idempotencia durable. Los sujetos
son `ProjectId + ProjectVersion` tenant-private y `FundingOpportunityId + FundingContentVersion`
global; no existe `OrganizationProfileEmbedding` en este contrato project-first.

`021` no inventa ni siembra un corpus real etiquetado o una configuración activa. El smoke usa
fixtures que siempre se revierten; no constituyen datos evaluados. La carga futura de un manifiesto
revisado debe ser un cambio controlado, trazable y posterior a aplicar las migraciones pendientes.

La migración crea dos superficies de mínimo privilegio sin vincular principals:

- `FundingPlatform_SemanticWorkerRole`: `EXECUTE` sólo sobre los 11 SP de claim/input/lease/
  complete/fail/wait del worker;
- `FundingPlatform_SemanticAdminRole`: `EXECUTE` sólo sobre backfill y los cuatro SP de
  alta/listado/detalle/reporte administrativos.

Ambos roles tienen `DENY SELECT, INSERT, UPDATE, DELETE` sobre las 11 tablas semánticas. El
despliegue autorizado debe usar principals distintos para worker general y API y, respecto de esta
superficie, asignar sólo el rol semántico correspondiente a cada uno. Esto no elimina otros permisos
mínimos que esos hosts requieran fuera de 9B-A. Se verifican permisos efectivos; ninguna aplicación
recibe `db_owner`, DML directo o ambos roles semánticos.

Este runbook de 9B-A queda supersedido por la migración `027`: no se asignan ya los roles
especialistas directamente. `DatabaseMigrator --provision-runtime-identities` vincula por
`clientId`/SID binario a `H_general` y API únicamente con
`FundingPlatform_GeneralWorkerRole` y `FundingPlatform_ApiRuntimeRole`; esos roles agregados contienen
la superficie especialista exacta y el comando valida idempotencia, SID y ausencia de membresías
adicionales.

El preflight de permisos se ejecuta conectado por separado como cada principal: `USER_NAME()` debe
devolver el user esperado; el worker debe poder ejecutar `FundingPlatform_usp_SemanticEmbeddingJob_Claim` y no
`FundingPlatform_usp_SemanticEvaluationRun_Create`; la API debe mostrar el inverso; ambos deben
obtener `0` al consultar `HAS_PERMS_BY_NAME` para `SELECT` sobre
`FundingPlatform_SemanticEmbeddings`.

El JSON canónico se genera en tiempo de ejecución desde campos allowlisted y está limitado a 8192
bytes UTF-8. Ni ese JSON, ni prompts, respuestas crudas o texto enviado al proveedor se guardan en
las tablas 9B-A. Jobs y embeddings conservan hashes, versiones y configuración efectiva; las guardas
rechazan input inválido, stale o con patrones de email, URL o RUT. La oportunidad usa sólo contenido
editorial público y el proyecto excluye título/nombre, IDs de organización/usuario, notas y billing.
Vectores y resultados de evaluación son inmutables para reproducibilidad; 9B-A no agrega un SP de
purga. Retención/borrado del proveedor real debe diseñarse y aprobarse en 9B-B.

La evaluación es corpus-level y shadow-only. El conjunto exige al menos 30 proyectos, 100
oportunidades y entre 300 y 5000 pares etiquetados `0/1/2`, congelados por proyecto. Compara el orden
semántico por distancia coseno exacta con el orden histórico 9A de cada corrida, respetando sus hard
gates y TOP 200. Persiste métricas agregadas de cobertura, éxito del proveedor, Recall@10, nDCG@10,
baseline/delta, MRR@10, cambio medio de rank, costo incremental, p95 y promociones indebidas de hard
gates. No actualiza `ProjectMatchingRuns`, `ProjectFundingMatches`, score, clasificación,
`IsCurrent`, orden visible ni frontend.

El gate de referencia exige corpus completo, cobertura ≥95%, éxito ≥99%, Recall@10 ≥0,80,
nDCG@10 ≥0,75, delta nDCG ≥0,05 y cero promociones de incompatibles. Una corrida con embeddings
terminalmente ausentes puede cerrar con reporte parcial, pero no es elegible. La configuración fake
local tampoco puede promoverse, independientemente de sus métricas.

El fake léxico determinístico de costo cero se restringe a `Development`/`Testing` y nunca es
promovible. La activación hosted de 9B-A exige el adapter real gobernado de 9B-B; no existe fallback
silencioso al fake.

## Estado de FASE 9B-B

La implementación local agrega dos migraciones forward-only, todavía no aplicadas:

- `022_governed_openai_provider.sql` (788 líneas/9 lotes), SHA-256
  `d961a90278a8081c175418f6331be6dd19b65a0563b75fe6c857417c266f0f56`;
- `022_governed_openai_provider_smoke.sql` (362 líneas/un lote), SHA-256
  `4204196816b74194ee012b63bd3c0a184e7dfa649bcd6b4f82a80d9370ca9b22`;
- `023_shadow_structured_explanations.sql` (2164 líneas/25 lotes), SHA-256
  `add58976e0963dc0cec0b434d18415869eb5f0e96e0bed35264e3363a021eca9`;
- `023_shadow_structured_explanations_smoke.sql` (335 líneas/un lote), SHA-256
  `11d1a4d51008e0d6c6c27ac9265a4078955911506de8f863fcdad0298ca62a3c`.

`022` introduce políticas de proveedor inmutables con identidad/modelo/capability/endpoint exactos,
hashes de DPA y términos, ZDR, residencia, precios, aprobador y expiración. Una configuración real de
embeddings queda enlazada por FK y fingerprint; el GetInput del worker entrega sólo metadatos
allowlisted y nunca una API key. `023` agrega configuraciones y runs de explicación, jobs con lease,
reservas mensuales previas, ledger de costo, resultados estructurados inmutables e idempotencia.

El input no se persiste: SQL lo deriva durante el lease desde un ítem Test/primary congelado de
9B-A y las nueve reglas 9A, aplica el detector de riesgo y guarda únicamente SHA-256. C# vuelve a
validar el JSON exacto antes de la red. La salida se limita a assessment, resumen, una razón estable
y hasta tres códigos de regla; no se guardan prompt, canonical JSON, respuesta raw, API key ni
provider request ID sin hash.

Los roles existentes se amplían sólo con los SP correspondientes: Admin publica políticas/
configuraciones y crea/consulta runs; Worker reclama, lee input efímero, renueva, completa o falla.
Ambos conservan `DENY SELECT, INSERT, UPDATE, DELETE` sobre las tablas nuevas. La API exige
Admin/SuperAdmin con MFA reciente y el runtime queda deshabilitado por defecto.

El gate local pasó ScriptDom para `022`, smoke `022`, `023` y smoke `023`; build .NET con 0
warnings/0 errores; 347/347 pruebas unitarias; 142/142 de integración; lint frontend, 21 archivos/
104 pruebas Vitest y build de producción. Estos gates no abrieron una conexión SQL ni llamaron a
OpenAI. El estado observado de `res` sigue en 18/18: un despliegue futuro debe aplicar
`019`→`020`→`021`→`022`→`023`, ejecutar sus smokes reales y registrar status/reapply.

El adapter soporta `/v1/embeddings` y `/v1/responses` con Structured Outputs y `store=false`, pero
queda apagado hasta aprobar el proyecto exacto para ZDR/DPA, guardar el secreto en Key Vault,
registrar precios actuales y ejecutar evals sobre un corpus real. No se entrenó un modelo ni se usó
Azure ML. La extracción generativa y cualquier writeback/promoción continúan fuera de este cierre.

## Estado de FASE 10A

La implementación local agrega una migración forward-only todavía no aplicada:

- `024_saved_search_alerts.sql` (1264 líneas/19 lotes), SHA-256
  `f6222f40fb6b6ad436e6496d383f4b05900458e4201d9176165dcf9d113e99a4`;
- `024_saved_search_alerts_smoke.sql` (293 líneas/un lote), SHA-256
  `24f5aa7def2ecd6b7bf6f9c5c6843e105f34afca1fad0f69c8e4c5f484d7b035`.

`024` agrega búsquedas privadas por usuario+organización, filtros N:N normalizados, suscripción diaria,
ledger del digest e ítems por oportunidad. La materialización reusa
`FundingPlatform_ifn_FundingOpportunityPublicReady`, replica los predicados 8A y considera sólo
publicaciones nuevas de la ventana. El máximo es 50; si hubo una caída de más de 24 horas se genera
un único digest de recuperación en vez de uno por día perdido.

La entrega usa claim/renew/complete/fail con leases e intentos. Un timeout/ACK incierto termina
`Unknown` y no vuelve a enviarse; un fallo confirmado antes de enviar puede quedar
`RetryScheduled`. SQL no persiste email, body ni bearer de baja. Solo guarda nonce, receipt acotado,
estado y código seguro. `FundingPlatform_AlertWorkerRole` recibe `EXECUTE` en seis SP de scheduler/
delivery y `DENY` de DML directo sobre las tablas principales; la migración no crea el usuario Entra.

ScriptDom parseó los 19 lotes de migración y el lote transaccional del smoke. El gate local pasó
build .NET 0 warnings/0 errores, Unit 360/360, Integration 149/149, lint frontend, 23/108 Vitest y
build. No se abrió una conexión DB/Azure, no se aplicó `024` ni se envió email. El último estado
observado de `res` sigue en 18/18; el despliegue posterior debe validar/aplicar en orden
`019`→`025`, correr todos los smokes con rollback, reapply/status y registrar los resultados reales.

## Estado de FASE 10B

La implementación local agrega dos artefactos forward-only todavía no ejecutados contra una base:

- `025_organization_networking.sql` (717 líneas/11 lotes), SHA-256
  `f0add029613446ad5350b9ddaa8873497e4074a5483b40c6518838941abc24cf`;
- `025_organization_networking_smoke.sql` (273 líneas/dos lotes), SHA-256
  `02485713222d60c4a87b5bc514bd34a1b1f094247625bd75d4c8976335e87af7`.

`025` agrega preferencias opt-in por organización, solicitudes Connect y un ledger de creación
idempotente. El directorio reutiliza las guardas `OrganizationMarketplaceReady` y
`ProjectMarketplaceReady`: no inventa otra publicación ni expone miembros/PII. Visibilidad y
recepción de solicitudes son decisiones separadas; bloqueo excluye el par del directorio.

Los SP vuelven a validar usuario, membresía, tenant y rol administrador en cada mutación. Create
exige hash de clave/request, un proyecto público opcional, snapshots seguros y cuotas durables;
Action exige rowversion y transiciones explícitas. Dos triggers hacen inmutables identidad,
mensaje, snapshots, historial terminal y ledger. El smoke transaccional prepara dos ONG/proyectos
públicos, ejerce opt-in, directorio, create/replay/conflict, accept, list/get, block y privacidad,
y termina con rollback.

El gate local pasó ScriptDom mediante la suite de infraestructura, build .NET 0 warnings/0 errores,
Unit 370/370, Integration 156/156, lint frontend, 25 archivos/111 pruebas Vitest y build. No se
abrió una conexión SQL/Azure ni se ejecutaron `--validate`, `--apply`, `--test` o `--status` para
`025`; `res` continúa observado en 18/18. Un despliegue futuro debe aplicar `019`→`025` en orden,
ejecutar todos los smokes con rollback y registrar status/reapply reales.

## Estado de FASE 11

`026_subscription_billing_sandbox.sql` (988 líneas) y su smoke transaccional (94 líneas) preparan
planes, precios, entitlements, suscripciones, pagos, checkout, inbox de webhooks y reconciliación.
Professional y Organization se publican sin precio y no comprables; Free es el fallback. No se
persisten cuerpos de webhook, tarjetas, tokens ni secretos. La configuración sale apagada y exige
Mercado Pago sandbox para habilitarse.

El gate del cierre local pasó build .NET 0 warnings/errores, Unit 373/373, Integration 156/156,
lint, 25 archivos/111 pruebas frontend y build. El 2026-08-27 `026` quedó validada como parte de
`001`→`028`, pero no aplicada ni ejecutada por `--test`; `res` continúa observado en 18/18.

## Preparación runtime 027 — FASE 12A

`027_runtime_database_roles.sql` (371 líneas/un lote), SHA-256
`ad9212a025cf438fcb65d6dc4463e58dd246cf42868b22862b953af5a57aef2a`, agrega únicamente los roles
host-específicos `FundingPlatform_ApiRuntimeRole` y `FundingPlatform_GeneralWorkerRole`. La API
recibe una allowlist exacta de 116 procedimientos, 18 permisos DML sobre siete tablas de
Identity/MFA y `EXECUTE`/`REFERENCES` sobre cinco TVP; el worker general recibe 49 procedimientos y
cero DML directo. El rol de extracción creado por 016 conserva sus seis procedimientos. No se
crean usuarios Entra ni membresías desde la migración.

`027_runtime_database_roles_smoke.sql` (460 líneas/un lote), SHA-256
`a994e3ac4ff7da2e21cf4180d28d9f7c27a67a2c06dd609db7ce45bf40960856`, crea usuarios temporales
`WITHOUT LOGIN` dentro de una transacción, verifica permisos efectivos y aislamiento entre hosts y
revierte todo. Tras `028`, el mismo smoke congela el contrato acumulado de API en 119 procedimientos
y 147 permisos directos; la migración `027` conserva su allowlist original. ScriptDom parseó ambos
lotes y los tests focales pasaron. El 2026-08-27 `027` quedó validada dentro de la cadena completa,
pero no aplicada ni ejecutada por `--test`; `res` sigue observado en 18/18. La base dev debe aplicar
`001`→`028`, ejecutar los 28 smokes con rollback y aprovisionar fuera del historial sólo los tres
principals runtime autorizados por nombre y `clientId` convertido a SID.

## Cierre administrativo 028 — paneles operativos y resumen del usuario

`028_admin_operations_completion.sql` (346 líneas/cinco lotes), SHA-256
`81691a037d245fda2e5415528a6902ca5dc9d2a731a193b71f00efcca848c8ef`, agrega tres consultas
administrativas de solo lectura: listado y ficha segura de organizaciones, y una bandeja de errores
operacionales sanitizados. Extiende el rol runtime de API únicamente con `EXECUTE` sobre esos tres
procedimientos; el contrato acumulado queda en 119 SP y 147 permisos directos.

`028_admin_operations_completion_smoke.sql` (109 líneas/un lote), SHA-256
`b4c6e82754edf277dacb6cb813a73623f540188c2f6337553ad472602e6f503d`, crea fixtures dentro de una
transacción, ejerce los tres procedimientos con un administrador MFA, verifica los grants y termina
con rollback. La API expone `/api/v1/admin/organizations`, su detalle y
`/api/v1/admin/operational-errors`; no devuelve identificadores tributarios, payloads, stack traces,
tokens ni mensajes crudos de proveedores. El frontend reemplaza además el resumen de usuario por
métricas derivadas de proyectos, postulaciones, calendario y alertas existentes.

ScriptDom T-SQL 170 y los tests focales de arquitectura, HTTP y frontend quedaron verdes. El gate
completo se registra en el log de despliegue. El 2026-08-27 `028` quedó validada dentro de la cadena
completa, pero no aplicada ni ejecutada por `--test`; debe desplegarse sólo después de `027`.

## Carpetas

- Tables: definiciones de tablas, claves, constraints e índices propios del objeto.
- Types: table-valued types y otros tipos SQL justificados.
- StoredProcedures: procedimientos almacenados invocados por Dapper con CommandType.StoredProcedure.
- Views: vistas justificadas por consultas reales.
- Seed: catálogos iniciales y datos de referencia versionados.
- Migrations: historial numerado, inmutable y forward-only aplicado por el migrador.
- Provisioning: objetos no transaccionales, idempotentes y ejecutados solo por el comando explícito
  correspondiente del migrador.

## Reglas para FASE 2

- La base `res` es compartida: todo objeto propiedad de la aplicación comienza con `FundingPlatform_` y el migrador no toca objetos ajenos o sin ese prefijo.
- La convención incluye tablas, vistas, tipos, funciones, triggers y procedimientos (`FundingPlatform_usp_*`), además de nombres explícitos de claves e índices (`FundingPlatform_PK_*`, `FundingPlatform_FK_*`, `FundingPlatform_CK_*`, `FundingPlatform_UQ_*`, `FundingPlatform_IX_*`).
- La API no ejecuta migraciones al arrancar.
- El migrador registra cada script aplicado en `FundingPlatform_SchemaVersions`.
- Una migración publicada no se edita; las correcciones se agregan en una migración posterior.
- Dinero usa DECIMAL, fechas técnicas DATETIME2 y texto Unicode NVARCHAR.
- No se guardan listas separadas por comas.
- Toda FK, índice y TVP debe responder a una relación o consulta real.
- Los procedimientos viven fuera de Controllers y se invocan explícitamente como stored procedures.
- Los tests de integración usan SQL Server/Azure SQL real, no SQLite.
- Ningún script contiene credenciales, connection strings ni nombres secretos de infraestructura.

Los archivos `.gitkeep` conservan carpetas reservadas que todavía no tienen artefactos separados.

## Alcance del baseline 001

La primera migración mantiene un núcleo sencillo: catálogos y seed Chile, identidad
base, organizaciones/perfiles, oportunidades/fuentes canónicas, entitlements Free y
outbox. FASE 6 ya incorporó evidence editorial y el límite seguro de documentos en Blob.
FASE 7A incorporó contenido bruto de Grants.gov y runs de importación. FASE 7B incorporó extracción
PDF, recepción Defender/Event Grid fail-closed, RSS gobernado y deduplicación humana. FASE 8A
incorporó búsqueda/detalle organizacional, favoritos privados y Full-Text con fallback literal.
FASE 8B prepara en código local marketplace de proyectos, postulaciones privadas y calendario
derivado; su migración `019` sigue pendiente de aplicación autorizada. FASE 9A incorporó en código
local la compatibilidad determinística project-first y su migración `020`, con gate local cerrado pero
aplicación DB pendiente. FASE 9B-A prepara embeddings project-first y su evaluación corpus-level sólo
en sombra mediante `021`, también sin aplicar. FASE 9B-B prepara adapters externos gobernados y
explicaciones administrativas shadow mediante `022`/`023`, igualmente apagados y sin aplicar;
FASE 10A prepara búsquedas guardadas y alertas diarias mediante `024`, apagadas y sin aplicar;
FASE 10B prepara networking opt-in moderado mediante `025`, también sin aplicar. Extracción
generativa, promoción y billing conservan fases o gates posteriores. Las sesiones
y MFA se incorporaron de forma aditiva en FASE 3 mediante
las migraciones 002/003/004.

La revisión funcional del 17 de agosto mantiene el baseline 001 inmutable y reordena las próximas
migraciones: primero proyectos; después funders/oportunidades; luego runs, raw, evidence y matching
por `ProjectVersion + OrganizationProfileVersion`. `FundingSource` seguirá representando el origen
técnico del dato y no la entidad financiadora. Véase
[REVISION-VISION-FUNDRAISING-GLOBAL.md](../docs/REVISION-VISION-FUNDRAISING-GLOBAL.md).

## Backup y rollback operativo

Antes de cada lote de FASE 2:

1. verificar que la conexión corresponde a `res` y que las migrations pendientes solo administran objetos `FundingPlatform_`;
2. confirmar con el propietario de Azure SQL que los backups automáticos/PITR están activos y registrar la ventana recuperable vigente;
3. registrar hora UTC, versión de aplicación y última versión de `FundingPlatform_SchemaVersions`;
4. ejecutar primero el chequeo de conexión y detener el despliegue ante cualquier discrepancia.

El rollback de esquema es forward-only. Una migration usa transacción cuando las operaciones lo permiten; si falla antes del commit, se revierte esa transacción. Si ya fue confirmada, el archivo permanece inmutable y la corrección se entrega como una migration numerada posterior. No se usan scripts `down` sobre `res`.

Para recuperar datos, PITR se restaura en una base temporal distinta y se valida allí. Desde esa copia solo se preparan reparaciones para datos u objetos `FundingPlatform_`; no se sobrescribe automáticamente la base compartida ni se modifican objetos de terceros. Una restauración completa de `res` o un cambio de destino requiere un cambio coordinado y aprobado por el propietario de la base y todos sus consumidores. El redespliegue de una versión anterior de la aplicación solo es válido si su contrato continúa siendo compatible con el esquema actual.
