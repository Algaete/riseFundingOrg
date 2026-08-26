# Infraestructura Azure — FASE 12A

Este directorio prepara un ambiente `dev` separado mediante Bicep. Ninguna plantilla se ejecuta al
hacer push: `infra-dev.yml` sólo se inicia manualmente, usa OIDC y exige escribir `DEPLOY-DEV` para
la operación `apply`.

## Topología preparada

- Resource Group exclusivo y presupuesto mensual real con avisos al 50%, 80% y 100% previsto.
- App Service Linux B1 para la API y Static Web Apps Free para React.
- dos Function Apps Flex Consumption, con máximo 10 instancias y escala a cero;
- Azure SQL General Purpose serverless, 1 vCore máximo, 0,5 mínimo y auto-pausa a 60 minutos;
- Log Analytics/Application Insights, Key Vault RBAC y clave rotatoria de Data Protection;
- Storage documental, Storage de colas y un host Storage distinto por Function App;
- cinco UAMI: API, `H_general`, `H_extractor`, sender `S` y consumer `C`.

La cola y el container de extracción tienen RBAC a nivel del recurso. Shared Key y acceso Blob
anónimo están deshabilitados. La regla SQL `0.0.0.0` permite servicios Azure solamente en dev; no es
la topología de producción y se reemplazará por red privada cuando las mediciones justifiquen el
costo.

## Validación local

```bash
bicep build infra/main.bicep --stdout >/dev/null
bash -n infra/scripts/deploy-dev.sh
```

El workflow `Infrastructure validation` compila con Bicep `0.46.1` sin iniciar sesión en Azure. El
workflow manual primero comprueba que la región ofrece Linux App Service .NET 10 y Functions Flex
`dotnet-isolated` 10.0; después ejecuta `validate` y, según la opción, `what-if` o `apply`.

## Variables del environment GitHub `dev`

- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`: identidad de despliegue OIDC;
- `AZURE_LOCATION`: región validada;
- `AZURE_UNIQUE_SUFFIX`: 4–8 caracteres `[a-z0-9]`;
- `AZURE_SQL_ADMIN_LOGIN`, `AZURE_SQL_ADMIN_OBJECT_ID`: grupo Entra administrador;
- `AZURE_BUDGET_EMAIL`, `AZURE_BUDGET_START_DATE`, `AZURE_MONTHLY_BUDGET_AMOUNT` (moneda de
  facturación de la suscripción, no una divisa asumida por el repositorio);
- `AZURE_DEPLOY_COMPUTE`: `true` para incluir API/frontend/Functions.

Estos identificadores no son credenciales, pero se mantienen por ambiente para no acoplar la
plantilla a una suscripción. La identidad OIDC debe estar federada al subject
`repo:Algaete/riseFundingOrg:environment:dev` y tener permisos limitados al despliegue de este
ambiente y al presupuesto. No se usan publish profiles ni client secrets.

## Condiciones antes del primer `apply`

1. Revisar el costo con Azure Pricing Calculator y conservar una alerta presupuestaria por debajo de
   los créditos disponibles. El tag/presupuesto no detiene recursos automáticamente.
2. Ejecutar primero `validate` y `what-if`; guardar la salida para revisión.
3. Confirmar disponibilidad real de .NET 10 en la región; el script falla si no existe.
4. Después de crear infraestructura, cargar secretos criptográficos en Key Vault fuera de logs.
5. Aplicar `019`→`026`, probar los 26 smokes, provisionar Full-Text y crear usuarios SQL Entra con
   permisos exactos. La identidad de migración nunca se adjunta a las aplicaciones.
6. Configurar dominio común `app.<dominio>`/`api.<dominio>` antes de probar refresh cookies. Los hosts
   predeterminados de SWA y App Service no sirven como topología final de sesión.
7. Desplegar paquetes sólo después de crear un workflow separado y revisar los outputs reales.

Por diseño, este cierre no aprovisiona Azure, no aplica SQL, no configura DNS y no habilita Defender,
RSS, email, OpenAI ni billing.

## Evidencia del cierre local

Bicep CLI 0.46.1 compiló y aplicó lint sin diagnósticos sobre los tres archivos (603 líneas). SHA-256:

- `main.bicep`: `d7d93185886066a099e7fb6b4c4bade5b9917e8c2bfc68e1a9f9e6c5fe820f23`;
- `environment.bicep`: `0988bce3406a71af7e9ea441f5c200b5ae15fef13328821edf3f47dd8ab03b1a`;
- `flex-function.bicep`: `e23c621097a178b478a5439ebb5d67c0a320559ce6b21ca7bd92a0197c8f8b5e`.

El gate local pasó build .NET con 0 warnings/errores, 376/376 unitarias, 156/156 de
integración, YAML y Bash sintácticamente válidos, frontend lint, 25 archivos/111 pruebas y build.
No se ejecutó la validación ARM remota porque eso requiere seleccionar la suscripción/región e
iniciar sesión explícitamente.
