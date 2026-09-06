# Runbook: observabilidad segura en Azure dev

## Alcance

La API y los dos procesos Functions usan OpenTelemetry y exportan a la instancia workspace-based de
Application Insights creada por Bicep. La API usa JSON en consola sólo sin exportación APM (local/tests);
en Azure envía los logs de aplicación por OpenTelemetry para evitar doble ingesta. Los workers no
reintroducen `ConsoleLoggerProvider`, que Azure Functions retira para evitar duplicados, y retransmiten
sus propiedades Serilog a los providers oficiales/OpenTelemetry. Los identificadores W3C
`traceId`/`spanId` permiten unir solicitudes, dependencias y logs; el `correlationId` continúa siendo
un identificador funcional separado que el cliente puede enviar de forma validada.

La instrumentación de los workers no autoriza publicar sus paquetes ni habilitar triggers. Esos dos
cambios siguen siendo operaciones independientes: un ZIP nuevo debe permanecer inerte mientras las
16 app settings `AzureWebJobs.*.Disabled` sean `true`.

Referencias de implementación:

- [Azure Functions .NET isolated y OpenTelemetry](https://learn.microsoft.com/azure/azure-functions/dotnet-isolated-process-guide#application-insights)
- [Azure Monitor OpenTelemetry para .NET](https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-enable?tabs=aspnetcore)
- [Configuración, muestreo y redacción](https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-configuration)

## Controles obligatorios

- Application Insights tiene `DisableLocalAuth: true`; API y workers exportan con la UAMI explícita
  y el rol `Monitoring Metrics Publisher`, nunca con instrumentation key como credencial.
- Fuera de desarrollo, la API rechaza el arranque sin connection string y la UAMI de runtime. Cada
  worker además exige `APPLICATIONINSIGHTS_CLIENT_ID`, que debe ser la identidad de su host.
- `OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION=false` y
  `OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION=false` son obligatorios. El proceso
  aborta si se configuró telemetría y cualquiera falta o vale otra cosa. Esto protege códigos OAuth,
  tokens de baja, SAS y cualquier otro valor de query.
- No capturar cuerpos, cookies, encabezados de autorización, tokens, emails, nombres, texto de PDFs
  ni parámetros SQL. Los logs de negocio deben usar IDs públicos/operacionales o conteos.
- La instrumentación automática no registra eventos de excepción completos y excluye `/health` de
  trazas de entrada. El detalle HTTP público sigue siendo `ProblemDetails` sin stack trace.
- Los procesadores propios se registran antes del exporter. Los spans conservan plantillas de ruta
  en las entradas y sólo el origen en las URLs salientes; eliminan query, fragmentos, texto SQL y
  descripciones de error. Los logs de excepción conservan un mensaje constante y el tipo original,
  sin el mensaje, inner exception, stack trace ni atributos originales. Los logs normales limitan
  las propiedades exportadas y no incluyen scopes ni mensajes formateados con valores sin filtrar.
- El host de Functions tiene un pipeline independiente: los procesadores del worker no filtran los
  eventos del host. Verificar ambos en un canary antes de publicar/habilitar Functions; las pruebas
  de privacidad locales no equivalen a evidencia de privacidad del host alojado.

## Límites de costo y volumen

- Muestreo rate-limited: objetivo de `1.0` traza por segundo por instancia/pipeline. Los hosts
  Functions reciben `OTEL_TRACES_SAMPLER=microsoft.rate_limited` y `OTEL_TRACES_SAMPLER_ARG=1.0`,
  alineados con el worker. Una decisión heredada del padre puede prevalecer; no es un techo global
  de la aplicación ni un límite de gasto o volumen de logs/métricas.
- Live Metrics desactivado.
- Log Analytics conserva 30 días y la API/workers mantienen sus límites de escala de dev.
- Salud se excluye del APM de entrada; una prueba externa de disponibilidad debe tener frecuencia
  baja y no incluir query strings.

No elevar muestreo, retención o nivel de logs durante un incidente sin registrar responsable, hora
de expiración y costo estimado. La alerta presupuestaria no detiene la ingesta.

## Secuencia de despliegue

1. Fusionar únicamente un SHA con build, tests, validación Bicep y auditoría de dependencias verdes.
2. Para una API ya aprovisionada, ejecutar `api-dev.yml` con `DEPLOY-DEV-API` y ese SHA exacto.
   Usa los permisos existentes de Resource Group/ACR, construye la imagen y actualiza únicamente
   su digest y las tres variables OTel declaradas en Bicep. No requiere roles de suscripción.
3. El workflow comprueba el digest y ejecuta `verify-dev.sh api`, conservando el mínimo de réplicas
   anterior. Registrar además la revisión previa para rollback y verificar la ingesta APM real.
4. Confirmar trazas de API antes de crear alertas. No publicar Functions hasta completar Defender,
   Event Grid, Storage/CORS y el gate operativo específico de cada trigger.

Cuando se necesite aplicar infraestructura adicional, `infra-dev.yml` sigue siendo una operación
separada con `validate`/`what-if` y los permisos correspondientes. `apply-base` omite la API; puede
aplicar las variables del host de Functions, pero no las de API. El release acotado de API no
aplica las variables nuevas de los hosts ni publica sus paquetes.

## Verificación sin datos sensibles

En Logs de Application Insights/Log Analytics, acotar siempre por tiempo. Ejemplos:

```kusto
AppRequests
| where TimeGenerated > ago(15m)
| project TimeGenerated, Name, ResultCode, DurationMs, OperationId
| order by TimeGenerated desc
```

```kusto
union AppTraces, AppExceptions
| where TimeGenerated > ago(15m)
| summarize Events=count() by Type, SeverityLevel, bin(TimeGenerated, 5m)
```

Comprobar en una solicitud controlada:

1. `OperationId` coincide con el `traceId` W3C expuesto en `ProblemDetails` cuando hay error.
2. La URL no contiene query; las entradas usan plantillas de ruta y las salidas sólo el origen.
3. No aparecen `Authorization`, cookies, refresh tokens, contenido documental ni datos personales.
4. Las trazas de `/health` no dominan el volumen.
5. `AppRoleName` distingue API, worker general y worker de extracción en las tablas del workspace.

Si cualquiera falla, volver al digest anterior de la API o mantener los workers sin paquete. No
“corregir” el síntoma habilitando local auth ni desactivando la redacción.

## Alertas mínimas antes del piloto

Crear las reglas sólo después de observar una línea base real y confirmar el destinatario:

- disponibilidad externa de `/health` desde al menos dos ubicaciones;
- solicitudes API 5xx y tasa de fallos sostenida;
- excepciones no controladas por `AppRoleName`;
- backlog/edad de `imports` y `document-extractions`;
- runs/jobs atascados según sus watchdogs;
- presupuesto 50/80/100 ya definido.

Cada regla debe tener severidad, ventana, umbral, action group, runbook y responsable. Probar el
action group con una notificación controlada y registrar acuse; crear recursos de alerta no basta
para declarar el gate completo.

## Respuesta y rollback

Para un aumento de 5xx, filtrar primero por `OperationId`, revisión de Container Apps y ventana de
despliegue. Si coincide con el último digest, ejecutar el rollback gobernado y repetir salud/SQL.
Para ruido o costo de telemetría, reducir nivel/muestreo mediante un cambio revisado; nunca borrar
el workspace como mitigación. Para fallos de worker, deshabilitar el trigger exacto y preservar cola,
poison messages y evidencia antes de reintentar.
