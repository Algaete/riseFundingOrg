# Infraestructura Azure — FASE 12A

Este directorio prepara un ambiente `dev` separado mediante Bicep. Ninguna plantilla se ejecuta al
hacer push: `infra-dev.yml` sólo se inicia manualmente, usa OIDC y exige escribir `DEPLOY-DEV` para
la operación `apply`.

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
AZURE_SUBSCRIPTION_ID=<id> AZURE_TENANT_ID=<id> AZURE_UNIQUE_SUFFIX=<sufijo8> bash infra/scripts/verify-dev.sh base
AZURE_SUBSCRIPTION_ID=<id> AZURE_TENANT_ID=<id> AZURE_UNIQUE_SUFFIX=<sufijo8> AZURE_API_MIN_REPLICAS=1 bash infra/scripts/verify-dev.sh api
```

El workflow `Infrastructure validation` compila con Bicep `0.46.1` sin iniciar sesión en Azure y
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

## Estado operativo de la base dev — 2026-08-27

La base `risefunding-dev` tiene aplicadas `001`→`028`. El preflight conjunto validó la cadena local
de 29 migraciones/355 lotes y los 29 smokes con rollback total; la corrección `029` todavía no fue
aplicada. Full-Text, principals runtime y bootstrap SuperAdmin siguen pendientes; por eso todavía no
corresponde ejecutar el apply de compute.

## Condiciones antes del primer `apply`

1. Revisar el costo con Azure Pricing Calculator. El presupuesto sólo alerta: no detiene recursos.
2. Ejecutar primero `validate` y `what-if`; guardar la salida para revisión.
3. Confirmar que los providers requeridos estén registrados. El script no los registra solo.
4. Verificar el grupo administrador SQL y la membresía del operador **antes** de `apply-base`.
5. Ejecutar `apply-base`; luego usar `prepare-key-vault-dev.sh` para crear las tres claves sin
   sobrescribirlas y revocar el rol temporal exacto.
6. Con al menos 2 GiB libres, ejecutar `prepare-database-dev.sh`. El wrapper fija Staging, base y
   FQDN esperados, conexión Entra dev, PITR y firewall temporal con cleanup; ejecuta primero
   `--preflight`, aplica la pendiente `029` sobre `001`→`028`, corre los 29 smokes, estabiliza
   Full-Text, aprovisiona por `clientId`/SID los tres usuarios runtime y crea interactivamente el
   SuperAdmin. No usa Graph para crear principals SQL.
7. Ejecutar `apply` indicando `expected_release_sha` igual al SHA ya preparado; después verificar y
   reducir los permisos amplios JIT en la misma sesión. Email continúa apagado y la aplicación falla
   cerrada si falta una dependencia.
8. Configurar `app.<dominio>`/`api.<dominio>` antes de probar refresh cookies. Los hosts predeterminados
   de SWA y Container Apps sirven para smoke técnico, no para la topología final de sesión.

La secuencia operativa completa y los campos que prepararemos en la sesión de despliegue están en
[`DEV-DEPLOYMENT-CHECKLIST.md`](DEV-DEPLOYMENT-CHECKLIST.md).

Por diseño, este cierre no aprovisiona Azure, no aplica SQL, no configura DNS y no habilita Defender,
RSS, email, OpenAI ni billing.

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
