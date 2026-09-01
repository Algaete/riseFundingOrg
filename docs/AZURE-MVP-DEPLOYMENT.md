# Despliegue del MVP en Azure

Estado 2026-09-01: la infraestructura base de FASE 12A está creada en Azure dev; la base
`risefunding-dev` tiene `001`→`029`, 29 smokes, reapply idempotente, Full-Text, principals runtime y
bootstrap SuperAdmin verificados. La API está publicada por digest OCI en
`https://ca-rf-dev-ag26rf01-api.gentlesea-402d2db7.eastus2.azurecontainerapps.io` y pasó salud, SQL y
catálogo público. El frontend técnico del commit
`c348071360d1bdf7fdd32cffb280eeaf0a93c901` está publicado y verificado en
`https://salmon-glacier-0721afc0f.7.azurestaticapps.net`. Las Function Apps Flex existen sin paquetes;
carga PDF E2E, correo, dominios propios, APM/alertas, restore y producción siguen pendientes. SSO
Entra está implementado en código, pero permanece sin configurar y deshabilitado en Azure dev. Este
release prepara E2E público Playwright/axe y paquetes Functions offline verificables. No publica
workers: el cambio local de IaC define las 16 Functions como deshabilitadas, pero aún no fue aplicado;
las Function Apps desplegadas no tienen paquetes y por eso no poseen triggers ejecutables.

## 1. Arquitectura del MVP

El despliegue usa componentes separados:

- `frontend/funding-platform-web`: Azure Static Web Apps.
- `src/FundingPlatform.Api`: Azure Container Apps Consumption con imagen privada en ACR.
- `src/FundingPlatform.Workers`: Azure Functions para importaciones, outbox, retención y Event Grid.
- `src/FundingPlatform.ExtractionWorkers`: otra Function App para extraer PDF con identidad limitada.
- Azure SQL Database para datos y procedimientos almacenados.
- Storage GPv2 para host de Functions, colas y documentos privados.
- Key Vault para secretos y claves de Data Protection.
- Log Analytics para logs de sistema/consola y Application Insights compartido con Functions; la
  instrumentación APM del API se completa en 12B.
- Azure Communication Services Email para correo transaccional, diferido a 12B.

Defender for Storage, Event Grid y `official-rss` permanecen deshabilitados hasta completar sus
permisos, políticas y una prueba E2E. El MVP durable nunca autopublica contenido importado.

## 2. Decisiones que deben tomarse antes de crear recursos

1. Elegir una región compatible con Container Apps, Container Registry, Functions Flex Consumption, Azure SQL, Static Web
   Apps y Communication Services. No fijar una región solo por cercanía sin comprobar disponibilidad.
2. Elegir una sola vez un sufijo único de exactamente 8 caracteres `[a-z0-9]` y reutilizarlo. Ejemplo
   de convención: `rf-mvp-<recurso>-<sufijo8>`.
3. Comprar o disponer de un dominio. Reservar, como mínimo:
   - `app.<dominio>` para React.
   - `api.<dominio>` para la API.
4. Crear un ambiente `staging` separado antes de producción. No usar la base de desarrollo `res`
   como base pública sin una decisión explícita, backup verificado y revisión de datos.
5. Definir presupuesto y alertas de costo en la suscripción.

Los subdominios `app` y `api` deben compartir el mismo sitio registrable. La cookie refresh es segura,
host-only y `SameSite=Lax`; una Static Web App bajo `azurestaticapps.net` y una API bajo
`azurecontainerapps.io` no constituyen la topología final de sesión.

## 3. Preparar GitHub

1. Proteger `main`: exigir pull request y el workflow `CI` en cambios posteriores al primer push.
2. No almacenar publish profiles, connection strings, contraseñas ni JSON de service principals.
3. Para despliegues usar OpenID Connect (OIDC). La credencial federada de GitHub es distinta de las
   identidades que ejecutan Container Apps y Functions; no se usan publish profiles.
4. Definir entornos de GitHub `staging` y `production`, con aprobación manual para `production`.

El workflow `.github/workflows/ci.yml` compila y prueba. `infra-validate.yml` compila Bicep sin
credenciales. `infra-dev.yml` es exclusivamente manual, usa OIDC y exige confirmación literal para
`apply`; por defecto sólo ejecuta `what-if`. `frontend-dev.yml` también es manual: exige el SHA
exacto de `main`, compila sin credenciales Azure y publica el artefacto prevalidado en SWA usando un
deployment token leído y enmascarado justo a tiempo mediante OIDC.

## 4. Crear la base de recursos

La plantilla de FASE 12A crea esta base de forma reproducible. Antes de ejecutarla, seguir
[`infra/README.md`](../infra/README.md) y el
[`checklist dev`](../infra/DEV-DEPLOYMENT-CHECKLIST.md), configurar el environment GitHub `dev` y
revisar el `what-if`. La lista siguiente describe los recursos que deben aparecer; no se crean otra
vez manualmente en Portal.

En Azure Portal:

1. Resource Group `dev` separado.
2. Log Analytics y Application Insights.
3. Azure SQL Server y base `risefunding-dev` exclusiva.
4. Administrador Microsoft Entra en el servidor SQL.
5. Key Vault con RBAC de Azure y soft delete habilitado.
6. Cuenta de Blob documental y estos containers privados:
   - `fp-source-incoming`
   - `fp-source-quarantine`
   - `fp-source-trusted`
   - `dataprotection`
7. Cola `document-extractions` y una cola `imports` en cada host general donde corresponda.
8. Lifecycle de `fp-source-incoming/uploads/` para retirar cargas abandonadas después de un día y
   borrar sus versiones anteriores a los 14 días; sin esa segunda acción, Blob Versioning las
   conservaría indefinidamente. La retención de documentos aceptados la gestiona la aplicación.
9. Container Apps Environment Consumption y ACR Basic autenticado; usuario admin deshabilitado y
   `AcrPull` sólo para la UAMI de la API.

Azure Communication Services Email no se crea en 12A: alertas/email siguen deshabilitados hasta su
gate propio de 12B.

No habilitar acceso público anónimo en Blob. No usar account keys en App Settings.

## 5. Crear las aplicaciones

1. Crear Azure Static Web Apps para el frontend.
2. Construir `FundingPlatform.Api` con su Dockerfile no-root y desplegarla en Container Apps con
   ingress HTTPS, 0,5 vCPU/1 GiB, máximo una réplica y mínimo inicial `1`.
3. Crear dos Function Apps Flex Consumption separadas:
   - general: `FundingPlatform.Workers`;
   - extracción: `FundingPlatform.ExtractionWorkers`.
4. Configurar probes de Container Apps en `/health`; `/health/ready` no se publica en Azure porque
   consulta SQL e impediría la auto-pausa.
5. Cambiar el mínimo a `0` mediante Bicep cuando se acepte el cold start; una petición pública puede
   volver a escalar la aplicación.

Antes de elegir una versión del runtime en el Portal, comprobar que soporte el `global.json` y los
`TargetFramework` del repositorio. El pipeline es la fuente de verdad: cualquier downgrade debe ser
un cambio de código probado, no una selección silenciosa en Azure.

## 6. Identidades administradas y RBAC

Crear cuatro UAMI distintas para Functions:

| Identidad | Se adjunta a | Permisos funcionales |
|---|---|---|
| `H_general` | solo Workers general | host storage, cola `imports`, Blob general y SQL del worker |
| `H_extractor` | solo ExtractionWorkers | host storage del extractor |
| `S` | solo Workers general | `Storage Queue Data Message Sender` sobre `document-extractions` |
| `C` | solo ExtractionWorkers | `Storage Queue Data Message Processor`, lectura de `fp-source-trusted` y rol SQL de extracción |

Reglas obligatorias:

- `H_general`, `H_extractor`, `S` y `C` tienen client IDs diferentes.
- En cada Function App solo se adjuntan las identidades indicadas en la tabla.
- El host storage del extractor no es la cuenta documental ni la cola de datos de extracción.
- La API usa su propia Managed Identity.
- La misma UAMI autentica en ACR para pull, Key Vault, Blob y SQL; `AZURE_CLIENT_ID` la fija de forma
  explícita y no se adjunta otra identidad a Container Apps.
- Otorgar permisos al scope más pequeño posible: cola o container, no toda la suscripción.

Para la API:

- `Key Vault Secrets User` en el vault.
- `Key Vault Crypto User` sobre la clave de Data Protection.
- `Storage Blob Data Contributor` limitado al container `dataprotection` y a los containers que la
  API realmente escribe.
- `AcrPull` únicamente sobre el registry dev.
- permisos SQL de ejecución solo para sus procedimientos requeridos.

Las migraciones crean roles host-específicos. La UAMI API recibe sólo
`FundingPlatform_ApiRuntimeRole`, `H_general` sólo `FundingPlatform_GeneralWorkerRole` y `C` sólo
`FundingPlatform_ExtractionWorkerRole`; `H_extractor` y `S` no tienen usuario SQL. La identidad que
aplica migraciones no se usa para ejecutar la aplicación.

Ejemplo conceptual; el despliegue real usa `DatabaseMigrator --provision-runtime-identities` para
derivar y verificar el SID desde el `clientId`, sin Microsoft Graph:

```sql
CREATE USER [rf-mvp-extraction-consumer]
    WITH SID = <0x-sid-binario-del-client-id>, TYPE = E;
ALTER ROLE [FundingPlatform_ExtractionWorkerRole]
    ADD MEMBER [rf-mvp-extraction-consumer];
```

## 7. Key Vault y configuración de la API

Crear valores aleatorios independientes y guardar secretos con nombres jerárquicos de ASP.NET Core:

- `Authentication--Jwt--SigningKey`
- `Authentication--SecurityHash--IpHashPepper`
- `Authentication--SecurityHash--RecoveryCodePepper`
- `Authentication--External--Entra--ClientSecret` cuando SSO esté habilitado

Los peppers y la signing key se generan fuera del repositorio. No se reutilizan entre staging y
producción. Configurar en Container Apps/Key Vault, sin copiar secretos:

```text
ASPNETCORE_ENVIRONMENT=Production
AZURE_KEY_VAULT_URI=https://<vault>.vault.azure.net/
AZURE_STORAGE_DATA_PROTECTION_BLOB_URI=https://<storage>.blob.core.windows.net/dataprotection/keys.xml
AZURE_KEY_VAULT_DATA_PROTECTION_KEY_URI=https://<vault>.vault.azure.net/keys/data-protection
AZURE_SQL_CONNECTION_STRING=Server=tcp:<server>.database.windows.net,1433;Initial Catalog=<database>;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;
AZURE_STORAGE_BLOB_SERVICE_URI=https://<documents>.blob.core.windows.net
SOURCE_DOCUMENT_INCOMING_CONTAINER=fp-source-incoming
SOURCE_DOCUMENT_QUARANTINE_CONTAINER=fp-source-quarantine
SOURCE_DOCUMENT_TRUSTED_CONTAINER=fp-source-trusted
FRONTEND_BASE_URL=https://app.<dominio>
ALLOWED_CORS_ORIGINS=https://app.<dominio>
Authentication__Jwt__Issuer=https://api.<dominio>
Authentication__Jwt__Audience=FundingPlatform.Web
Authentication__Jwt__AccessTokenMinutes=15
Authentication__RefreshToken__LifetimeDays=30
Authentication__Mfa__AdminSessionMinutes=60
Email__Enabled=false
Email__FrontendBaseUrl=https://app.<dominio>
APPLICATIONINSIGHTS_CONNECTION_STRING=<referencia de Azure>
```

Si la API usa UAMI, añadir `User Id=<client-id>` a la conexión SQL. Mantener
`SOURCE_DOCUMENT_SCAN_MODE=MicrosoftDefender` solo cuando Event Grid esté totalmente configurado;
`DevelopmentFake` nunca se habilita en producción.

## 8. Configurar Workers

En ambas Function Apps configurar `AZURE_FUNCTIONS_ENVIRONMENT=Production`, SQL, Application Insights
y sus opciones específicas. Usar conexiones identity-based, no connection strings con keys.

Workers general:

```text
AzureWebJobsStorage__blobServiceUri=https://<general-host>.blob.core.windows.net
AzureWebJobsStorage__queueServiceUri=https://<general-host>.queue.core.windows.net
AzureWebJobsStorage__tableServiceUri=https://<general-host>.table.core.windows.net
AzureWebJobsStorage__credential=managedidentity
AzureWebJobsStorage__clientId=<H_general-client-id>
DocumentExtractionQueueStorage__queueServiceUri=https://<data>.queue.core.windows.net
DocumentExtractionQueueStorage__credential=managedidentity
DocumentExtractionQueueStorage__senderClientId=<S-client-id>
DocumentExtractionQueueStorage__clientId=<C-client-id-declarado-para-validar-separacion>
```

ExtractionWorkers:

```text
AzureWebJobsStorage__blobServiceUri=https://<extractor-host>.blob.core.windows.net
AzureWebJobsStorage__queueServiceUri=https://<extractor-host>.queue.core.windows.net
AzureWebJobsStorage__tableServiceUri=https://<extractor-host>.table.core.windows.net
AzureWebJobsStorage__credential=managedidentity
AzureWebJobsStorage__clientId=<H_extractor-client-id>
DocumentExtractionQueueStorage__queueServiceUri=https://<data>.queue.core.windows.net
DocumentExtractionQueueStorage__credential=managedidentity
DocumentExtractionQueueStorage__clientId=<C-client-id>
DocumentExtractionQueueStorage__senderClientId=<S-client-id-declarado-para-validar-separacion>
AZURE_STORAGE_BLOB_SERVICE_URI=https://<documents>.blob.core.windows.net
```

Copiar el resto de valores no secretos desde `.env.example`, revisando cada uno. No copiar el archivo
completo ni dejar placeholders en Production.

## 9. Microsoft Entra para acceso público

1. Crear App Registration de tipo Web.
2. Permitir cuentas organizacionales y cuentas personales Microsoft si ese sigue siendo el alcance.
3. Agregar redirect URI exacta:
   `https://api.<dominio>/api/v1/auth/external/entra/callback`.
4. Configurar `ENTRA_SSO_ENABLED=true`, tenant `common`, client ID y el client secret desde Key Vault.
5. No agregar cada cliente como invitado al tenant; el alta ocurre en FundingPlatform después del
   callback validado.
6. Probar login, vinculación, logout, refresh y MFA administrativa con una cuenta de staging.

## 10. Aplicar la base de datos

La API no aplica migraciones al arrancar. La preparación dev se ejecuta desde una terminal humana
autenticada con el wrapper versionado; éste deriva el único servidor SQL del Resource Group, bloquea
la carga accidental del `.env`, valida base y FQDN, y arma una regla firewall temporal con limpieza
automática:

```bash
AZURE_SUBSCRIPTION_ID='<subscription-id>' \
AZURE_TENANT_ID='<tenant-id>' \
AZURE_UNIQUE_SUFFIX='<sufijo8>' \
RF_DEV_RELEASE_SHA='<commit-aprobado-de-40-caracteres>' \
RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID='<group-object-id>' \
RF_DEV_SQL_ADMIN_GROUP_NAME='<display-name-exacto>' \
RF_DEV_ADMIN_EMAIL='<superadmin-dev>' \
bash infra/scripts/prepare-database-dev.sh
```

El wrapper exige `main` limpio e idéntico a `origin/main`, al menos 2 GiB libres y una terminal
interactiva para la contraseña del SuperAdmin. La autenticación del operador queda fijada a la
sesión de Azure CLI ya validada. En el estado actual ejecuta primero `--preflight`, confirma las 29
migraciones registradas sin pendientes y luego ejecuta los 29 smokes con rollback, verifica
`Full-Text 8A: listo`, prueba reapply/provisioning idempotentes y vincula las tres UAMI SQL por
`clientId`/SID sin Microsoft Graph. El procedimiento exacto y sus prerrequisitos están en
[`infra/DEV-DEPLOYMENT-CHECKLIST.md`](../infra/DEV-DEPLOYMENT-CHECKLIST.md).

## 11. Configurar y publicar el frontend

El workflow manual `frontend-dev.yml` ejecuta el build por separado y entrega a Static Web Apps un
artefacto precompilado con este contrato:

```text
app_location: frontend-dist
api_location: (vacío)
output_location: (vacío)
skip_app_build: true
skip_api_build: true
```

Resuelve desde Azure y fija durante el build estas variables, públicas por definición:

```text
VITE_API_BASE_URL=https://<api-fqdn>.azurecontainerapps.io/api/v1
VITE_EXTERNAL_AUTH_BASE_URL=https://<api-fqdn>.azurecontainerapps.io/api/v1
```

`public/staticwebapp.config.json` incluye fallback SPA y cabeceras básicas; Vite lo copia a `dist`.
No colocar tokens, claves ni connection strings en variables `VITE_*`. Para publicar desde `main`,
seleccionar `DEPLOY-DEV-FRONTEND` e ingresar el SHA completo aprobado. El deployment token se lee de
SWA con la identidad OIDC y se enmascara; sólo su copia en el runner vive durante ese job y no se
almacena en GitHub. La credencial original sigue siendo persistente en Azure hasta que se rote.

El smoke verifica `deploy-meta.json`, raíz, `/funding`, headers y CORS del API. Esto no valida aún
refresh/login persistente entre hosts cross-site ni PUT directo a Blob; esas pruebas esperan dominios
same-site y CORS/Functions/Defender para importación.

## 12. Despliegue continuo

En Azure dev, los pasos 1–4 ya se completaron para el preview actual; permanecen como runbook para
futuros releases. El paso 5 continúa bloqueado hasta cerrar los gates gobernados de Functions.

1. Ejecutar primero el workflow `CI` del repositorio.
2. Ejecutar `infra-dev.yml` con `validate`, después `what-if` y finalmente `apply-base` confirmado;
   esta última operación crea ACR/entorno pero todavía no crea la API.
3. Cargar secretos, crear usuarios/roles SQL y ejecutar `apply`; recién entonces ACR Build publica la
   imagen y Container Apps la consume por digest OCI.
4. Ejecutar `frontend-dev.yml` con el mismo SHA aprobado; el workflow publica y verifica el preview
   técnico de Static Web Apps.
5. Publicar cada Function App desde un workflow posterior indicando el `.csproj` correcto y sólo
   después de habilitar las dependencias gobernadas correspondientes.
6. Exigir aprobación del entorno GitHub `production` y no reutilizar UAMI runtime en Actions.

FASE 12A dejó desplegadas la **API** por digest y la publicación precompilada del frontend como
preview técnico. Los recursos base de Functions existen sin paquetes y la topología final con
dominios sigue en 12B. No se aceptan publish profiles ni secretos de service principal, ACR o SWA
persistidos en GitHub.

El job .NET de CI construye ambos ZIP Functions sin Azure, rechaza configuración local y patrones
conocidos de archivos sensibles, y publica temporalmente un artifact con manifiestos y SHA-256.
Esta validación estructural no sustituye un escaneo de secretos por contenido. El job público
posterior al frontend usa Playwright contra la URL resuelta, pero recibe únicamente `contents: read`;
no hereda OIDC, token de Static Web Apps ni credenciales de usuario.

## 13. Dominios, TLS y comprobación final

1. Verificar la propiedad del dominio con el TXT solicitado por Azure antes de agregar CNAME/A.
2. Asociar `app.<dominio>` a Static Web Apps y `api.<dominio>` a Container Apps.
3. Habilitar certificados administrados y HTTPS-only.
4. Actualizar CORS, frontend URL, issuer y redirect URI con valores finales exactos.
5. En 12B, cuando estén configurados y habilitados dominios, ACS y SSO, validar:
   - `GET https://api.<dominio>/health`
   - una lectura limitada del catálogo público para comprobar conexión/permisos SQL;
   - frontend y navegación profunda recargable
   - registro manual y Microsoft
   - refresh de sesión después de expirar el access token
   - MFA y consola administrativa
   - creación de organización/proyecto
   - publicación administrativa de un fondo
   - búsqueda, detalle y favorito desde una organización
   - importación manual y procesamiento de colas
   - carga PDF solo cuando el escaneo real esté habilitado
6. En el smoke 12A revisar logs de sistema/consola de Container Apps en Log Analytics. Después de
   instrumentar APM en 12B, confirmar también en Application Insights que no se registran JWT,
   refresh tokens, SAS, hashes privados ni contenido raw.
7. Crear alertas de 5xx, health no disponible, colas con backlog, jobs atascados y presupuesto.

## 14. Qué puede habilitarse en el primer staging

El primer gate 12A comprueba `/health`, base/migraciones, bootstrap SuperAdmin, preview del frontend y
arranque fail-closed. Una cuenta local ya aprovisionada puede probar el login manual en dev.
Con `Email__Enabled=false`, alta autoservicio, reenvío de verificación y recuperación responden `503`
antes de persistir. SSO Entra sigue sin configurar ni habilitar; el E2E de altas/MFA espera ACS y la
validación de refresh cross-site espera dominios same-site en 12B. Mantener además deshabilitados
hasta su propia validación:

- pagos y suscripciones reales;
- Defender/Event Grid si no están completos los permisos y la prueba E2E;
- `official-rss` sin revisión de licencia/robots;
- IA/recomendaciones automáticas de fases posteriores;
- piloto pagado antes del hardening y restauración ensayada de FASE 12.
