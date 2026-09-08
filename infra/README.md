# Infraestructura Azure — FASE 12A

Este directorio prepara un ambiente `dev` separado mediante Bicep. Ninguna plantilla ni publicación
se ejecuta al hacer push: `infra-dev.yml` y `frontend-dev.yml` sólo se inician manualmente, usan OIDC
y exigen una confirmación explícita para cada mutación.

## Topología preparada

- Resource Group exclusivo y presupuesto mensual real con avisos al 50%, 80% y 100% previsto.
- API en Azure Container Apps Consumption: 0,5 vCPU, 1 GiB, máximo una réplica y mínimo configurable
  `1`/`0`; el workflow conserva `0` como opción segura por defecto y el primer smoke selecciona `1`.
- Azure Container Registry Basic privado, sin usuario administrador ni credenciales de registro; la
  UAMI de la API recibe solamente `AcrPull`.
- React en Static Web Apps Free y dos Function Apps Flex Consumption con escala a cero y máximo
  dev de una instancia bajo demanda por app.
- Azure SQL General Purpose serverless, 1 vCore máximo, 0,5 mínimo y auto-pausa a 60 minutos.
- Log Analytics/Application Insights, Key Vault RBAC y clave rotatoria de Data Protection.
- Storage documental, Storage de colas y un host Storage distinto por Function App.
- Lifecycle que quita la versión actual de blobs abandonados bajo `fp-source-incoming/uploads/`
  después de un día y elimina sus versiones anteriores después de 14 días.
- Cinco UAMI: API, `H_general`, `H_extractor`, sender `S` y consumer `C`.

La cola y el container de extracción tienen RBAC a nivel del recurso. Shared Key y acceso Blob
anónimo están deshabilitados. La regla SQL `0.0.0.0` permite servicios Azure solamente en dev; no es
la topología de producción y se reemplazará por red privada cuando las mediciones justifiquen el
costo.

## Imagen y despliegue de la API

`src/FundingPlatform.Api/Dockerfile` produce una imagen .NET 10 no-root sobre el puerto `8080` y
`.dockerignore` impide enviar `.env`, `.git`, tests y artefactos al contexto remoto. El flujo manual:

1. `apply-base` crea la base, el Container Apps Environment y ACR sin crear aún la app; exige
   `DEPLOY-DEV-BASE`;
2. el operador carga secretos y configura usuarios/roles SQL;
3. `apply` ejecuta `az acr build`, publica `rise-funding-api:<commit>` y obtiene su digest OCI;
4. crea/actualiza Container Apps usando ese digest, nunca `latest` ni una contraseña de registry.

Los probes de plataforma usan `/health`, que no consulta SQL. `/health/ready` existe sólo en
Development/Testing y no se publica en Azure; el verificador usa una lectura pública limitada para
probar conexión y permisos SQL sin dejar un endpoint de readiness que mantenga despierta la base.

## Publicación del frontend dev

`frontend-dev.yml` publica el React ya compilado en la Static Web App existente. Primero resuelve y
valida en Azure el hostname real de SWA, el FQDN del API y su CORS; después compila, ejecuta lint y
tests en un job sin credenciales Azure. El job final descarga ese artefacto inmutable, obtiene el
deployment token de SWA mediante la identidad OIDC, lo enmascara sin persistirlo en GitHub y publica
con `skip_app_build`. El smoke posterior comprueba el SHA expuesto en `deploy-meta.json`, raíz, ruta
SPA profunda, headers de seguridad, catálogo público y CORS del API.

El token original es una credencial persistente del recurso Azure, no un token efímero; el workflow
sólo evita copiarlo a configuración permanente de GitHub y limpia su copia del runner tras publicar.

La ejecución manual exige `expected_release_sha` igual al SHA de `main` y confirmación
`DEPLOY-DEV-FRONTEND`. Esta primera URL es un **preview técnico**: los dominios predeterminados de SWA
y Container Apps son cross-site, por lo que el refresh cookie `SameSite=Lax` requiere todavía
`app.<dominio>`/`api.<dominio>` bajo el mismo sitio registrable. La carga directa de PDF también queda
pendiente hasta versionar CORS de Blob y publicar/validar Functions y Defender/Event Grid.

## Escala y costo

El workflow pregunta `api_min_replicas`:

- `1`: mantiene una réplica tibia al comenzar el ambiente dev;
- `0`: permite escala a cero cuando no hay tráfico; una solicitud pública puede volver a activarla.

El máximo permanece en una réplica. La operación manual `scale-api`, confirmada con
`SCALE-DEV-API`, cambia `1`/`0` sin reconstruir la imagen; Bicep y el workflow usan `0` por defecto
para evitar reactivaciones accidentales. ACR Basic tiene costo fijo diario aunque la API esté en
cero; Container Apps cobra consumo y el mínimo `1` puede consumir la franquicia gratuita. El importe
real depende de región, contrato y moneda de la suscripción y se revisa antes de `apply`.

`pause-api` (`PAUSE-DEV-API`) además cierra el ingress y es la pausa recomendada; `resume-api`
(`RESUME-DEV-API`) lo reabre. Todo `apply` vuelve a habilitar el ingress según Bicep, por lo que hay
que volver a pausar si corresponde. `rollback-api` (`ROLLBACK-DEV-API`) reutiliza un digest OCI
`sha256:...` existente y saludable, sin `latest` ni build nuevo.

## Validación local

```bash
bicep build infra/main.bicep --stdout >/dev/null
bash -n infra/scripts/deploy-dev.sh
bash -n infra/scripts/prepare-key-vault-dev.sh
bash -n infra/scripts/prepare-database-dev.sh
bash -n infra/scripts/scale-api-dev.sh
bash -n infra/scripts/set-api-access-dev.sh
bash -n infra/scripts/rollback-api-dev.sh
bash -n infra/scripts/verify-dev.sh
docker build -f src/FundingPlatform.Api/Dockerfile -t rise-funding-api:local .
```

Después de crear recursos, la verificación read-only usa solamente metadata y `/health`; nunca lista
secretos:

```bash
AZURE_SUBSCRIPTION_ID=<id> AZURE_TENANT_ID=<id> AZURE_SQL_LOCATION=centralus AZURE_UNIQUE_SUFFIX=<sufijo8> bash infra/scripts/verify-dev.sh base
AZURE_SUBSCRIPTION_ID=<id> AZURE_TENANT_ID=<id> AZURE_SQL_LOCATION=centralus AZURE_UNIQUE_SUFFIX=<sufijo8> AZURE_API_MIN_REPLICAS=1 bash infra/scripts/verify-dev.sh api
AZURE_SUBSCRIPTION_ID=<id> AZURE_TENANT_ID=<id> AZURE_SQL_LOCATION=centralus AZURE_UNIQUE_SUFFIX=<sufijo8> AZURE_API_MIN_REPLICAS=1 EXPECTED_FRONTEND_RELEASE_SHA=<sha40> bash infra/scripts/verify-dev.sh frontend
```

La verificación `base` exige además las 16 Functions deshabilitadas por nombre y autenticación básica
de publicación SCM/FTP cerrada en ambos hosts. El workflow `Infrastructure validation` compila con
Bicep `0.46.1` sin iniciar sesión en Azure y
construye la imagen sin publicarla. El workflow manual comprueba Container Apps, ACR, Static Web Apps,
Functions Flex y `dotnet-isolated` 10.0 en la región antes de `validate`, `what-if` o `apply`.

## Variables del environment GitHub `dev`

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`: identidad de despliegue OIDC;
- `AZURE_LOCATION`: región validada;
- `AZURE_SQL_LOCATION`: región validada de Azure SQL; puede diferir de la aplicación cuando la
  suscripción restringe SQL en la región principal (`centralus` para el ambiente dev actual);
- `AZURE_UNIQUE_SUFFIX`: exactamente 8 caracteres `[a-z0-9]`; se elige una vez y se reutiliza;
- `AZURE_SQL_ADMIN_LOGIN`, `AZURE_SQL_ADMIN_OBJECT_ID`: grupo Entra administrador;
- `AZURE_BUDGET_START_DATE`, `AZURE_MONTHLY_BUDGET_AMOUNT` (moneda de facturación de la
  suscripción, no una divisa asumida por el repositorio);
- `AZURE_DEPLOY_COMPUTE`: `true` para incluir API/frontend/Functions.

`AZURE_BUDGET_EMAIL` se registra como **environment secret**, no como variable. El mínimo de la API
se elige en cada ejecución manual. Los demás identificadores no son credenciales. La identidad OIDC
se federa con issuer `https://token.actions.githubusercontent.com` al subject inmutable
`repo:Algaete@51843665/riseFundingOrg@1344044015:environment:dev`; el environment se restringe a
`main`, que también debe estar protegida por PR/checks y sin force-push/eliminación. Además de
desplegar la base y sus RBAC, necesita ejecutar ACR Tasks/build y leer el manifest mediante
`AcrPull`. No se usan publish profiles, passwords de ACR ni client secrets.

Los roles amplios de bootstrap son JIT: al terminar se retiran de la suscripción. El estado normal
conserva `Contributor` sólo en el Resource Group dev y los dos roles ACR sólo en el registry. Un apply
completo posterior exige elevación temporal aprobada; `scale-api` no la necesita.

## Estado operativo de Azure dev — 2026-09-07

La base `risefunding-dev` tiene aplicadas `001`→`030`; los 30 smokes SQL, el reapply idempotente y
Full-Text pasaron. Los principals runtime y el bootstrap SuperAdmin quedaron verificados. La imagen
de API fue publicada por digest OCI y Container Apps quedó saludable en
`https://ca-rf-dev-ag26rf01-api.gentlesea-402d2db7.eastus2.azurecontainerapps.io`; el verificador
confirmó `/health`, conexión SQL y catálogo público.

El workflow `Azure dev frontend` publicó y verificó el commit
`0e8d816b686beec5d7259150b9d484bc1a0c87c2` en
`https://salmon-glacier-0721afc0f.7.azurestaticapps.net`: pasaron `deploy-meta.json`, raíz,
`/funding`, fallback SPA, headers y CORS GET/preflight. La Function App general tiene publicado el
paquete del commit local `93ad3574f5ba76347833608f100adfe9f58a8f35`; únicamente sus tres
triggers de importación están habilitados. La app de extracción conserva sus dos triggers
deshabilitados y continúa sin paquete. Importación PDF E2E, correo, dominios propios, alertas y
restore siguen pendientes.
La API ya exporta APM con identidad administrada y pasó el canary de correlación/privacidad.
SSO Entra está implementado
en código, pero permanece sin configurar y deshabilitado en Azure dev.

CI ya puede preparar **offline** ambos proyectos Functions en ZIP deterministas, inventariados y con
SHA-256. Ese artifact dura siete días y rechaza configuración local y patrones conocidos de archivos
sensibles; esta validación estructural no sustituye un escaneo de secretos por contenido. El release
`680c96bc0b97b5b2c67594c0f997d99aa1370880` aplicó y verificó las 16 barreras iniciales y SCM/FTP
basic auth cerrado en ambos hosts. La publicación posterior del worker general conservó once
triggers deshabilitados y activó sólo dispatcher, cola y scheduler de importación. La API conservó
su digest y revisión, y el principal OIDC quedó sin roles de suscripción y limitado al Resource
Group/ACR.

El frontend incorpora una suite Playwright/axe pública. CI la ejecuta contra un preview aislado y
`frontend-dev.yml` la repite después de publicar, sin OIDC ni credenciales Azure o de usuarios,
comprobando además el SHA inmutable. Login autenticado, refresh cross-site y journeys mutantes
siguen siendo gates separados.

El incremento del 2026-09-06 incorpora OpenTelemetry por UAMI, el interlock de arranque inerte
de Defender y alertas opt-in con `deployOperationalAlerts=false`. También prepara el workflow manual
de sesión autenticada y el simulacro PITR a una base nueva. La API del SHA
`0e8d816b686beec5d7259150b9d484bc1a0c87c2` fue publicada por el workflow acotado, sin ampliar permisos,
conservando escala 1/1. El canary confirmó `FundingPlatform.Api`, plantillas de ruta y ausencia de
query/slug sintéticos y texto SQL en la telemetría de sus dos solicitudes. El worker general y sus
variables de host fueron publicados después; su canary importó 25/25 elementos de Grants.gov como
borradores. Ni el E2E autenticado remoto ni el restore se ejecutaron.

- [Evidencia del release, canary APM, rollback y pendientes](../docs/runbooks/phase12b-release-2026-09-06.md).
- [Activación del importador, correcciones, canary y rollback](../docs/runbooks/import-worker-dev-2026-09-07.md).
- [Observabilidad: despliegue, privacidad y verificación](../docs/runbooks/observability.md).
- [Alertas dev: activación, costo y pausa de sondas](../docs/runbooks/operational-alerts-dev.md).
- [Restauración SQL: validación read-only y destino temporal](../docs/runbooks/database-restore.md).
- [E2E autenticado: cuenta, dominios y environment protegido](../frontend/funding-platform-web/README.md).

## Runbook reproducible para futuros `apply`

Para actualizar sólo una API existente, usar el workflow manual `api-dev.yml` con el SHA exacto de
`main` y `DEPLOY-DEV-API`. El script `deploy-api-dev.sh` usa los permisos actuales del Resource Group
y ACR; construye por SHA, publica por digest y aplica las tres variables de telemetría de la API.
Conserva su escala y verifica salud/SQL. No reaplica presupuesto, SQL, identidades ni Functions.
El procedimiento completo siguiente se reserva para cambios adicionales de infraestructura.

La secuencia siguiente conserva el procedimiento aprobado del primer despliegue y debe repetirse
para un cambio completo de infraestructura; no describe trabajo pendiente del ambiente ya publicado.

1. Revisar el costo con Azure Pricing Calculator. El presupuesto sólo alerta: no detiene recursos.
2. Ejecutar primero `validate` y `what-if`; guardar la salida para revisión.
3. Confirmar que los providers requeridos estén registrados. El script no los registra solo.
4. Verificar el grupo administrador SQL y la membresía del operador **antes** de `apply-base`.
5. Ejecutar `apply-base` indicando `expected_release_sha` igual al SHA aprobado; el workflow verifica
   después las 16 barreras de trigger y SCM/FTP. Luego usar `prepare-key-vault-dev.sh` para crear las tres claves sin
   sobrescribirlas y revocar el rol temporal exacto.
6. Con al menos 2 GiB libres, ejecutar `prepare-database-dev.sh`. El wrapper fija Staging, base y
   FQDN esperados, conexión Entra dev, PITR y firewall temporal con cleanup; ejecuta primero
   `--preflight`, aplica las pendientes, confirma `001`→`034` sin pendientes, corre los 34 smokes,
   verifica Full-Text listo,
   aprovisiona por `clientId`/SID los tres usuarios runtime y crea interactivamente el
   SuperAdmin. No usa Graph para crear principals SQL.
7. Ejecutar `apply` indicando `expected_release_sha` igual al SHA ya preparado; después verificar y
   reducir los permisos amplios JIT en la misma sesión. Email continúa apagado y la aplicación falla
   cerrada si falta una dependencia.
8. Ejecutar `frontend-dev.yml` para ese mismo SHA con confirmación `DEPLOY-DEV-FRONTEND`; su smoke
   prueba solamente el preview técnico público.
9. Configurar `app.<dominio>`/`api.<dominio>` antes de probar refresh cookies. Los hosts predeterminados
   de SWA y Container Apps sirven para smoke técnico, no para la topología final de sesión.

La secuencia operativa completa y los campos que prepararemos en la sesión de despliegue están en
[`DEV-DEPLOYMENT-CHECKLIST.md`](DEV-DEPLOYMENT-CHECKLIST.md).

El workflow de frontend no configura DNS ni habilita Functions, Defender, RSS, email, OpenAI o
billing.

## Evidencia del snapshot

Este bloque conserva el cierre local anterior a la creación de Azure dev; el estado operativo
posterior está documentado arriba.

Antes del push se observaron: Bicep `0.46.1` sin errores ni warnings, build Release `0` warnings/`0`
errors, Unit `411/411`, Integration `160/160`, tests focales de infraestructura `5/5`, parsing de
scripts/YAML y `git diff --check` limpios. `Infrastructure validation` remoto con la misma versión de
Bicep sigue siendo gate obligatorio del commit exacto. Los conteos/hashes manuales de plantillas no
se congelan en este documento porque se vuelven obsoletos con cada hardening.

En ese snapshot todavía no se había ejecutado `validate`, `what-if`, ACR build ni `apply` contra una
suscripción Azure.
