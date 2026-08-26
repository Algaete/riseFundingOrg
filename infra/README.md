# Infraestructura Azure — FASE 12A

Este directorio prepara un ambiente `dev` separado mediante Bicep. Ninguna plantilla se ejecuta al
hacer push: `infra-dev.yml` sólo se inicia manualmente, usa OIDC y exige escribir `DEPLOY-DEV` para
la operación `apply`.

## Topología preparada

- Resource Group exclusivo y presupuesto mensual real con avisos al 50%, 80% y 100% previsto.
- API en Azure Container Apps Consumption: 0,5 vCPU, 1 GiB, máximo una réplica y mínimo configurable
  `1`/`0`; comienza en `1`.
- Azure Container Registry Basic privado, sin usuario administrador ni credenciales de registro; la
  UAMI de la API recibe solamente `AcrPull`.
- React en Static Web Apps Free y dos Function Apps Flex Consumption con escala a cero.
- Azure SQL General Purpose serverless, 1 vCore máximo, 0,5 mínimo y auto-pausa a 60 minutos.
- Log Analytics/Application Insights, Key Vault RBAC y clave rotatoria de Data Protection.
- Storage documental, Storage de colas y un host Storage distinto por Function App.
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

Los probes de plataforma usan `/health`, que no consulta SQL. `/health/ready` queda para una prueba
operacional explícita, evitando que el probe mantenga despierta la base serverless.

## Escala y costo

El workflow pregunta `api_min_replicas`:

- `1`: mantiene una réplica tibia al comenzar el ambiente dev;
- `0`: permite escala a cero cuando no hay tráfico; una solicitud pública puede volver a activarla.

El máximo permanece en una réplica. Cambiar a `0` requiere ejecutar de nuevo `what-if` y `apply` con
esa opción para conservar el estado en Bicep. ACR Basic tiene costo fijo diario aunque la API esté en
cero; Container Apps cobra consumo y el mínimo `1` puede consumir la franquicia gratuita. El importe
real depende de región, contrato y moneda de la suscripción y se revisa antes de `apply`.

## Validación local

```bash
bicep build infra/main.bicep --stdout >/dev/null
bash -n infra/scripts/deploy-dev.sh
docker build -f src/FundingPlatform.Api/Dockerfile -t rise-funding-api:local .
```

El workflow `Infrastructure validation` compila con Bicep `0.46.1` sin iniciar sesión en Azure y
construye la imagen sin publicarla. El workflow manual comprueba Container Apps, ACR, Static Web Apps,
Functions Flex y `dotnet-isolated` 10.0 en la región antes de `validate`, `what-if` o `apply`.

## Variables del environment GitHub `dev`

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`: identidad de despliegue OIDC;
- `AZURE_LOCATION`: región validada;
- `AZURE_UNIQUE_SUFFIX`: 4–8 caracteres `[a-z0-9]`;
- `AZURE_SQL_ADMIN_LOGIN`, `AZURE_SQL_ADMIN_OBJECT_ID`: grupo Entra administrador;
- `AZURE_BUDGET_EMAIL`, `AZURE_BUDGET_START_DATE`, `AZURE_MONTHLY_BUDGET_AMOUNT` (moneda de
  facturación de la suscripción, no una divisa asumida por el repositorio);
- `AZURE_DEPLOY_COMPUTE`: `true` para incluir API/frontend/Functions.

El mínimo de la API se elige en cada ejecución manual. Estos identificadores no son credenciales. La
identidad OIDC se federa al subject `repo:Algaete/riseFundingOrg:environment:dev`; además de desplegar
la base y sus RBAC, necesita ejecutar ACR Tasks/build. No se usan publish profiles, passwords de ACR
ni client secrets.

## Condiciones antes del primer `apply`

1. Revisar el costo con Azure Pricing Calculator. El presupuesto sólo alerta: no detiene recursos.
2. Ejecutar primero `validate` y `what-if`; guardar la salida para revisión.
3. Confirmar que los providers requeridos estén registrados. El script no los registra solo.
4. Ejecutar `apply-base`, crear los secretos criptográficos/email y usuarios SQL, y sólo entonces
   ejecutar `apply`; la aplicación falla cerrada si falta una dependencia.
5. Aplicar `019`→`026`, probar los 26 smokes, provisionar Full-Text y crear usuarios SQL Entra con
   permisos exactos. La identidad de migración nunca se adjunta a las aplicaciones.
6. Configurar `app.<dominio>`/`api.<dominio>` antes de probar refresh cookies. Los hosts predeterminados
   de SWA y Container Apps sirven para smoke técnico, no para la topología final de sesión.

Por diseño, este cierre no aprovisiona Azure, no aplica SQL, no configura DNS y no habilita Defender,
RSS, email, OpenAI ni billing.

## Evidencia local

Gate local del cierre Container Apps:

- Bicep `0.46.1`, `bash -n`, YAML de ambos workflows y `git diff --check`: correctos;
- solución .NET Release: `0` warnings / `0` errors; Unit `377/377` e Integration `156/156`;
- frontend: lint, `25` archivos / `111` tests y build correctos;
- publicación Release del API y build Docker local: correctos; imagen ejecutable como UID `1654`,
  puerto `8080`, digest local `sha256:37ab6036b08866e9931697027ba42158b4ad08aec3c55827c66c691a2259f7c5`;
- `infra/main.bicep`: 119 líneas, SHA-256
  `4c07b40679831b90567d1a4ae949a64c243ea1da02478a86f861e1e6674af3ac`;
- `infra/modules/environment.bicep`: 419 líneas, SHA-256
  `ec07f78415edb0fe22feadf4977f45082ed96801011d079cc1418083011ea045`;
- `infra/modules/container-api.bicep`: 127 líneas, SHA-256
  `3f42039b991b1d3c122857f0e89deccb58dd9a1075404c8b2254256cb56e3085`;
- `src/FundingPlatform.Api/Dockerfile`: 27 líneas, SHA-256
  `f4a71fcf64af26db423438741a2090f7565bdfa933008ddfe2a6bb027a7f3ea9`.

No se ha ejecutado `validate`, `what-if`, ACR build ni `apply` contra una suscripción Azure.
