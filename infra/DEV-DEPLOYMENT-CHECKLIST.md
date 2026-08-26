# Checklist del primer despliegue `dev`

Este checklist prepara una sesión de despliegue reproducible. No contiene secretos y ningún push a
`main` crea recursos: las operaciones con costo son manuales desde el environment GitHub `dev`.

## 1. Datos que deben estar decididos

- Suscripción y tenant correctos.
- Región que pase el preflight del script.
- Sufijo único de exactamente 8 caracteres `[a-z0-9]`. Después del primer `apply-base` es inmutable: cambiarlo
  crearía otro ambiente con costo.
- Grupo Entra que administrará Azure SQL y su Object ID.
- Correo, monto y primer día UTC del presupuesto mensual.
- Réplica mínima inicial del API: `1`; después puede cambiarse a `0`.

No usar la base histórica `res`: Bicep crea `risefunding-dev` dentro del Resource Group dev.

## 2. Confianza GitHub → Azure

1. Crear una identidad de despliegue separada de todas las identidades runtime.
2. Agregar una credencial federada para GitHub Actions con:
   - issuer `https://token.actions.githubusercontent.com`;
   - organización `Algaete`;
   - repositorio `riseFundingOrg`;
   - entity type `Environment`;
   - environment `dev`;
   - audience `api://AzureADTokenExchange`.
3. Durante el bootstrap, otorgarle temporalmente `Contributor` y
   `Role Based Access Control Administrator` sobre la suscripción elegida. El paso 13 los reduce y
   verifica antes de cerrar la sesión.
4. No crear client secret, publish profile ni credenciales de ACR.

Como este repositorio fue creado después de la adopción de subjects inmutables de GitHub, el subject
exacto es:

```text
repo:Algaete@51843665/riseFundingOrg@1344044015:environment:dev
```

Confirmarlo al crear la FIC y eliminar cualquier credencial federada mutable o adicional. Restringir
el environment `dev` exclusivamente a `main` y exigir un reviewer cuando el plan de GitHub lo
permita. Proteger `main` con PR, checks `CI` e `Infrastructure validation`, y bloquear force-push y
eliminación; el guard del workflow complementa esas políticas, no las reemplaza.

## 3. Environment GitHub `dev`

Crear `Settings → Environments → dev`, aplicar la protección anterior y registrar como **variables**:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
AZURE_LOCATION
AZURE_UNIQUE_SUFFIX
AZURE_SQL_ADMIN_LOGIN
AZURE_SQL_ADMIN_OBJECT_ID
AZURE_BUDGET_START_DATE
AZURE_MONTHLY_BUDGET_AMOUNT
AZURE_DEPLOY_COMPUTE=true
```

Registrar `AZURE_BUDGET_EMAIL` como **environment secret** para evitar publicar PII en metadata o
logs. Los tres IDs y el Object ID no son secretos. No guardar claves, passwords ni connection
strings en GitHub.

## 4. Preflight del propietario de la suscripción

Registrar una sola vez los providers que el script verifica y deliberadamente no registra:

```bash
for namespace in Microsoft.Resources Microsoft.Authorization Microsoft.Consumption Microsoft.ManagedIdentity Microsoft.Storage Microsoft.KeyVault Microsoft.Sql Microsoft.Web Microsoft.App Microsoft.ContainerRegistry Microsoft.Insights Microsoft.OperationalInsights; do
  az provider register --namespace "$namespace" --wait
done
```

## 5. Secuencia sin saltos

1. Congelar el checkout que se desplegará. No mezclar ni aceptar cambios en `main` durante la sesión:

   ```bash
   git fetch origin main
   test "$(git branch --show-current)" = main
   test -z "$(git status --porcelain --untracked-files=normal)"
   test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
   export RF_DEV_RELEASE_SHA="$(git rev-parse HEAD)"
   test "${#RF_DEV_RELEASE_SHA}" -eq 40
   ```

   Confirmar CI e `Infrastructure validation` verdes para ese SHA.
2. Antes de crear Azure SQL, autenticar el Mac y validar la cuenta, el grupo administrador y la
   membresía efectiva del operador. Estos valores deben coincidir con las variables del environment
   GitHub `dev`:

   ```bash
   export RF_DEV_SUBSCRIPTION_ID='<subscription-id>'
   export RF_DEV_TENANT_ID='<tenant-id>'
   export RF_DEV_SUFFIX='<sufijo8>'
   export RF_DEV_DEPLOYER_CLIENT_ID='<oidc-app-client-id>'
   export RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID='<object-id-grupo-sql>'
   export RF_DEV_SQL_ADMIN_GROUP_NAME='<display-name-exacto-grupo-sql>'
   az login --tenant "$RF_DEV_TENANT_ID"
   az account set --subscription "$RF_DEV_SUBSCRIPTION_ID"
   test "$(az account show --query id --output tsv)" = "$RF_DEV_SUBSCRIPTION_ID"
   test "$(az account show --query tenantId --output tsv)" = "$RF_DEV_TENANT_ID"
   test "$(az ad group show --group "$RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID" --query displayName --output tsv)" = "$RF_DEV_SQL_ADMIN_GROUP_NAME"
   OPERATOR_OBJECT_ID="$(az ad signed-in-user show --query id --output tsv)"
   test "$(az ad group member check --group "$RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID" --member-id "$OPERATOR_OBJECT_ID" --query value --output tsv)" = true
   ```
3. Ejecutar `infra-dev.yml` con `validate`.
4. Ejecutar `what-if`, guardar la salida y revisar tipos, región, nombres y presupuesto.
5. Ejecutar `apply-base`, confirmación `DEPLOY-DEV-BASE`, réplica `1`.
6. Ejecutar localmente
   `AZURE_SUBSCRIPTION_ID=<id> AZURE_TENANT_ID=<id> AZURE_UNIQUE_SUFFIX=<sufijo8> bash infra/scripts/verify-dev.sh base`.
7. Obtener el Object ID del principal OIDC y darle `AcrPull` sobre el ACR dev. `Contributor` permite
   el quick build durante bootstrap; cuando se reduzca ese permiso, conservar explícitamente
   `Container Registry Tasks Contributor`.

   ```bash
   [[ "$RF_DEV_SUBSCRIPTION_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "RF_DEV_SUBSCRIPTION_ID is invalid" >&2; exit 1; }
   [[ "$RF_DEV_TENANT_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "RF_DEV_TENANT_ID is invalid" >&2; exit 1; }
   [[ "$RF_DEV_SUFFIX" =~ ^[a-z0-9]{8}$ ]] || { echo "RF_DEV_SUFFIX must be exactly 8 lowercase letters or digits" >&2; exit 1; }
   [[ "$RF_DEV_DEPLOYER_CLIENT_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "RF_DEV_DEPLOYER_CLIENT_ID is invalid" >&2; exit 1; }
   [[ "$(az account show --query id --output tsv)" == "$RF_DEV_SUBSCRIPTION_ID" ]] || { echo "Wrong Azure subscription" >&2; exit 1; }
   [[ "$(az account show --query tenantId --output tsv)" == "$RF_DEV_TENANT_ID" ]] || { echo "Wrong Azure tenant" >&2; exit 1; }
   export RF_DEV_RG="rg-rf-dev-${RF_DEV_SUFFIX}"
   DEPLOYER_OBJECT_ID="$(az ad sp show --id "$RF_DEV_DEPLOYER_CLIENT_ID" --query id --output tsv)"
   ACR_ID="$(az acr list --resource-group "$RF_DEV_RG" --query '[0].id' --output tsv)"
   az role assignment create --assignee-object-id "$DEPLOYER_OBJECT_ID" --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID"
   ```
8. Crear en Key Vault las tres claves criptográficas requeridas:
   - `Authentication--Jwt--SigningKey`: Base64 de al menos 64 bytes aleatorios;
   - `Authentication--SecurityHash--IpHashPepper`: Base64 de 32 bytes aleatorios;
   - `Authentication--SecurityHash--RecoveryCodePepper`: Base64 de 32 bytes aleatorios.
   El helper aborta si alguna ya existe, genera archivos temporales con permisos restrictivos, no
   imprime valores y crea/revoca/verifica por ID exacto el rol temporal `Key Vault Secrets Officer`:

   ```bash
   AZURE_SUBSCRIPTION_ID="$RF_DEV_SUBSCRIPTION_ID" \
   AZURE_TENANT_ID="$RF_DEV_TENANT_ID" \
   AZURE_UNIQUE_SUFFIX="$RF_DEV_SUFFIX" \
   bash infra/scripts/prepare-key-vault-dev.sh
   ```

   Si el helper informa `PARTIAL KEY VAULT BOOTSTRAP`, detener la sesión: no reintentar ni
   sobrescribir. Revisar sólo los nombres/versiones creados y reconciliar la rotación de las tres
   claves como una operación controlada antes de continuar.
9. Con al menos 2 GiB libres y una terminal interactiva, preparar la base y SuperAdmin mediante el
   único wrapper autorizado. El SHA debe ser el mismo que luego se escribirá en
   `expected_release_sha` para `apply`:

   ```bash
   export AZURE_SUBSCRIPTION_ID="$RF_DEV_SUBSCRIPTION_ID"
   export AZURE_TENANT_ID="$RF_DEV_TENANT_ID"
   export AZURE_UNIQUE_SUFFIX="$RF_DEV_SUFFIX"
   test "$RF_DEV_RELEASE_SHA" = "$(git rev-parse HEAD)"
   export RF_DEV_ADMIN_EMAIL='<superadmin-dev@example.org>'
   export RF_DEV_ADMIN_DISPLAY_NAME='Administrador dev'
   bash infra/scripts/prepare-database-dev.sh
   ```

   El script hace `git fetch`, exige `main` limpio e idéntico a `origin/main`, valida grupo/miembro y
   el administrador efectivo del servidor SQL, deriva la conexión dev, registra PITR, abre una regla
   firewall única con cleanup verificado, aplica `001`→`028`, ejecuta los 28 smokes, espera Full-Text
   listo y prueba reapply/provisioning idempotente. Después crea por `clientId`/SID y verifica los
   principals de la tabla siguiente, confirma las dos ausencias y solicita la contraseña SuperAdmin
   sin argumento ni pipe.

   | Principal | Resultado SQL que verifica el wrapper |
   |---|---|
   | UAMI API | `FundingPlatform_ApiRuntimeRole` |
   | `H_general` | `FundingPlatform_GeneralWorkerRole` |
   | consumer `C` | `FundingPlatform_ExtractionWorkerRole` |
   | `H_extractor` y sender `S` | sin usuario SQL |
10. Ejecutar `apply`, confirmación `DEPLOY-DEV`, réplica `1` y
    `expected_release_sha=$RF_DEV_RELEASE_SHA`. El workflow rechaza otro commit, construye la imagen
    en ACR y despliega el API por digest OCI.
11. Ejecutar
    `AZURE_SUBSCRIPTION_ID=<id> AZURE_TENANT_ID=<id> AZURE_UNIQUE_SUFFIX=<sufijo8> AZURE_API_MIN_REPLICAS=1 bash infra/scripts/verify-dev.sh api`.
12. No publicar todavía Functions: el host general está diseñado para fallar cerrado mientras
    Defender/Event Grid permanezca deshabilitado. Frontend, dominios y publicación de Functions son
    el siguiente gate de FASE 12B.
13. Antes de cerrar la sesión, reducir obligatoriamente el principal OIDC: conservar `Contributor`
    sólo en `rg-rf-dev-<sufijo8>`, `Container Registry Tasks Contributor` + `AcrPull` sólo en el ACR y
    quitar `Contributor`/`Role Based Access Control Administrator` de la suscripción. Un futuro
    `validate`/`what-if`/`apply` completo requiere elevación JIT aprobada y revocada en la misma
    sesión; `scale-api` funciona con el permiso estable del Resource Group.

    ```bash
    set -euo pipefail
    RG_ID="$(az group show --name "$RF_DEV_RG" --query id --output tsv)"
    SUBSCRIPTION_SCOPE="/subscriptions/${RF_DEV_SUBSCRIPTION_ID}"
    az role assignment create --assignee-object-id "$DEPLOYER_OBJECT_ID" --assignee-principal-type ServicePrincipal --role Contributor --scope "$RG_ID"
    az role assignment create --assignee-object-id "$DEPLOYER_OBJECT_ID" --assignee-principal-type ServicePrincipal --role "Container Registry Tasks Contributor" --scope "$ACR_ID"
    az role assignment create --assignee-object-id "$DEPLOYER_OBJECT_ID" --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID"
    test "$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$RG_ID" --query "[?roleDefinitionName=='Contributor'] | length(@)" --output tsv)" = 1
    test "$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$ACR_ID" --query "[?roleDefinitionName=='Container Registry Tasks Contributor'] | length(@)" --output tsv)" = 1
    test "$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$ACR_ID" --query "[?roleDefinitionName=='AcrPull'] | length(@)" --output tsv)" = 1
    test "$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$SUBSCRIPTION_SCOPE" --query "[?roleDefinitionName=='Contributor'] | length(@)" --output tsv)" = 1
    test "$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$SUBSCRIPTION_SCOPE" --query "[?roleDefinitionName=='Role Based Access Control Administrator'] | length(@)" --output tsv)" = 1
    SUB_CONTRIBUTOR_ID="$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$SUBSCRIPTION_SCOPE" --query "[?roleDefinitionName=='Contributor'].id | [0]" --output tsv)"
    SUB_RBAC_ADMIN_ID="$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$SUBSCRIPTION_SCOPE" --query "[?roleDefinitionName=='Role Based Access Control Administrator'].id | [0]" --output tsv)"
    az role assignment delete --ids "$SUB_CONTRIBUTOR_ID"
    az role assignment delete --ids "$SUB_RBAC_ADMIN_ID"
    test "$(az role assignment list --assignee-object-id "$DEPLOYER_OBJECT_ID" --scope "$SUBSCRIPTION_SCOPE" --query "[?roleDefinitionName=='Contributor' || roleDefinitionName=='Role Based Access Control Administrator'] | length(@)" --output tsv)" = 0
    ```

En 12A `Email__Enabled=false`: la API arranca sin Azure Communication Services, pero registro,
reenvío de verificación y recuperación de contraseña responden `503` antes de escribir en SQL. El
smoke de mañana es técnico (`/health` y bootstrap administrativo); email, SSO, navegador y sesiones
cross-site esperan ACS y dominios de 12B.

## 6. Evidencia y recuperación

Si `apply-base` falla después de crear sólo parte de los recursos, conservar exactamente el mismo
`AZURE_UNIQUE_SUFFIX`, revisar las operaciones del deployment, corregir la causa y reaplicar
`apply-base`. No cambiar el sufijo ni borrar recursos o el Resource Group a ciegas: hacerlo crearía
otro ambiente, puede duplicar costo y destruye la ruta idempotente de recuperación.

Después de un smoke saludable, guardar el digest OCI desplegado y el nombre de la revisión de
Container Apps. En despliegues posteriores, capturar esos dos datos **antes** del cambio: el rollback
de API crea una nueva revisión apuntando explícitamente al digest saludable anterior, nunca a
`latest` ni a una reconstrucción. Corregir Bicep y reaplicar; no borrar el Resource Group.

Las migraciones SQL son forward-only: ante un defecto se hace fix-forward. Si se necesita recuperar
datos, usar PITR hacia **otra** base, validar y promover con un cambio controlado; no ejecutar scripts
down ni prometer que ARM deshace datos. Registrar `earliestRestoreDate` antes de mutar.

## 7. Reducir consumo al terminar

- `scale-api` + `SCALE-DEV-API` + réplica `0` permite escala a cero, pero mantiene el ingress público:
  una petición puede despertar el API. No reconstruye la imagen y el máximo sigue en `1`.
- `pause-api` + `PAUSE-DEV-API` pone mínimo `0` **y cierra el ingress**. Es la pausa preferida cuando
  nadie usa dev. No ejecutar probes mientras esté pausado.
- `resume-api` + `RESUME-DEV-API` reabre el ingress con el mínimo `0`/`1` seleccionado.
- Todo `apply` vuelve a declarar el ingress activo mediante Bicep. Si el ambiente debe quedar
  pausado después, ejecutar nuevamente `pause-api`.
- `rollback-api` + `ROLLBACK-DEV-API` exige el digest `sha256:...` saludable guardado, no usa
  `latest` ni reconstruye. Se ejecuta con ingress activo; si estaba pausado, reanudar primero y
  volver a pausar después de verificar.

El input por defecto queda en `0` para que una ejecución posterior no reactive accidentalmente una
réplica caliente. ACR Basic, Storage, Log Analytics y SQL conservan sus costos propios. Después de
`pause-api`, desconectar clientes y esperar 70–75 minutos; hacer **una sola** consulta de estado a la
base y esperar `Paused`:

```bash
az sql db show --resource-group "$RF_DEV_RG" --server '<sql-server-name>' --name risefunding-dev --query status --output tsv
```

`AZURE_DEPLOY_COMPUTE=false` no es una pausa: ARM incremental no elimina ni detiene recursos ya
creados. No agregar app settings manuales a Functions; un futuro apply reemplaza esa colección y
12B debe versionarla completa en IaC.

No borrar el Resource Group como mecanismo cotidiano de pausa: contiene la base, identidades y
almacenamiento. Si se decide eliminarlo, primero exportar evidencia, confirmar backup/restauración y
tratarlo como una operación destructiva separada.
