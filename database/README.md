# Base de datos

Esta carpeta contiene los artefactos SQL versionados de FundingPlatform. El baseline
ejecutable de **FASE 2** fue validado y aplicado contra Azure SQL real.

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
operador crea el usuario de la UAMI `C` exacta del consumidor extractor y la agrega al rol:

~~~sql
CREATE USER [<nombre-identidad>] FROM EXTERNAL PROVIDER
    WITH OBJECT_ID = '<object-id-identidad>';
ALTER ROLE [FundingPlatform_ExtractionWorkerRole]
    ADD MEMBER [<nombre-identidad>];
~~~

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
derivado; su migración `019` sigue pendiente de aplicación autorizada. Proyectos/funders se agregaron
en FASE 5/6, matching project-first en FASE 9; billing y alertas conservan sus fases. Las sesiones y
MFA se incorporaron de forma aditiva en FASE 3 mediante las migraciones 002/003/004.

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
