# Despliegue del MVP en Azure

Estado: FASE 12A preparada localmente mediante `infra/main.bicep`, módulos y workflows de validación
y despliegue manual. Este documento no acredita que los recursos Azure estén creados ni que
producción esté habilitada.

## 1. Arquitectura del MVP

El despliegue usa componentes separados:

- `frontend/funding-platform-web`: Azure Static Web Apps.
- `src/FundingPlatform.Api`: Azure Container Apps Consumption con imagen privada en ACR.
- `src/FundingPlatform.Workers`: Azure Functions para importaciones, outbox, retención y Event Grid.
- `src/FundingPlatform.ExtractionWorkers`: otra Function App para extraer PDF con identidad limitada.
- Azure SQL Database para datos y procedimientos almacenados.
- Storage GPv2 para host de Functions, colas y documentos privados.
- Key Vault para secretos y claves de Data Protection.
- Application Insights y Log Analytics para observabilidad.
- Azure Communication Services Email para correo transaccional.

Defender for Storage, Event Grid y `official-rss` permanecen deshabilitados hasta completar sus
permisos, políticas y una prueba E2E. El MVP durable nunca autopublica contenido importado.

## 2. Decisiones que deben tomarse antes de crear recursos

1. Elegir una región compatible con Container Apps, Container Registry, Functions Flex Consumption, Azure SQL, Static Web
   Apps y Communication Services. No fijar una región solo por cercanía sin comprobar disponibilidad.
2. Elegir nombres únicos. Ejemplo de convención: `rf-mvp-<recurso>-<sufijo>`.
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
`apply`; por defecto sólo ejecuta `what-if`.

## 4. Crear la base de recursos

La plantilla de FASE 12A crea esta base de forma reproducible. Antes de ejecutarla, seguir
[`infra/README.md`](../infra/README.md), configurar el environment GitHub `dev` y revisar el
`what-if`. Los pasos de Portal siguientes sirven como verificación, no como una segunda fuente de
infraestructura paralela.

En Azure Portal:

1. Crear el Resource Group de `staging`.
2. Crear Log Analytics y Application Insights.
3. Crear Azure SQL Server y una base exclusiva del MVP.
4. Configurar un administrador Microsoft Entra en el servidor SQL.
5. Crear Key Vault con RBAC de Azure y soft delete habilitado.
6. Crear Azure Communication Services Email y verificar el remitente/dominio.
7. Crear la cuenta de Blob documental y estos containers privados:
   - `fp-source-incoming`
   - `fp-source-quarantine`
   - `fp-source-trusted`
   - `dataprotection`
8. Crear la cola `document-extractions` y la cola `imports` donde corresponda.
9. Configurar lifecycle de `fp-source-incoming/uploads/` para eliminar cargas abandonadas después de
   un día. La retención de documentos aceptados la gestiona el vertical durable de la aplicación.
10. Crear Container Apps Environment Consumption y ACR Basic privado; deshabilitar usuario admin y
    dar `AcrPull` sólo a la UAMI de la API.

No habilitar acceso público anónimo en Blob. No usar account keys en App Settings.

## 5. Crear las aplicaciones

1. Crear Azure Static Web Apps para el frontend.
2. Construir `FundingPlatform.Api` con su Dockerfile no-root y desplegarla en Container Apps con
   ingress HTTPS, 0,5 vCPU/1 GiB, máximo una réplica y mínimo inicial `1`.
3. Crear dos Function Apps Flex Consumption separadas:
   - general: `FundingPlatform.Workers`;
   - extracción: `FundingPlatform.ExtractionWorkers`.
4. Configurar probes de Container Apps en `/health`; no usar `/health/ready` como sondeo periódico
   porque consulta SQL e impediría la auto-pausa.
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

La migración crea `FundingPlatform_ExtractionWorkerRole`. Crear en Azure SQL el usuario Entra de `C`
y agregarlo únicamente a ese rol. Los principales de API y Workers reciben roles/`EXECUTE` separados;
la identidad que aplica migraciones no se usa para ejecutar la aplicación.

Ejemplo conceptual, ejecutado por el administrador Entra y reemplazando el nombre por la UAMI real:

```sql
CREATE USER [rf-mvp-extraction-consumer] FROM EXTERNAL PROVIDER;
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
JWT_ISSUER=https://api.<dominio>
JWT_AUDIENCE=FundingPlatform.Web
AUTH_ACCESS_TOKEN_MINUTES=15
AUTH_REFRESH_TOKEN_DAYS=30
AUTH_ADMIN_SESSION_MINUTES=60
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
   `https://api.<dominio>/api/v1/auth/external/microsoft/callback`.
4. Configurar `ENTRA_SSO_ENABLED=true`, tenant `common`, client ID y el client secret desde Key Vault.
5. No agregar cada cliente como invitado al tenant; el alta ocurre en FundingPlatform después del
   callback validado.
6. Probar login, vinculación, logout, refresh y MFA administrativa con una cuenta de staging.

## 10. Aplicar la base de datos

La API no aplica migraciones al arrancar. Desde una máquina administrativa autenticada o un job
manual protegido:

```bash
dotnet run --project tools/FundingPlatform.DatabaseMigrator -- --status
dotnet run --project tools/FundingPlatform.DatabaseMigrator -- --validate
dotnet run --project tools/FundingPlatform.DatabaseMigrator -- --apply
dotnet run --project tools/FundingPlatform.DatabaseMigrator -- --test
dotnet run --project tools/FundingPlatform.DatabaseMigrator -- --provision-full-text
dotnet run --project tools/FundingPlatform.DatabaseMigrator -- --status
```

Antes de `--apply`: confirmar servidor/base, backup/PITR y checksums. Después: esperar Full-Text `ready`,
ejecutar un segundo `--apply` que reporte cero pendientes y guardar la evidencia en
`database/DEPLOYMENT-LOG.md`.

## 11. Configurar el frontend

En Azure Static Web Apps:

```text
app_location: frontend/funding-platform-web
api_location: (vacío)
output_location: dist
```

Variables de build, que son públicas por definición:

```text
VITE_API_BASE_URL=https://api.<dominio>/api/v1
VITE_EXTERNAL_AUTH_BASE_URL=https://api.<dominio>/api/v1
```

`public/staticwebapp.config.json` incluye fallback SPA y cabeceras básicas; Vite lo copia a `dist`.
No colocar tokens, claves ni connection strings en variables `VITE_*`.

## 12. Despliegue continuo

1. Ejecutar primero el workflow `CI` del repositorio.
2. Ejecutar `infra-dev.yml` con `validate`, después `what-if` y finalmente `apply-base` confirmado;
   esta última operación crea ACR/entorno pero todavía no crea la API.
3. Cargar secretos, crear usuarios/roles SQL y ejecutar `apply`; recién entonces ACR Build publica la
   imagen y Container Apps la consume por digest OCI.
4. Publicar cada Function App desde un workflow posterior indicando el `.csproj` correcto.
5. Crear/publicar la Static Web App desde el repositorio con las rutas del punto anterior.
6. Exigir aprobación del entorno GitHub `production` y no reutilizar UAMI runtime en Actions.

FASE 12A deja preparado el build remoto y despliegue por digest de la **API** dentro del apply manual.
La publicación de Functions/frontend sigue en 12B, después de observar outputs, dominios e
identidades reales. No se aceptan publish profiles ni secretos de service principal o de ACR.

## 13. Dominios, TLS y comprobación final

1. Verificar la propiedad del dominio con el TXT solicitado por Azure antes de agregar CNAME/A.
2. Asociar `app.<dominio>` a Static Web Apps y `api.<dominio>` a Container Apps.
3. Habilitar certificados administrados y HTTPS-only.
4. Actualizar CORS, frontend URL, issuer y redirect URI con valores finales exactos.
5. Validar:
   - `GET https://api.<dominio>/health`
   - `GET https://api.<dominio>/health/ready`
   - frontend y navegación profunda recargable
   - registro manual y Microsoft
   - refresh de sesión después de expirar el access token
   - MFA y consola administrativa
   - creación de organización/proyecto
   - publicación administrativa de un fondo
   - búsqueda, detalle y favorito desde una organización
   - importación manual y procesamiento de colas
   - carga PDF solo cuando el escaneo real esté habilitado
6. Confirmar en Application Insights que no se registran JWT, refresh tokens, SAS, hashes privados ni
   contenido raw.
7. Crear alertas de 5xx, health no disponible, colas con backlog, jobs atascados y presupuesto.

## 14. Qué puede habilitarse en el primer staging

Puede probarse registro/login, organizaciones, proyectos, administración editorial, fondos públicos,
búsqueda/favoritos y Grants.gov durable. Mantener deshabilitados hasta su propia validación:

- pagos y suscripciones reales;
- Defender/Event Grid si no están completos los permisos y la prueba E2E;
- `official-rss` sin revisión de licencia/robots;
- IA/recomendaciones automáticas de fases posteriores;
- piloto pagado antes del hardening y restauración ensayada de FASE 12.
