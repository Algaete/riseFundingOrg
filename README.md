# FundingPlatform

FundingPlatform es una plataforma SaaS para que ONG estructuren proyectos, descubran financiamiento,
encuentren partners y prioricen oportunidades mediante matching explicable. El producto parte en
Chile y español, con diseño para Latinoamérica, internacionalización e inteligencia de fundraising.

## Estado del proyecto

El repositorio completó la **implementación local de FASE 10A** sobre el catálogo 8A: búsquedas
guardadas privadas, resumen diario por email, baja con token de un solo propósito e historial de
notificaciones. El runtime de alertas permanece apagado por defecto; no se envió correo ni se creó
un recurso Azure. La compatibilidad 9A y la experimentación 9B continúan separadas y sin alterar el
contenido ni la selección de las alertas.

Las migraciones `019` a `024`, junto con sus smokes, permanecen como artefactos locales: por
instrucción del propietario **no se aplicaron ni validaron contra Azure SQL ni contra otro entorno de
base de datos**. El último estado observado de `res` continúa siendo 18/18, correspondiente a 8A.

| Fase | Estado | Resultado esperado |
|---|---|---|
| 0 | Completada | Diseño técnico, alcance MVP/V2, modelo lógico, API, riesgos y roadmap |
| 1 | Completada | Solución compilable, frontend base, configuración y documentación |
| 2 | Completada | Baseline 001 aplicado a `res`: migrador forward-only, esquema, seed, 41 tablas de negocio, 4 TVP y 8 SP |
| 3 | Completada | Registro/login, verificación y reset por email, JWT, refresh rotativo, MFA, Data Protection y bootstrap SuperAdmin |
| 4 | Completada | Organización, membresía, catálogos, onboarding, perfil N:N, versionado, completitud y ETag |
| 5 | Completada | SSO Entra opt-in, proyectos versionados, publicación moderada, auditoría/outbox y perfil público seguro |
| 6 | Completada | Funders, oportunidades, workflow editorial, correcciones y carga documental segura |
| 7A | Completada | Grants.gov durable, runs/raw, outbox/Queue, Functions y consola administrativa sin autopublicación |
| 7B | Completada | Extracción PDF aislada, recepción Defender/Event Grid fail-closed, RSS gobernado, retención y deduplicación humana |
| 8A | Completada | Catálogo organizacional protegido, búsqueda, filtros, órdenes, paginación, detalle completo y favoritos privados |
| 8B | Código completado; activación DB pendiente | Marketplace público, postulaciones privadas y calendario básico derivados del proyecto/fondo |
| 9A | Código completado; activación DB pendiente | Compatibilidad determinística y explicable por proyecto, historial e idempotencia |
| 9B-A | Código completado; activación DB pendiente | Embeddings versionados, presupuesto y evaluación semántica corpus-level sólo en sombra |
| 9B-B | Código gobernado completado; activación y eval real pendientes | Adapters OpenAI apagados por defecto, DPA/ZDR/precios versionados y explicaciones admin sólo en sombra |
| 10A | Código completado; activación DB/email pendiente | Búsquedas guardadas privadas, digest diario idempotente, baja segura e historial |
| 10B | Pendiente | Networking básico y solicitudes Connect moderadas |
| 11 | Pendiente | Suscripciones, billing sandbox y administración completa |
| 12 | Pendiente | Hardening, pruebas, observabilidad y despliegue del piloto |

El diseño base está en [docs/FASE-0-DISENO-TECNICO.md](docs/FASE-0-DISENO-TECNICO.md) y
la ampliación project-first está en
[docs/REVISION-VISION-FUNDRAISING-GLOBAL.md](docs/REVISION-VISION-FUNDRAISING-GLOBAL.md).
Las migraciones `001` a `018` están aplicadas en `res`. El gate SQL definitivo de 8A confirmó
18/18 migraciones, 18/18 smokes con rollback, 1267 objetos propios, una segunda aplicación con
0 migraciones/0 lotes y el Full-Text de 8A listo después de dos provisiones idempotentes. Las `019`
de 8B, `020` de 9A, `021` de 9B-A, `022`/`023` de 9B-B y `024` de 10A no forman parte de ese resultado: permanecen
como artefactos locales pendientes de un despliegue posterior autorizado y deben aplicarse en ese
orden. El código
del receptor Defender/Event Grid está listo, pero esa integración y
la fuente RSS permanecen deshabilitadas en producción hasta que el operador configure los recursos,
permisos y políticas aprobadas. Este cierre no activó servicios pagados ni ejecutó un E2E real de
Defender.

## Stack objetivo

- Backend: .NET 10 LTS, ASP.NET Core Web API, C#, Dapper, Microsoft.Data.SqlClient, FluentValidation, Serilog y OpenAPI.
- Workers: Azure Functions v4 isolated sobre .NET 10.
- Datos: Azure SQL o SQL Server 2025, con procedimientos almacenados cuando aporten valor.
- Frontend: React, TypeScript, Vite, React Router, TanStack Query, React Hook Form, Zod, Tailwind CSS y shadcn/ui.
- Infraestructura: Azure App Service, Static Web Apps, Functions, Queue Storage, Blob Storage, Key Vault y Application Insights.
- Integraciones previstas: OpenAI, proveedor de email y Mercado Pago detrás de abstracciones reemplazables.

## Prerrequisitos

Para trabajar con toda la solución se requiere:

- Git.
- SDK .NET 10. La versión preferida está fijada por global.json.
- Node.js 22.12+ o 24+, y npm 10+; este workspace fue validado con Node 24 y npm 11.
- Azure Functions Core Tools v4 para ejecutar el worker localmente. En macOS se puede instalar con `brew tap azure/functions` y `brew install azure-functions-core-tools@4`.
- Acceso a Azure SQL o SQL Server 2025 para validar migraciones y pruebas SQL reales.
- Azurite para Blob y Queue en desarrollo local de los workers.
- Opcionalmente Azure CLI y una suscripción Azure para staging/deploy.

SQL Server no se ejecutará bajo emulación ARM64 como baseline del proyecto. En un Mac ARM64 se usará Azure SQL de desarrollo, una instancia SQL remota x86-64 o el entorno de integración de CI.

## SDK .NET: instalación local o global

### Opción A — SDK local al repositorio

La carpeta .dotnet está ignorada por Git. Instala allí el canal 10.0 con el instalador oficial:

~~~bash
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --channel 10.0 --install-dir "$PWD/.dotnet"
export DOTNET_ROOT="$PWD/.dotnet"
export PATH="$DOTNET_ROOT:$PATH"
./.dotnet/dotnet --version
~~~

Los comandos de este README muestran la forma local. Si el ejecutable global satisface global.json, se puede sustituir ./.dotnet/dotnet por dotnet.

### Opción B — SDK global

Instala .NET 10 desde la distribución oficial de Microsoft para tu sistema y verifica:

~~~bash
dotnet --list-sdks
dotnet --version
~~~

Si global.json solicita una versión que no está instalada, .NET informará la versión requerida. No se debe modificar global.json solo para ocultar una instalación incompleta.

## Configuración local

1. Crea el archivo local:

~~~bash
cp .env.example .env
~~~

2. Sustituye los placeholders únicamente en `.env` y completa las variables necesarias para la fase que ejecutarás.
3. Nunca añadas `.env`, credenciales, tokens, connection strings con contraseña o certificados al repositorio.

El loader admite `.env` únicamente para bootstrap local: lo carga si ninguna de las señales externas `ASPNETCORE_ENVIRONMENT`, `DOTNET_ENVIRONMENT` y `AZURE_FUNCTIONS_ENVIRONMENT` está definida, o si todas las que están definidas valen `Development`. Esto permite que el propio `.env` local declare el entorno. Si alguna señal vale `Production`, `Staging`, `Testing` o cualquier otro valor, el archivo se omite. No hace falta ejecutar `source .env` y las variables ya definidas en el proceso prevalecen.

`.env` está ignorado y no se incluye en artefactos publicados. Staging y producción fijan explícitamente el entorno antes del arranque y usan App Settings, referencias de Key Vault y Managed Identity; nunca dependen del bootstrap local.

Las variables `VITE_` son públicas porque Vite las incorpora al bundle del navegador; nunca deben contener secretos.

Variables agrupadas:

- Entorno: ASPNETCORE_ENVIRONMENT, DOTNET_ENVIRONMENT y AZURE_FUNCTIONS_ENVIRONMENT.
- SQL: AZURE_SQL_CONNECTION_STRING y la conexión opcional AZURE_SQL_LOG_CONNECTION_STRING.
- Acceso interno: INTERNAL_API_KEY es una clave local que debe generarse fuera del repositorio; el valor de `.env.example` es solo un marcador.
- Alias opcional: API_FOOTBALL_KEY se admite como nombre de configuración, pero actualmente FundingPlatform no consume API-Football.
- Sesión: JWT_SECRET, JWT_ISSUER, JWT_AUDIENCE y peppers de seguridad. En este entorno los valores secretos se obtienen de Key Vault; los aliases locales son solo fallback.
- SSO: ENTRA_SSO_ENABLED, ENTRA_SSO_TENANT_ID y ENTRA_SSO_CLIENT_ID identifican la aplicación Web local. El secreto se guarda preferentemente en Key Vault como `Authentication--External--Entra--ClientSecret`, nunca en Git ni en React.
- IA generativa futura: OPENAI_API_KEY, OPENAI_MODEL y OPENAI_EMBEDDING_MODEL permanecen sin uso en
  9B-A; no se requiere una API key para ejecutar el fake local.
- Semántica 9B-A: SEMANTIC_ENABLED, SEMANTIC_SHADOW_ONLY, SEMANTIC_DIMENSIONS,
  SEMANTIC_BATCH_SIZE, SEMANTIC_LEASE_SECONDS y SEMANTIC_TIMEOUT_SECONDS. Los ejemplos fijan
  `SEMANTIC_ENABLED=false`, `SEMANTIC_SHADOW_ONLY=true` y 1536 dimensiones. Fuera de
  `Development`/`Testing`, la API fuerza su policy a deshabilitada y el worker rechaza al arranque
  una configuración habilitada porque todavía no existe un proveedor hosted aprobado.
- Storage/workers: `FundingPlatform.Workers` usa su conexión `AzureWebJobsStorage` para host y cola
  `imports` de FASE 7A. `FundingPlatform.ExtractionWorkers` usa una conexión
  `AzureWebJobsStorage` propia para su host, con otro `clientId`. Ambos se comunican por la cola de datos
  `document-extractions`, configurada mediante `DocumentExtractionQueueStorage`. En Azure, el host
  storage del extractor sí debe ser distinto de la cola de extracción y de Blob documental. La cola
  y los containers documentales son scopes lógicos separados, pero pueden residir en una misma GPv2
  si RBAC se asigna a la cola/container exactos. Las familias identity-based
  admiten `accountName` o URI y `credential=managedidentity`. Las cuatro UAMI y su asignación exacta
  se detallan en el runbook de FASE 7B. Para documentos
  se usan AZURE_STORAGE_BLOB_SERVICE_URI,
  SOURCE_DOCUMENT_INCOMING_CONTAINER,
  SOURCE_DOCUMENT_QUARANTINE_CONTAINER, SOURCE_DOCUMENT_TRUSTED_CONTAINER,
  SOURCE_DOCUMENT_MAX_BYTES, SOURCE_DOCUMENT_UPLOAD_TTL_MINUTES,
  SOURCE_DOCUMENT_FINALIZE_LEASE_SECONDS, SOURCE_DOCUMENT_SCAN_TIMEOUT_SECONDS,
  SOURCE_DOCUMENT_SCAN_MODE y SOURCE_DOCUMENT_DEVELOPMENT_FAKE_RESULT. La API accede a Blob
  mediante Entra/Managed Identity y no necesita una account key.
- Extracción/retención: DOCUMENT_EXTRACTION_MAX_BYTES, DOCUMENT_EXTRACTION_MAX_PAGES,
  DOCUMENT_EXTRACTION_MAX_CHARACTERS, DOCUMENT_EXTRACTION_MAX_UTF8_BYTES,
  DOCUMENT_EXTRACTION_MAX_STACK_DEPTH, DOCUMENT_EXTRACTION_TIMEOUT_SECONDS,
  DOCUMENT_EXTRACTION_LEASE_SECONDS, DOCUMENT_EXTRACTION_WATCHDOG_BATCH_SIZE,
  CONTENT_RETENTION_BATCH_SIZE, CONTENT_RETENTION_SOURCE_DOCUMENT_BATCH_SIZE y
  CONTENT_RETENTION_SOURCE_DOCUMENT_LEASE_SECONDS.
- Defender/RSS: las familias DEFENDER_EVENT_GRID_*, DEFENDER_PENDING_SCAN_TIMEOUT_MINUTES,
  DEFENDER_WATCHDOG_BATCH_SIZE y OFFICIAL_RSS_* son fail-closed. Los ejemplos dejan
  DEFENDER_EVENT_GRID_ENABLED y OFFICIAL_RSS_ENABLED en `false`.
- Correo: AZURE_COMMUNICATION_SERVICES_ENDPOINT y EMAIL_FROM_ADDRESS. La autenticación local usa Azure CLI, no una access key del proveedor.
- Billing: PAYMENT_PROVIDER, MERCADO_PAGO_ACCESS_TOKEN y MERCADO_PAGO_WEBHOOK_SECRET.
- Web: BACKEND_API_BASE_URL, FRONTEND_BASE_URL, ALLOWED_CORS_ORIGINS, VITE_API_BASE_URL y
  VITE_EXTERNAL_AUTH_BASE_URL. Esta última apunta directamente a la API para que las cookies OIDC
  de correlación no atraviesen el proxy de desarrollo.
- Seguridad Azure/telemetría: AZURE_KEY_VAULT_URI, las URI de Data Protection, KEY_VAULT_URI como alias y APPLICATIONINSIGHTS_CONNECTION_STRING.

`BACKEND_API_BASE_URL` se mapea a `BackendApi:BaseUrl` para clientes internos; no cambia por sí sola la dirección donde escucha Kestrel. `VITE_API_BASE_URL` es la URL pública que consume el navegador e incluye el prefijo `/api/v1`. Para escuchar en otro origen se usa `--urls` o `ASPNETCORE_URLS` explícitamente. `VITE_EXTERNAL_AUTH_BASE_URL` también incluye `/api/v1`, pero debe ser absoluta y usar el mismo esquema, host y puerto configurados en las redirect URIs Web de Entra.

## Instalación

Desde la raíz:

~~~bash
./.dotnet/dotnet restore FundingPlatform.sln
./.dotnet/dotnet build FundingPlatform.sln --no-restore
~~~

Para instalar el frontend:

~~~bash
cd frontend/funding-platform-web
npm ci
~~~

Usa npm install solamente cuando corresponda crear o actualizar deliberadamente el lockfile.

## Backend

Ejecuta la API, que en desarrollo escucha en `http://localhost:5070`:

~~~bash
./.dotnet/dotnet run --project src/FundingPlatform.Api/FundingPlatform.Api.csproj --urls http://localhost:5070
~~~

Si `5070` ya está ocupado por otra aplicación, usa por ejemplo `5080`:

~~~bash
./.dotnet/dotnet run --project src/FundingPlatform.Api/FundingPlatform.Api.csproj --urls http://localhost:5080
~~~

Para ejecutar importaciones y extracción documental, usa tres terminales y mantenlas abiertas.
`local.settings.json` es local y está ignorado por Git.

Terminal 1 — Azurite:

~~~bash
npx azurite --silent --location .azurite
~~~

Terminal 2 — Azure Functions:

~~~bash
cd src/FundingPlatform.Workers
# Solo la primera vez; conserva luego tu archivo local.
cp local.settings.example.json local.settings.json
func start --port 7071
~~~

Terminal 3 — extractor PDF aislado:

~~~bash
cd src/FundingPlatform.ExtractionWorkers
# Solo la primera vez; este proyecto conserva su propio archivo local.
cp local.settings.example.json local.settings.json
func start --port 7072
~~~

Si Homebrew no agregó Core Tools al `PATH`, usa directamente el ejecutable de la versión instalada que muestre `brew list azure-functions-core-tools@4`.

En Development los workers crean en Azurite las colas requeridas si aún no existen. En Azure se
provisionan por infraestructura; el extractor falla al arrancar si su host storage coincide con la
cola de extracción o con Blob documental. Cola y Blob pueden compartir GPv2 con RBAC de recurso
exacto. Cada Function App usa un `AzureWebJobsStorage__clientId` distinto; esto no exige una cuenta
por identidad ni cuatro cuentas Storage. No se usan account keys. El host general conserva importaciones 7A,
outbox, adquisición, recepción Defender y retención. El host aislado consume únicamente
`document-extractions` y ejecuta su watchdog. API y frontend se inician con los comandos de sus
secciones respectivas.

## Frontend

~~~bash
cd frontend/funding-platform-web
npm run dev
~~~

La URL local normalmente será `http://localhost:5173`. El navegador usa `/api/v1` y
Vite envía `/api` a `http://localhost:5070` para mantener un mismo origen. Si la API
escucha en otro puerto, inicia Vite así:

~~~bash
FUNDING_PLATFORM_API_PROXY_TARGET=http://localhost:5080 npm run dev
~~~

Los access tokens viven solo en memoria; el refresh token permanece en una cookie
`HttpOnly`, `Secure` y host-only. No se guardan tokens en localStorage. El access token dura 15
minutos y se renueva mediante una familia refresh rotativa de 30 días. Para Admin/SuperAdmin, la
comprobación MFA permanece vigente durante 60 minutos; la renovación conserva la hora original del
MFA y nunca prolonga artificialmente esa ventana.

## Autenticación local (FASE 3)

Antes de iniciar la API, autentica la identidad local y confirma la suscripción:

~~~bash
az login
az account show
~~~

La configuración de desarrollo usa recursos de alcance reducido:

- secretos criptográficos en `fpong-kv-dev`;
- key ring de Data Protection en el blob `dataprotection/keys.xml`, cifrado con la clave `data-protection` de Key Vault;
- Azure Communication Services `fpong-comms-dev-1234` y su remitente de dominio administrado;
- Azure SQL `res` mediante Microsoft Entra ID.

La identidad local tiene `Key Vault Secrets Officer` únicamente sobre `fpong-kv-dev`
y `Storage Blob Data Contributor` únicamente sobre el container `dataprotection`.
Esos permisos son para desarrollo. Al desplegar, se asignarán a la Managed Identity
de cada servicio con el mínimo alcance necesario; no se reutilizará la sesión de Azure CLI.

La carga documental administrativa usa los containers privados `fp-source-incoming`,
`fp-source-quarantine` y `fp-source-trusted`. Para probarla con la identidad local se
requieren `Storage Blob Delegator` sobre la cuenta `fpongdev1234` y
`Storage Blob Data Contributor` sobre cada uno de esos tres containers. No se usa la
account key. Estos roles todavía deben asignarse explícitamente a la identidad que ejecuta
la API; en producción pertenecen a su Managed Identity. Una regla Lifecycle elimina blobs
abandonados bajo `fp-source-incoming/uploads/` después de un día; soft delete conserva la
recuperación durante siete días.

Los nombres de secretos esperados en Key Vault son
`Authentication--Jwt--SigningKey`,
`Authentication--SecurityHash--IpHashPepper` y
`Authentication--SecurityHash--RecoveryCodePepper`. Sus valores nunca deben copiarse
a documentación, logs, Git ni al navegador.

El primer SuperAdmin se crea una sola vez mediante la consola administrativa. La
contraseña se solicita dos veces sin eco y no se acepta como argumento ni por pipe:

~~~bash
./.dotnet/dotnet run --project tools/FundingPlatform.AdminCli/FundingPlatform.AdminCli.csproj -- \
  bootstrap-superadmin --email admin@example.org --display-name "Administrador"
~~~

Sustituye el correo y el nombre por valores reales. El primer login queda limitado a
configurar MFA antes de habilitar operaciones administrativas. No se ha creado ningún
SuperAdmin automáticamente.

## Importación durable de oportunidades — FASE 7A

El primer corte durable usa exclusivamente la API pública oficial de Grants.gov. No es un crawler
universal. El adaptador vive en Infrastructure, la orquestación en Application y los timers/colas en
Functions. Cada ejecución conserva primero el run, las observaciones raw inmutables, sus hashes y
los snapshots normalizados; después prepara los borradores editoriales. Los items y errores permiten
reanudar trabajo parcial. Lease renovable, retry acotado, poison handling, watchdog y outbox cierran
las ventanas de fallo sin convertir Queue Storage en la fuente de verdad.

Con API, Azurite, worker y frontend activos, una persona Admin/SuperAdmin con MFA reciente abre:

- `http://localhost:5173/admin/imports` para crear y seguir ejecuciones;
- `http://localhost:5173/admin/sources` para ver el estado operativo de las fuentes;
- `http://localhost:5173/admin/funding` para revisar, corregir y publicar candidatos.

El formulario acepta una palabra clave de 2–100 caracteres y hasta 25 resultados. El endpoint crea
`ImportRun + OutboxMessage` y responde `202`; el navegador consulta el estado sin recibir raw JSON ni
datos internos. Los candidatos quedan `Draft`/`StagedForReview`: una importación nunca publica. Solo
aparecen en `/funding` después de revisión humana y aprobación Admin/SuperAdmin con MFA reciente.
No existe un comando directo de importación: toda ejecución usa el mismo flujo durable y auditable.

## Documentos y fuentes gobernadas — FASE 7B

Un documento solo puede solicitar extracción cuando el scan vigente es `Clean` y el blob exacto ya
está en el container confiable. El receptor HTTP de Event Grid valida el token Entra y la política
exacta de tenant, aplicación, principal, topic, suscripción y cuenta; después vuelve a comprobar
ETag, SHA-256 y el recibo de Defender. Cualquier resultado inválido, desconocido, tardío o no
verificable bloquea el documento. El watchdog cierra scans abandonados de forma segura.

`FundingPlatform.ExtractionWorkers` solo lee el container confiable y procesa PDF con límites de
tamaño, páginas, caracteres, bytes UTF-8 y profundidad. El parser solicita cancelación a los 120
segundos y el host tiene un límite exterior de 5 minutos. Esto separa proceso y permisos, pero no es
una sandbox de sistema operativo ni garantiza preempción dura dentro del parser. El resultado
expone métricas/evidencia sanitizada, nunca el contenido bruto, hash o ruta privada. Esta fase no
llama a IA ni interpreta campos; ese enriquecimiento permanece en FASE 9B-B. La evaluación de
embeddings de 9B-A no consume el texto PDF extraído ni modifica contenido editorial.

La retención redacta en SQL el raw, items, resultados y evidencia al vencer la política. Para blobs,
el worker solicita borrado sobre el nombre y ETag exactos e itera snapshots y versiones. La
indisponibilidad lógica es inmediata cuando se confirma la solicitud; con soft delete de siete días,
los bytes aún son recuperables durante esa ventana y la purga física final queda a cargo de la
expiración/lifecycle de Storage.

La fuente `official-rss` es un único feed HTTPS fijo, no un crawler. Valida endpoint y hosts exactos,
licencia, `robots.txt` en modo `enforce`, rate limit, tamaño y retención antes de cada solicitud. Se
rechazan redirects, DTD y destinos DNS privados, loopback, link-local o metadata. Se
mantiene deshabilitada hasta que un SuperAdmin configure una política inmutable en una terminal
interactiva y su preflight coincida exactamente con `OFFICIAL_RSS_*`:

~~~bash
./.dotnet/dotnet run --project tools/FundingPlatform.AdminCli/FundingPlatform.AdminCli.csproj -- \
  configure-funding-source-policy \
  --superadmin-user-id '<guid>' --provider-code official-rss \
  --base-url '<feed-https-exacto>' --license-name '<nombre>' --license-url '<url-https>' \
  --license-reviewed-at-utc '<utc>' --robots-url '<url-https-exacta>' \
  --robots-policy enforce --robots-policy-version '<n>' \
  --robots-reviewed-at-utc '<utc>' --robots-expires-at-utc '<utc>' \
  --allowed-hosts '<hosts-separados-por-coma>' --rate-per-minute '<n>' \
  --maximum-response-bytes '<n>' --retention-days '<n>' --idempotency-key '<clave>' \
  --enabled --compliance-approved
~~~

El comando exige TTY y una confirmación escrita; no almacena credenciales ni inicia una descarga.
En `/admin/imports/:id`, el revisor compara candidatos y decide conservar separados, confirmar el
duplicado o ignorar la sugerencia. Las tres decisiones conservan auditoría, ETag e idempotencia y el
candidato sigue sin publicarse.

### Activación Azure pendiente

El código no habilita ni factura Defender/Event Grid por sí solo. Antes de producción, un operador
debe crear/configurar esos recursos, registrar la política exacta con
`configure-defender-event-grid-trust`, asignar RBAC mínimo y ejecutar un E2E real limpio/malicioso.
Hasta entonces `DEFENDER_EVENT_GRID_ENABLED=false`, el scan productivo falla cerrado y no existe un
botón de reintento que simule Defender.

El despliegue usa cuatro UAMI distintas; una identidad adjunta a un Function App no se adjunta al
otro:

| Alias | Function App | Configuración/alcance |
|---|---|---|
| `H_general` | solo `FundingPlatform.Workers` | `AzureWebJobsStorage__clientId` de esa app; host, `imports` y data planes generales autorizados |
| `S` | solo `FundingPlatform.Workers` | `DocumentExtractionQueueStorage__senderClientId`; solo `Storage Queue Data Message Sender` sobre `document-extractions` |
| `H_extractor` | solo `FundingPlatform.ExtractionWorkers` | `AzureWebJobsStorage__clientId` de esa app; solo host storage |
| `C` | solo `FundingPlatform.ExtractionWorkers` | `DocumentExtractionQueueStorage__clientId`; reader/processor de la cola, reader de Blob confiable y rol SQL de extracción |

Los cuatro client IDs son distintos, incluido `H_general != H_extractor`. Los settings de `S` y `C`
pueden estar declarados en ambos hosts para validar la topología, pero solo se adjuntan y usan según
la tabla. La separación de identidades no implica cuatro cuentas: la cola y Blob pueden compartir
una GPv2 con RBAC sobre la cola/container exactos; el host storage del extractor no puede compartir
esa cuenta de datos.

La UAMI `C` debe coincidir en `DocumentExtractionQueueStorage__clientId`, el credential de lectura
del container confiable y `User Id=<client-id-C>` de la conexión SqlClient con
`Authentication=Active Directory Managed Identity`. El `object-id` usado para crear su principal SQL
no es el `client-id`:

~~~sql
CREATE USER [<nombre-identidad>] FROM EXTERNAL PROVIDER
    WITH OBJECT_ID = '<object-id-identidad>';
ALTER ROLE [FundingPlatform_ExtractionWorkerRole]
    ADD MEMBER [<nombre-identidad>];
~~~

`FundingPlatform_ExtractionWorkerRole` solo puede ejecutar seis SP de extracción: claim, renovación
de lease, registro de evidencia, complete, fail y requeue del watchdog. Conectado como esa identidad,
el preflight esperado es `1/0/0`:

~~~sql
SELECT USER_NAME() AS DatabaseUser;
SELECT HAS_PERMS_BY_NAME(
    'dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim', 'OBJECT', 'EXECUTE') AS AllowedClaim;
SELECT HAS_PERMS_BY_NAME(
    'dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart', 'OBJECT', 'EXECUTE') AS DeniedAdmin;
SELECT HAS_PERMS_BY_NAME(
    'dbo.FundingPlatform_SourceDocuments', 'OBJECT', 'SELECT') AS DeniedTableRead;
~~~

Sobre la cola de datos, `S` solo envía; `C` recibe `Storage Queue Data Reader` y
`Storage Queue Data Message Processor`. Sobre Blob, `C` solo recibe `Storage Blob Data Reader` en el
container confiable. Los permisos de host storage de `H_general` y `H_extractor` se asignan por
separado, según la
[configuración identity-based oficial de Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/manage-connections?pivots=functions-auth-identity&tabs=bindings#define-connections).
`H_general` recibe `Storage Blob Data Contributor` únicamente en los containers que necesita
para promoción, revocación y retención (`quarantine`/`trusted`); ese permiso no se hereda al
extractor ni a `H_extractor`/`C`.

## Catálogo organizacional de fondos — FASE 8A

Dentro del espacio de una organización, `/opportunities` muestra concursos publicados con filtros
y paginación server-side, `/opportunities/:slug` muestra el detalle completo y `/favorites` reúne
los favoritos del usuario actual. El catálogo público `/funding` no cambió.

La API incorporó exactamente estas rutas protegidas:

- `GET /api/v1/organizations/{organizationId}/funding-opportunities`;
- `GET /api/v1/organizations/{organizationId}/funding-opportunities/{idOrSlug}`;
- `GET /api/v1/organizations/{organizationId}/favorites`;
- `PUT /api/v1/organizations/{organizationId}/favorites/{fundingOpportunityId}`;
- `DELETE /api/v1/organizations/{organizationId}/favorites/{fundingOpportunityId}`.

Todas exigen sesión completa y membresía activa, usan `Cache-Control: no-store` y tienen límites de
tasa. Una organización ajena responde `404` sin confirmar su existencia; el detalle y el alta de un
favorito también usan `404` si la oportunidad no está disponible. La eliminación es idempotente y
responde `204` para una membresía válida aunque el favorito ya no exista. Los favoritos se
identifican por organización, usuario y oportunidad, por lo que no se comparten entre miembros.
Solo se proyectan oportunidades publicadas, activas y aptas para catálogo; no aparecen borradores ni
contenido bloqueado por procedencia o catálogos inactivos.

La búsqueda acepta texto, patrocinador, moneda/rango de monto, rango de cierre, solo abiertas y
listas de país, región, categoría, tag, beneficiario, tipo de proyecto, tipo de financiamiento, tipo
de organización admitido y funder. Los órdenes permitidos son `relevance`, `closing-soon`, `newest`,
`amount-asc` y `amount-desc`; relevancia exige texto y ordenar/filtrar por monto exige una moneda para
no comparar divisas distintas. La respuesta conserva página, tamaño, total y modo de búsqueda.

El texto combina el ranking de Full-Text con coincidencias literales determinísticas. Si Full-Text
no está disponible o aún no fue provisionado, el catálogo continúa mediante `literal-fallback`.
Como deuda P2, incluso el modo híbrido calcula el complemento literal sobre las seis columnas para
no perder coincidencias; eso mantiene corrección y un fallback reproducible, pero conserva costo de
scan. Antes de crecer al volumen objetivo se deben revisar planes/Query Store y acotar ese complemento
si la medición lo exige. No se presenta ningún filtro como confirmación de elegibilidad y 8A no usa
perfil, proyecto, score, IA ni embeddings para ordenar resultados.

La migración transaccional `018_funding_search_and_favorites.sql` crea el estado y los procedimientos
de búsqueda/detalle/favoritos. El catálogo e índice Full-Text se crean aparte porque SQL Server no
permite `CREATE FULLTEXT INDEX` dentro de la transacción del migrador:

~~~bash
./.dotnet/dotnet run --project tools/FundingPlatform.DatabaseMigrator/FundingPlatform.DatabaseMigrator.csproj -- --provision-full-text
~~~

`--apply` no ejecuta ese provisioning y `--validate` solo descubre/valida su manifiesto sin mutarlo.
El comando explícito verifica primero la migración `018` y su checksum, toma un application lock de
sesión y es idempotente. `--status` informa por separado si Full-Text está listo, poblando, no
provisionado, no disponible o en drift; en los dos estados de ausencia la búsqueda literal sigue
operativa.

## Marketplace de proyectos y actividad — FASE 8B

El marketplace anónimo usa las rutas frontend canónicas `/marketplace`,
`/marketplace/projects/:slug` y `/marketplace/organizations/:organizationId`. La ruta histórica
`/projects/public/:slug` se conserva como alias compatible. La navegación pública se apoya en:

- `GET /api/v1/marketplace/catalogs`;
- `GET /api/v1/marketplace/projects`;
- `GET /api/v1/marketplace/projects/{slug}`;
- `GET /api/v1/marketplace/organizations/{organizationId}`;
- `GET /api/v1/projects/{slug}`, conservado como alias del detalle público.

La búsqueda admite `q`, listas de país/categoría/tipo de proyecto, estado, moneda, orden y
paginación server-side. Los órdenes permitidos son `newest`, `title` y `funding-gap-desc`; este
último exige una moneda única para no comparar CLP, USD y EUR como si fueran equivalentes. Solo
proyecta proyectos activos y publicados de organizaciones activas con perfil público apto. Los
detalles y perfiles usan una proyección allowlisted sin miembros, correos, teléfonos, identificadores
tributarios ni borradores. Las respuestas públicas tienen cache de 60 segundos y rate limit; la
interfaz aclara que FundingPlatform no realiza una verificación legal de la organización.

El espacio autenticado incorpora `/applications` y `/calendar`, respaldados por estas rutas privadas:

- `GET/POST /api/v1/organizations/{organizationId}/applications`;
- `GET/PATCH /api/v1/organizations/{organizationId}/applications/{applicationId}`;
- `GET /api/v1/organizations/{organizationId}/calendar?from=YYYY-MM-DD&to=YYYY-MM-DD`.

Cada postulación enlaza obligatoriamente una organización, uno de sus proyectos y un fondo publicado.
Sus estados son `Interesado`, `Preparando postulación`, `Presentada`, `Adjudicada`, `No adjudicada`
y `Descartada`. Crear exige `Idempotency-Key` durable; reintentar la misma solicitud no duplica el
registro y reutilizar la clave con otros datos produce conflicto. Actualizar exige el ETag vigente en
`If-Match`. Todos los miembros activos pueden consultar; solo el responsable de la postulación o un
Admin de la organización puede editar. El aislamiento entre tenants responde `404` sin revelar si un
recurso ajeno existe, y estas rutas usan sesión completa, `Cache-Control: no-store` y rate limits.

El calendario no duplica datos en una tabla propia: deriva, para intervalos de hasta 366 días, los
cierres de fondos vinculados, fechas planificadas de envío y resultado, inicio/término del proyecto y
cierres de favoritos todavía no representados por una postulación activa. Las postulaciones
descartadas se excluyen. 8B no agregó matching, score, recomendaciones, IA, alertas, networking ni
billing; la compatibilidad determinística posterior corresponde a 9A.

`019_project_marketplace_applications_calendar.sql` y
`019_project_marketplace_applications_calendar_smoke.sql` están preparados como artefactos
forward-only. En este cierre no se ejecutaron `--validate`, `--apply`, `--test` ni `--status` contra
Azure SQL o cualquier otro entorno de base de datos; por ello no se declara una versión aplicada,
un inventario de objetos ni un smoke SQL real de 8B. Sus huellas locales congeladas son:

- migración `019` (1184 líneas/15 lotes):
  `eeb6962329261b6736b4e3584d1409e622f1a26a2947bbe3b3ae25a660df53ef`;
- smoke `019` (860 líneas/dos lotes):
  `7feccc8bb44f63f776df0b16f313ac9e06c8a421d51904764fe24d1da9732ab9`.

El parsing local ScriptDom terminó correctamente y pasaron 4/4 pruebas de arquitectura 8B. Estos
gates son estáticos y no equivalen a ejecutar SQL contra una base real.

## Compatibilidad determinística por proyecto — FASE 9A

La vista autenticada `/matching` permite elegir un proyecto, iniciar un cálculo, revisar su resumen
y abrir ejecuciones históricas. `/recommended` se conserva como alias hacia la misma experiencia.
La API privada, siempre bajo sesión completa, aislamiento tenant mediante `404`, `no-store` y rate
limit, expone:

- `POST /api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs`;
- `GET /api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs`;
- `GET /api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs/{matchingRunId}`.

El `POST` es síncrono, exige `Idempotency-Key` de 16–128 caracteres y materializa como máximo 200
oportunidades abiertas en un orden determinístico. La respuesta distingue una ejecución nueva de un
replay seguro. El
historial conserva las versiones de proyecto, perfil institucional, contenido de cada fondo, motor,
perfil de matching y conjunto de reglas; `isCurrent` permite advertir cuando el resultado ya no
representa el estado vigente. También informa el total del catálogo evaluable, el instante de su
snapshot y si el TOP 200 truncó candidatos.

El perfil `v1` suma 100% mediante nueve reglas: geografía (20%), tipo de organización (15%), figura
jurídica (15%), años de operación (10%), experiencia previa (10%), áreas temáticas (10%),
beneficiarios (5%), tipo de proyecto (5%) y monto (10%). Las cinco primeras son condiciones
excluyentes y cada una queda en `Pass`, `Fail` o `Unknown`. Un `Fail` clasifica el fondo como
`Incompatible` y deja el score en “No aplica”; sin fallos, un hard gate `Unknown` produce `Datos
insuficientes`, y solo todos los hard gates en `Pass` permiten mostrar `Compatible`.

Cada regla conserva resultado, estado del dato, peso, puntos, razón, parámetros y evidencia
allowlisted. `Unknown` aporta cero puntos y reduce la cobertura; los pesos conocidos nunca se
renormalizan. La interfaz muestra score y cobertura por separado, advertencias y versiones, junto
con el aviso permanente de que el resultado es orientativo. Esta fase no llama a OpenAI, no genera
embeddings, no hace ranking semántico y no afirma recomendación ni elegibilidad.

`020_deterministic_project_matching.sql` y su smoke están preparados localmente. En este corte no se
ejecutaron `--validate`, `--apply`, `--test` ni `--status` contra SQL Server/Azure SQL; tampoco se
declara una versión `020` aplicada, un nuevo inventario de objetos ni un smoke SQL real. La
activación exige primero aplicar `019` y luego `020` mediante un despliegue explícito y autorizado.

Sus huellas locales congeladas son:

- migración `020` (1718 líneas/16 lotes):
  `984450d06cb17447be8b3af595caa6415ce9e59f2b5e4d53bc3466ce2b25921e`;
- smoke `020` (924 líneas/un lote):
  `a827cc9234831c757583b2e6776c13d2550985dcce566653dc171616f3e036f6`.

El parsing estático T-SQL 170 y la inspección AST terminaron limpios. Estas comprobaciones locales no
equivalen a ejecutar la migración o el smoke contra un motor SQL.

## Evaluación semántica en sombra — FASE 9B-A

9B-A agrega el camino durable para comparar una señal de embeddings con el orden determinístico de
9A antes de exponerla. Es una evaluación interna **corpus-level**, no un cálculo solicitado por una
ONG ni una nueva pantalla. Una persona Admin/SuperAdmin con MFA reciente puede crear, listar y
consultar corridas mediante:

- `POST /api/v1/admin/semantic-evaluation-runs`, con `Idempotency-Key` y las versiones exactas del
  corpus y de la configuración semántica;
- `GET /api/v1/admin/semantic-evaluation-runs`;
- `GET /api/v1/admin/semantic-evaluation-runs/{runId}`;
- `GET /api/v1/admin/semantic-evaluation-runs/{runId}/report`.

El corpus es inmutable y revisado por una persona: exige al menos 30 proyectos, 100 oportunidades y
entre 300 y 5000 pares etiquetados `0/1/2`, con splits `Development` y `Test` congelados por proyecto.
Este repositorio define el contrato y fixtures transaccionales de smoke, pero no inventa ni siembra
un corpus real etiquetado o una configuración activa; esos datos requieren revisión y una carga
controlada posterior.
El TOP 200 se interpreta por cada corrida histórica 9A subyacente; no se mezcla todo el corpus en un
ranking global. El reporte agregado mide cobertura, éxito del proveedor, Recall@10, nDCG@10 frente
al baseline 9A, delta nDCG, MRR@10, cambio medio de rank, costo incremental, p95 y promociones de
hard gates. El gate de referencia exige cobertura ≥95%, éxito ≥99%, Recall@10 ≥0,80, nDCG@10
≥0,75, delta ≥0,05 y cero promociones de incompatibles; además requiere el corpus completo. Un
resultado parcial se informa como tal y nunca es elegible, y el fake local nunca puede promoverse.

Los sujetos son la versión exacta del proyecto, privada para su tenant, y la versión exacta del
contenido editorial público de la oportunidad. No se genera un embedding del perfil institucional.
Las entradas se construyen en servidor con allowlists y JSON canónico de hasta 8192 bytes UTF-8; el
proyecto excluye título/nombre, identificadores de organización o usuario, URLs, RUT, emails, notas y
billing. SQL persiste hashes, coordenadas versionadas y `VECTOR(1536)`, pero no el JSON canónico,
prompts, respuestas crudas ni texto enviado al proveedor. Los vectores y resultados shadow son
inmutables para reproducibilidad; 9B-A no incorpora una purga. La retención/borrado exigida por un
proveedor real es un gate explícito de 9B-B.

El worker usa claims y leases renovables, hasta tres intentos, reservas de presupuesto previas a
cualquier llamada y un ledger de uso/costo. En `Development`/`Testing` el adapter
`development-deterministic`/`lexical-hash-1536-v1` genera vectores reproducibles con costo cero y sin
red. La configuración queda deshabilitada por defecto y fail-closed en ambientes hosted: 9B-A no
incluye un adapter OpenAI real, no activa recursos Azure y no incurre en costo de proveedor.

`021` crea `FundingPlatform_SemanticWorkerRole` y `FundingPlatform_SemanticAdminRole`, pero no crea
usuarios ni agrega principals. En un despliegue autorizado se reutilizan los principals distintos
del worker general y de la API; respecto de la superficie semántica, el primero recibe sólo los 11 SP
de procesamiento y el segundo sólo los cinco SP de backfill, alta, listado, detalle y reporte. Esto
no reemplaza otros permisos mínimos que cada host ya requiera fuera de 9B-A. Ambos roles niegan
`SELECT/INSERT/UPDATE/DELETE` directo sobre las tablas semánticas. Ninguna identidad de aplicación
debe ser `db_owner` ni compartir ambos roles semánticos por conveniencia.

La migración forward-only `021_shadow_semantic_evaluation.sql` y su smoke están preparados sólo
localmente. No se ejecutaron `--validate`, `--apply`, `--test` ni `--status` contra SQL Server/Azure
SQL; por ello no se declara `021` aplicada ni un smoke SQL exitoso. Su activación futura exige aplicar
primero `019`, después `020` y finalmente `021`, mediante un cambio explícito y autorizado.

Huellas de los artefactos locales congelados:

- migración `021` (3995 líneas/48 lotes):
  `f6a7cc2a7faba60edce4611c58f56850cf6fd1000b50d7a2f55a53ab188737c3`;
- smoke `021` (1710 líneas/un lote):
  `64ad6a521c0eaa6bbb3674b8b0966e572731110eafef57c84b87726baa94cfbc`.

El parsing local ScriptDom terminó correctamente para los 48 lotes de la migración y el lote del
smoke. Es una comprobación estática; no equivale a ejecutar ninguno de los archivos en SQL Server.

## Proveedor gobernado y explicaciones en sombra — FASE 9B-B

La implementación local añade un adapter HTTP real para `/v1/embeddings` y otro para
`/v1/responses` con Structured Outputs estricto. Ambos quedan apagados por defecto. El worker sólo
puede iniciarlos cuando coinciden exactamente proveedor, modelo, endpoint oficial, capability,
fingerprint de la política activa, precio, vigencia y contrato ZDR. No hay fallback silencioso al
fake: éste continúa restringido a `Development`/`Testing` y jamás es promovible.

Las migraciones `022` y `023` modelan políticas inmutables de DPA/términos, residencia, retención,
precios y expiración; configuraciones versionadas; reservas de presupuesto antes de llamar; leases,
reintentos y cobro conservador cuando el ACK es incierto; y resultados de explicación separados e
inmutables. SQL no persiste API keys, prompts, JSON canónico ni respuestas crudas. El input de
explicación se deriva de snapshots 9A/9B-A, tiene máximo 8192 bytes UTF-8 y C#/SQL lo validan contra
campos, rangos, reglas y reason codes allowlisted. La salida admite sólo cuatro razones, hasta tres
reglas citadas y un resumen de 300 caracteres sin email, URL o RUT.

La única superficie HTTP nueva es administrativa con MFA reciente y `no-store`:

- `POST /api/v1/admin/semantic-explanation-runs`, con `Idempotency-Key`;
- `GET /api/v1/admin/semantic-explanation-runs/{runId}`.

Es un experimento **shadow-only**: no modifica `ProjectMatchingRuns`, `ProjectFundingMatches`,
`SemanticEvaluationItems`, score, hard gates, clasificación, `IsCurrent`, orden visible ni frontend.
No recomienda fondos y no confirma elegibilidad. Las políticas y configuraciones se publican por el
Admin CLI interactivo; no existe endpoint para que un cliente elija proveedor/modelo o suba prompts.

Después de aplicar las migraciones en un entorno autorizado, el operador consulta las opciones
exactas sin exponer secretos con:

~~~bash
./.dotnet/dotnet run --project tools/FundingPlatform.AdminCli --
~~~

La secuencia es `register-openai-embedding-policy`,
`publish-openai-semantic-configuration`, `register-openai-structured-output-policy` y
`publish-openai-explanation-configuration`. Cada comando exige terminal interactivo, SuperAdmin,
MFA en SQL, hashes de documentos aprobados e idempotencia; ninguno recibe ni imprime la API key.

Artefactos locales congelados:

- migración `022` (788 líneas/9 lotes), SHA-256
  `d961a90278a8081c175418f6331be6dd19b65a0563b75fe6c857417c266f0f56`;
- smoke `022` (362 líneas/un lote), SHA-256
  `4204196816b74194ee012b63bd3c0a184e7dfa649bcd6b4f82a80d9370ca9b22`;
- migración `023` (2164 líneas/25 lotes), SHA-256
  `add58976e0963dc0cec0b434d18415869eb5f0e96e0bed35264e3363a021eca9`;
- smoke `023` (335 líneas/un lote), SHA-256
  `11d1a4d51008e0d6c6c27ac9265a4078955911506de8f863fcdad0298ca62a3c`.

ScriptDom parseó los cuatro artefactos. El gate local pasó build .NET con 0 warnings/0 errores,
347/347 pruebas unitarias, 142/142 de integración, lint frontend, 21 archivos/104 pruebas Vitest y
build de producción. Aun así, `019`–`023` no se aplicaron ni ejecutaron en SQL Server/Azure SQL y no
hubo llamadas de proveedor.

Para activar 9B-B todavía hace falta aplicar `019`→`023` en un entorno autorizado, aprobar y cargar
un corpus real, contratar/confirmar ZDR y DPA para el proyecto exacto, registrar precios vigentes,
guardar la API key en Key Vault, ejecutar evals con presupuesto acotado y decidir go/no-go. La
extracción generativa de documentos y cualquier promoción de la señal semántica siguen diferidas;
ninguna se habilita por esta implementación. No se contempla entrenar un modelo propio ni usar
Azure ML para el MVP.

## Búsquedas guardadas y alertas diarias — FASE 10A

La SPA permite guardar desde `/opportunities` los filtros privados del usuario, abrirlos de nuevo,
eliminarlos, activar o desactivar un digest diario y consultar el historial en `/alerts`. La alerta
vuelve a evaluar en SQL la misma semántica literal/filtros de 8A sobre `PublicReady`; el navegador no
envía una lista de fondos y el correo nunca afirma elegibilidad.

La API usa sesión completa, `no-store`, aislamiento por usuario+organización, `Idempotency-Key` para
crear y ETag/`If-Match` para modificar/eliminar. La baja pública usa
`POST /api/v1/alerts/unsubscribe` y responde `204` de forma no enumerativa. El bearer firmado contiene
sólo IDs/nonce, se valida con HMAC-SHA256 y no se persiste; la clave de 32 bytes queda exclusivamente
en Key Vault/App Settings. Abrir el enlace sólo muestra una confirmación: la SPA no ejecuta la baja
automáticamente, para que un escáner de correo no la active por visitar la URL. El bearer viaja en
el fragmento `#token`, que el navegador no envía al hosting como parte del request HTTP.

El Functions general ejecuta scheduler cada cinco minutos y delivery cada minuto. SQL materializa
como máximo 50 novedades por digest, colapsa caídas superiores a 24 horas en un solo resumen de
recuperación y usa leases, intentos e idempotencia por alerta+ventana. Un resultado incierto del
proveedor queda `Unknown` y no se reenvía a ciegas; solo un fallo confirmado pre-envío puede
reintentarse. No se guardan dirección de email, body HTML/texto ni token de baja en el ledger.

Artefactos locales congelados:

- migración `024_saved_search_alerts.sql` (1264 líneas/19 lotes), SHA-256
  `f6222f40fb6b6ad436e6496d383f4b05900458e4201d9176165dcf9d113e99a4`;
- smoke `024_saved_search_alerts_smoke.sql` (293 líneas/un lote), SHA-256
  `24f5aa7def2ecd6b7bf6f9c5c6843e105f34afca1fad0f69c8e4c5f484d7b035`.

ScriptDom parseó ambos artefactos. El gate local pasó build .NET con 0 warnings/0 errores,
360/360 pruebas unitarias, 149/149 de integración, lint frontend, 23 archivos/108 pruebas Vitest y
build de producción. No se abrió una conexión DB/Azure; `res` permanece observado en 18/18 y la
activación futura debe aplicar `019`→`024` en orden y ejecutar todos los smokes.

`ALERTS_ENABLED=false` es el valor inicial. Para habilitarlo se requiere `024` aplicada, un usuario
Entra del worker miembro de `FundingPlatform_AlertWorkerRole`, permiso Communication Email Sender,
endpoint/from address verificados, URL frontend HTTPS y la clave de baja en Key Vault. 10A no agrega
recordatorios de postulaciones ni networking; el calendario/pipeline ya pertenecen a 8B y Connect
queda para 10B.

## Pruebas y validación

Backend:

~~~bash
./.dotnet/dotnet test FundingPlatform.sln
~~~

Frontend:

~~~bash
cd frontend/funding-platform-web
npm test
npm run build
~~~

Gate mínimo después de cada fase:

- compila backend y worker;
- ejecuta pruebas aplicables;
- ejecuta tests y build del frontend;
- mantiene OpenAPI, README y .env.example sincronizados;
- no deja secretos, TODO ni NotImplementedException pertenecientes a la fase cerrada.

Las pruebas SQL usan SQL Server/Azure SQL real, no SQLite, porque stored procedures, Full Text, locking y VECTOR no son equivalentes.

## Swagger, OpenAPI y salud

En Development, inicia la API en `http://localhost:5070` y usa:

- `http://localhost:5070/swagger` para Swagger UI;
- `http://localhost:5070/swagger/v1/swagger.json` para el contrato OpenAPI;
- `http://localhost:5070/health` para liveness;
- `http://localhost:5070/health/ready` para readiness.

Swagger estará deshabilitado o protegido en producción. Los errores HTTP usarán ProblemDetails e incluirán un traceId, sin stack traces ni datos sensibles.

## Base de datos

La estructura database/ contiene el baseline SQL de FASE 2 y las migraciones aditivas
de las fases posteriores:

- Tables: definiciones de tablas;
- Types: table-valued types y tipos propios;
- StoredProcedures: procedimientos de acceso y operaciones complejas;
- Views: vistas justificadas por consultas reales;
- Seed: catálogos y datos iniciales versionados;
- Migrations: historial inmutable y forward-only;
- Provisioning: objetos que SQL Server exige crear fuera de la transacción de migraciones.

La **FASE 2** quedó cerrada con `001_initial_schema.sql` aplicada a `res` y registrada
con SHA-256 `a6fe03d9ae312ee907ab63500be1c5dd7a8158327ed4a3ae5d97e163ad39884c`.
`--status` confirmó 1/1 aplicada: 41 tablas de negocio más
`FundingPlatform_SchemaVersions`, 4 TVP y 8 procedimientos almacenados. Una segunda
ejecución de `--apply` resultó 0 aplicadas / 0 pendientes. La API nunca migra la base
automáticamente al arrancar. Consulta [database/README.md](database/README.md) y el
[registro de despliegue](database/DEPLOYMENT-LOG.md).

FASE 3 agregó y aplicó `002_identity_security.sql`,
`003_superadmin_bootstrap.sql` y `004_security_token_reissue_cooldown.sql`.
Incorporan tokens opacos hasheados, refresh families
rotativas con detección de replay, challenges y recovery codes MFA, eventos de
autenticación, el bootstrap único del SuperAdmin y un cooldown que conserva el enlace
vigente frente a envíos repetidos. Los smoke tests SQL de las cuatro migraciones se
ejecutan dentro de transacciones y siempre revierten sus fixtures.

FASE 5 agregó y aplicó `006_entra_sso.sql`, `007_projects_core.sql`,
`008_project_publication_workflow.sql` y `009_entra_link_outcomes.sql`. Las dos primeras incorporan identidades externas y el
agregado Project con snapshots y relaciones normalizadas. `008` completa el workflow
`Draft → PendingReview → Published/Rejected → Archived`, auditoría append-only, outbox
idempotente, revisión Admin/SuperAdmin con MFA y proyección pública sin PII. `009` distingue
una vinculación Microsoft nueva de una identidad que ya estaba vinculada al mismo usuario.
`--status` confirmó 9/9 migraciones aplicadas y la suite SQL ejecutó 9/9 scripts con rollback.

FASE 6 agregó y aplicó `010_funders_editorial_workflow.sql` y
`011_source_document_upload.sql`. `010` incorpora funders canónicos, aliases, oportunidades
versionadas, evidence, staging de fuentes externas, workflow editorial, correcciones
`Published → Draft`, outbox y proyecciones públicas fail-closed. `011` incorpora intents de
carga, documentos en cuarentena y eventos de scan, sin guardar SAS ni tokens recuperables.
`--validate` ejecutó 2 migraciones/44 lotes con rollback; `--status` confirmó 11/11 y 831
objetos propios; 11/11 smokes SQL pasaron y la segunda aplicación ejecutó 0 lotes.

La migración operativa `012_superadmin_role_grant.sql`, aplicada después del cierre funcional
de FASE 6, agrega comandos locales auditados para listar administradores con correo enmascarado
y otorgar `SuperAdmin` a una cuenta existente, activa y confirmada. El grant es transaccional,
revoca sesiones refresh y no habilita MFA artificialmente; el siguiente acceso exige setup o challenge.
El cierre de esa etapa fue 12/12 migraciones, 12/12 smokes y 833 objetos propios.

FASE 7A agregó `013_source_link_identity_alignment.sql`, `014_durable_acquisition.sql` y
`015_import_run_correlation_format.sql`. `013` alinea la identidad externa histórica con la clave
canónica editable. `014` incorpora gobierno y scheduling de fuentes, runs, raw inmutable, snapshots
normalizados rehidratables, items/errores, leases, idempotencia manual, scheduler, outbox y watchdog.
El smoke real posterior a `014` reveló un defecto en el patrón SQL para correlation IDs con guion;
`015` lo corrigió forward-only sin modificar el archivo aplicado.

Hashes de cierre:

- migración `014`: `1d744783127a8107d22c6218b12c7be74161464dd034fca94d4a3a2822500b6e`;
- smoke `014`: `beead55a6d68222d2d75b8b5744cd15e1dcdbf457f61d2648d5c56bbe40196f5`;
- migración `015`: `ee0a75641df9de32210ff54979b06c5a10542ffca1cc07fd8437eed34471f88c`;
- smoke `015`: `b6598cc6df6d667d17b257d20f5cac1572ad958dbd506bc4dbd4dcb5e8913fa8`.

El 2026-08-22, `--validate` de `015` pasó una migración/dos lotes con rollback; `--apply`
aplicó una/dos; `--test` pasó 15 scripts/15 lotes con rollback; una segunda aplicación devolvió
0/0 y `--status` confirmó 15 locales/15 aplicadas en `res`, con 940 objetos propios.

FASE 7B agregó y aplicó `016_governed_document_extraction.sql`. Incorpora políticas inmutables de
adquisición, confianza mínima para Event Grid/Defender, extracción documental acotada, decisiones
humanas de duplicados, retención/redacción y el rol SQL mínimo
`FundingPlatform_ExtractionWorkerRole`. SHA-256 de migración:
`96d435dcee7f898a44b59f918c61e52717211476c365231f6f3518288430ec52`; SHA-256 vigente del smoke
tras la corrección exclusiva del fixture durante 8A:
`4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c`.

El 2026-08-22, `--validate` ejecutó 1 migración/74 lotes y revirtió todo; `--apply` aplicó 1/74;
`--test` pasó 16 scripts/16 lotes con rollback; la segunda aplicación devolvió 0/0 y `--status`
confirmó 16 migraciones locales/16 aplicadas y 1227 objetos propios. Los fixtures históricos
ajustados para el contrato vigente tienen estos hashes: smoke `010`
`8e602c3cef17d13959478a6bc425cb6e9bc1d238a5262682c3911cf928378d23`, smoke `011`
`f7c0b320a1f7276e284425f8c17c9efd357056d2ca15acb9b1daa8d62b1e183b` y smoke `014` indicado
arriba; ninguna migración aplicada se reescribió.

`017_primary_funder_identity_hardening.sql` quedó aplicada como corrección forward-only tras auditar
016, que permanece inmutable. Elimina la inferencia insegura de identidad por nombre normalizado:
reutilizar un funder exige una URL HTTPS canónica fuerte y exactamente coincidente. Colisiones, URL
inválida/no coincidente o funder inactivo quedan en un ledger de revisión y bloquean catálogo y
publicación mientras sigan abiertas; no se elimina un vínculo histórico incierto ni se reemplaza un
primary curado.

SHA-256 de `017`:
`214848f1384ba2f6b428fd550e363c538aee509284de49bd2c8feb1a744382ad`; SHA-256 de su smoke:
`b38a14a457e197efdd1b283613622bc61a370855898d539793714478bcb27862`. El 2026-08-22,
`--validate` pasó 1 migración/13 lotes con rollback; `--apply` aplicó 1/13; `--test` pasó 17/17 con
rollback; una segunda aplicación devolvió 0/0 y `--status` confirmó 17 locales/17 aplicadas y 1251
objetos propios.

FASE 8A agregó y aplicó `018_funding_search_and_favorites.sql`, junto con el provisioning
no transaccional e idempotente `001_funding_opportunity_full_text.sql`. La migración incorpora el TVP
de UUID, favoritos privados, guardas compartidas de publicación, filtros/órdenes/paginación y
procedimientos de catálogo/detalle; el provisioning crea un catálogo dedicado y el índice sobre
`Title`, `Description`, `Summary`, `SponsorName`, `EligibilityDescription` y `Requirements`.

- SHA-256 de `018` (947 líneas/10 lotes):
  `4b1fd2c54220a5209e39a3ed78c890220617707325e4ffdf236a54f4809492c4`;
- SHA-256 del smoke `018` (575 líneas/un lote):
  `ad078055fff7bfc41b03a3bfa56ecc3e198d9c9688940213b71016fa36b76caa`;
- SHA-256 del provisioning (176 líneas/tres lotes):
  `4dad7d2263baa0b55c65ea8e5925a4194a0e5cd6de854f3d85742a542cc4b2c5`.

El cierre observado el 2026-08-22 pasó `--validate` de `018` (una migración/10 lotes y rollback),
`--apply` (una/10), 18/18 smokes con rollback antes y después de provisionar, segunda aplicación
0/0 y `--status` final con 18 migraciones locales/18 aplicadas, 1267 objetos propios y Full-Text
listo. La provisión se ejecutó dos veces (un script/tres lotes en cada caso): la primera informó
inicialmente `poblando` y el `--status` posterior confirmó `listo`; la segunda confirmó directamente
el estado listo.
El primer gate completo detectó únicamente un reloj futuro en el fixture histórico `016`; se cambió
a la hora UTC del propio fixture, su hash final es
`4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c` y la migración `016`
permaneció inmutable.

El gate de código de 8A terminó con build de la solución .NET en 0 warnings/0 errores, 242/242
pruebas unitarias y 101/101 de integración. En frontend pasaron lint, 16 archivos/91 pruebas Vitest
y el build de producción.

El gate local de código de 8B terminó con build de la solución .NET en 0 warnings/0 errores,
261/261 pruebas unitarias y 114/114 de integración. En frontend pasaron lint, 19 archivos/98 pruebas
Vitest y el build de producción. Estos resultados validan código y contratos locales; no sustituyen
la validación transaccional ni el smoke de `019` en SQL Server/Azure SQL, que siguen pendientes.

El gate local de código de 9A terminó con build de la solución .NET en 0 warnings/0 errores,
281/281 pruebas unitarias y 123/123 de integración. En frontend pasaron lint, 21 archivos/104 pruebas
Vitest y el build de producción; el foco archived/matching pasó además 2 archivos/6 pruebas. Estos
resultados y los gates estáticos de `020` no sustituyen la ejecución pendiente de `019`/`020` y sus
smokes en SQL Server/Azure SQL.

El gate local de código de 9B-A terminó con build de la solución .NET en 0 warnings/0 errores,
324/324 pruebas unitarias y 136/136 de integración. La regresión frontend, aunque 9B-A no modificó
su producto, pasó lint, 21 archivos/104 pruebas Vitest y el build de producción. Estos resultados y
el parsing estático de `021`/smoke no sustituyen su ejecución pendiente en SQL Server/Azure SQL y no
incluyeron una llamada a OpenAI o a otro proveedor externo.

Endpoints principales del backend hasta este cierre:

- tenant: `POST /api/v1/organizations/{organizationId}/projects/{projectId}/publish` y
  `/archive`, con `If-Match` e `Idempotency-Key`;
- admin MFA: cola, detalle completo y decisión bajo `/api/v1/admin/projects`;
- público anónimo: `GET /api/v1/projects/{slug}`, limitado a proyectos publicados y
  organizaciones activas con perfil apto;
- marketplace público: catálogos, búsqueda paginada y detalle bajo `/api/v1/marketplace`, además
  del perfil seguro de organización; frontend canónico `/marketplace`,
  `/marketplace/projects/:slug` y `/marketplace/organizations/:organizationId`;
- frontend público heredado: `/projects/public/{slug}`;
- actividad privada: listado/alta/detalle/actualización bajo
  `/api/v1/organizations/{organizationId}/applications` y calendario derivado bajo
  `/api/v1/organizations/{organizationId}/calendar`;
- compatibilidad privada: alta idempotente, historial paginado y detalle explicable bajo
  `/api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs`;
- evaluación semántica shadow Admin/SuperAdmin con MFA: alta idempotente, listado, detalle y reporte
  agregado bajo `/api/v1/admin/semantic-evaluation-runs`, sin exponer entradas canónicas ni vectores;
- importación Admin/SuperAdmin con MFA: `POST /api/v1/admin/funding-sources/{sourceId}/import-runs`,
  `GET /api/v1/admin/import-runs` y
  `GET /api/v1/admin/import-runs/{runId}`;
- catálogo organizacional: `GET /api/v1/organizations/{organizationId}/funding-opportunities` y
  `GET /api/v1/organizations/{organizationId}/funding-opportunities/{idOrSlug}`;
- favoritos privados: `GET /api/v1/organizations/{organizationId}/favorites` y `PUT`/`DELETE`
  sobre `/api/v1/organizations/{organizationId}/favorites/{fundingOpportunityId}`;
- búsquedas/alertas privadas: `GET/POST /api/v1/organizations/{organizationId}/saved-searches`,
  `GET/PATCH/DELETE /saved-searches/{id}`, `PUT/DELETE /saved-searches/{id}/alert` y
  `GET /notification-logs`; la baja pública es `POST /api/v1/alerts/unsubscribe`.

FASE 6 incorporó CRUD y revisión de funders/oportunidades, ETag, idempotencia, auditoría,
correcciones versionadas, atribución, interstitial anti-phishing y el límite seguro de carga
documental. Sus endpoints de upload permiten crear un intent, hacer un `PUT` directo con SAS
HTTPS create-only, completar/verificar, consultar y reintentar scan. FASE 7B agregó extracción PDF
para blobs limpios/confiables, recepción autenticada y gobernanza de fuentes sin cambiar la regla:
nunca se publica automáticamente. En desarrollo el escáner es un fake visible; producción permanece
deshabilitada y fail-closed hasta que el operador conecte Defender/Event Grid y valide su E2E. El
gate histórico de FASE 6 pasó con 171/171
pruebas .NET, 48/48 de frontend, build/lint limpios y 12/12 smokes SQL.

### Microsoft Entra SSO local (opcional)

1. En Microsoft Entra ID crea un **App registration** con el tipo de cuenta
   **Accounts in any organizational directory and personal Microsoft accounts**
   (`AzureADandPersonalMicrosoftAccount`). Los usuarios públicos no se agregan como invitados a tu tenant.
2. En Authentication agrega la plataforma **Web** y la URI exacta
   `http://localhost:5070/api/v1/auth/external/entra/callback`. El registro de desarrollo actual
   admite además `http://localhost:5080/api/v1/auth/external/entra/callback`, porque ese es el puerto
   alternativo usado cuando 5070 está ocupado. Usa otro puerto solo si también cambias la URL local
   de la API y agregas su URI exacta al registro.
3. No habilites implicit grant. Este backend usa authorization code flow con PKCE.
4. Configura `ENTRA_SSO_TENANT_ID="common"` y copia el Client ID a tu `.env`; guarda el client secret en Key Vault con el nombre
   `Authentication--External--Entra--ClientSecret`.
5. Cuando el secreto exista, fija `ENTRA_SSO_ENABLED="true"`, reinicia API y frontend y verifica
   `GET /api/v1/auth/external/providers`. La respuesta debe mostrar `entra` habilitado.

El callback nunca envía access/refresh tokens propios en la URL: entrega un código opaco de un solo
uso y la SPA lo canjea. Un correo ya registrado no se vincula automáticamente; el usuario debe iniciar
sesión primero y usar **Mi cuenta → Vincular Microsoft**.

La cuenta propia de FundingPlatform se identifica por el `issuer` y `subject` validados de Microsoft;
el correo es un dato de contacto y no una clave de vinculación. Una cuenta Microsoft nueva crea su
usuario local automáticamente. Una dirección Gmail funciona en este botón solo si fue registrada como
cuenta Microsoft; Google OAuth sería un proveedor separado.

### Conexión Azure SQL local

El ejemplo conecta mediante Microsoft Entra ID a la base compartida `res` con `Authentication=Active Directory Default`; no contiene usuario, contraseña ni otro secreto. Antes de conectarte localmente, autentica Azure CLI y comprueba la cuenta activa:

~~~bash
az login
az account show
~~~

La identidad debe tener acceso concedido a `res` y la red local debe estar autorizada por el firewall de Azure SQL. En Azure no se usa una sesión de CLI: App Service, Functions y herramientas desplegadas autentican con Managed Identity y permisos mínimos sobre la base.

El chequeo no destructivo de conectividad se ejecuta con:

~~~bash
./.dotnet/dotnet run --project tools/FundingPlatform.DatabaseMigrator/FundingPlatform.DatabaseMigrator.csproj -- --check-connection
~~~

`--check-connection` ejecuta únicamente `SELECT 1`; no crea ni modifica objetos.

La base `res` es compartida. Por tanto, cada tabla, tipo, vista, procedimiento almacenado y objeto de control de migraciones propiedad de esta aplicación debe comenzar obligatoriamente con `FundingPlatform_`. Las migraciones no crean otra base, no renombran objetos ajenos y no operan sobre objetos sin ese prefijo.

### Backup y rollback de FASE 2

Antes de aplicar un lote, el responsable verifica que la conexión apunta a `res`, revisa la lista de migrations pendientes y confirma que Azure SQL conserva backups automáticos/PITR con una ventana recuperable suficiente. El registro del despliegue conserva hora UTC, versión de aplicación, última fila de `FundingPlatform_SchemaVersions` y estado de esa cobertura. El lote se detiene si cualquiera de estas comprobaciones falla.

Las migrations son forward-only. Un script transaccional que falla antes del commit revierte su propia transacción; después de confirmar una migration no se ejecutan scripts `down` ni se editan archivos publicados. Se crea una migration posterior para corregir esquema o datos. La aplicación anterior solo puede redesplegarse si sigue siendo compatible con el esquema vigente.

Como `res` es compartida, una recuperación PITR se restaura primero en una base temporal separada. Allí se valida el punto recuperado y se extraen solo objetos o datos `FundingPlatform_` para preparar una reparación forward-only. Nunca se reemplaza automáticamente `res` ni se restauran objetos de otros productos; una restauración completa requiere aprobación y coordinación del propietario de la base con todos sus consumidores.

El baseline de FASE 2 es deliberadamente acotado: incluye catálogos, identidad base,
organizaciones/perfiles, oportunidades/fuentes canónicas, plan Free y outbox. FASE 6 agregó
evidence editorial; FASE 7A, contenido bruto/runs para Grants.gov; y FASE 7B, extracción PDF
gobernada y un RSS oficial fijo sujeto a compliance. Proyectos/funders llegaron en FASE 5/6 y 9A
agregó la primera compatibilidad project-first, determinística y acotada. 9B-A prepara embeddings y
evaluación semántica sólo en sombra; 9B-B añade adapters gobernados y explicaciones administrativas
también en sombra, todavía sin activación ni eval real.
Billing y networking conservan sus fases; la autenticación completa corresponde a las
migraciones 002/003/004 de FASE 3.

## Arquitectura

La solución es un monolito modular con tres procesos backend desplegables:

~~~text
React SPA
   |
ASP.NET Core API
   |
Application -> Core
   |
Infrastructure -> Azure SQL / Blob / IA / email / pagos

FundingPlatform.Workers -> Application + Infrastructure
FundingPlatform.ExtractionWorkers -> Application + Infrastructure (superficie mínima)
~~~

Proyectos previstos:

~~~text
src/
  FundingPlatform.Api/
  FundingPlatform.Application/
  FundingPlatform.Core/
  FundingPlatform.Infrastructure/
  FundingPlatform.Workers/
  FundingPlatform.ExtractionWorkers/
  FundingPlatform.Contracts/

frontend/
  funding-platform-web

tests/
  FundingPlatform.UnitTests/
  FundingPlatform.IntegrationTests/

tools/
  FundingPlatform.DatabaseMigrator/
  FundingPlatform.AdminCli/
~~~

Reglas principales:

- Controllers coordinan HTTP; no contienen SQL ni reglas de negocio.
- Application implementa casos de uso.
- Core conserva dominio e interfaces sin dependencias de infraestructura.
- Infrastructure implementa Dapper y proveedores externos.
- Contracts contiene contratos públicos, no entidades persistentes.
- Todo dato tenant se autoriza por organizationId validado en servidor.
- Operaciones asíncronas usan outbox y Queue Storage con consumidores idempotentes.

Las decisiones arquitectónicas nuevas se registran en [docs/decisions/README.md](docs/decisions/README.md).
El prompt reproducible para investigación asistida por IA está en
[docs/PROMPT-BUSQUEDA-EXHAUSTIVA-FONDOS.md](docs/PROMPT-BUSQUEDA-EXHAUSTIVA-FONDOS.md).

Las imágenes externas solo se muestran cuando la fuente entrega URL, licencia/permiso, crédito y
procedencia verificables. No se reutilizan automáticamente logos, sellos ni fotografías encontradas
en una web. Si esos metadatos no existen, el frontend usa una portada temática propia y accesible.

## Despliegue conceptual

La preparación operativa y la secuencia exacta de Portal, identidades, SQL, dominios, configuración y
validación están en [Despliegue del MVP en Azure](docs/AZURE-MVP-DEPLOYMENT.md).

Topología del MVP:

- React en Azure Static Web Apps.
- API en Azure App Service Linux.
- Worker general y extractor documental aislado en Azure Functions Flex Consumption separados.
- Azure SQL provisionado pequeño para el piloto.
- Blob Storage para documentos/raw y Queue Storage para transporte.
- Microsoft Defender for Storage y Event Grid para escaneo on-upload, pendientes de activación y
  validación E2E por el operador.
- Key Vault y Managed Identity para secretos/accesos.
- Application Insights y Log Analytics para trazas, métricas y alertas.

Development, staging y production usan recursos y datos separados. Producción usará dominios app y api bajo el mismo sitio para la cookie refresh host-only; los dominios predeterminados inconexos no son una topología de sesión aceptada. Infraestructura como código, backups, restore, SLO y runbooks se completan en FASE 12 antes del primer piloto pagado.

## Seguridad básica del repositorio

- No guardes secretos en React, appsettings, documentación, fixtures ni logs.
- Usa placeholders en .env.example.
- No publiques local.settings.json ni certificados.
- Trata archivos y contenido importado como no confiables.
- No habilites una fuente web sin revisión de términos y robots.txt.
- No intentes evadir CAPTCHA, Cloudflare ni controles anti-bot.

## Roadmap

El orden de ejecución es:

- FASE 1 — solución compilable y estructura;
- FASE 2 — base de datos;
- FASE 3 — autenticación;
- FASE 4 — perfil institucional;
- FASE 5 — proyectos estructurados y perfil público;
- FASE 6 — funders, oportunidades y workflow editorial;
- FASE 7A — adquisición durable inicial mediante Grants.gov, Functions, Queue/outbox y consola admin;
- FASE 7B — extracción PDF aislada, recepción Defender/Event Grid fail-closed, RSS gobernado,
  retención y deduplicación humana;
- FASE 8A — catálogo organizacional, búsqueda, detalle completo y favoritos privados;
- FASE 8B — marketplace, postulaciones y calendario básico completados en código; activación de
  `019` pendiente de un despliegue autorizado;
- FASE 9A — compatibilidad determinística, versionada y explicable por proyecto, completada en
  código local; activación de `020` pendiente de un despliegue autorizado;
- FASE 9B-A — embeddings project-first y evaluación corpus-level sólo en sombra, completados en
  código local; activación de `021` pendiente;
- FASE 9B-B — adapters reales, gobierno/DPA/ZDR/precios y explicaciones shadow completados en código
  local; aplicación `022`/`023`, eval real, extracción generativa y decisión de promoción pendientes;
- FASE 10A — búsquedas guardadas y alertas email completadas en código local; aplicación `024` y
  activación del proveedor pendientes;
- FASE 10B — networking básico y solicitudes Connect moderadas;
- FASE 11 — suscripciones y administración completa;
- FASE 12 — hardening, pruebas y despliegue.

La API no aloja un crawler ni trabajos largos: Azure Functions procesa timers/colas y cada fuente
web requiere revisión de términos, `robots.txt`, rate limits, allowlist y kill switch. La beta de
billing utiliza sandbox. No se aceptan pagos ni donaciones reales hasta completar su compliance y
FASE 12.
