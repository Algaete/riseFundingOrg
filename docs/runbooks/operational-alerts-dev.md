# Alertas operativas de Azure dev

Este bloque está versionado pero **no está desplegado**. `deployOperationalAlerts=false` es el valor
predeterminado y, mientras se conserve, Bicep no crea el Action Group, la prueba sintética ni las
reglas. Ninguna validación local de este runbook llama Azure o envía correo.

## Qué crea el opt-in

Una ejecución de infraestructura explícita con `deploy_operational_alerts=true` crea, con nombres
deterministas para el ambiente:

- un Action Group con el mismo correo secreto ya usado por el presupuesto, usando el esquema común
  de alertas y sin webhooks, SMS ni teléfonos;
- una prueba estándar que hace solamente `HTTPS GET /health`, exige `200`, valida TLS y avisa cuando
  queda menos de siete días de certificado;
- una alerta de disponibilidad por una ubicación fallida;
- una alerta agregada cuando `AppRequests` registra al menos un `5xx` de
  `AppRoleName == "FundingPlatform.Api"` en cinco minutos;
- una alerta agregada cuando `AppExceptions` registra al menos una excepción del mismo rol en cinco
  minutos.

Las consultas sólo entregan un conteo. No incluyen URL, usuario, mensaje, stack trace ni propiedades
del evento en la carga de la alerta.

## Límites deliberados de dev

- La prueba se ejecuta cada 15 minutos desde **una** ubicación y tiene timeout de 30 segundos. Con
  éxito son 96 ejecuciones al día; los reintentos ocurren sólo ante falla. Microsoft recomienda más
  ubicaciones para una señal de producción, por lo que esta configuración económica no representa
  un SLO multi-región. Es sólo el perfil dev: antes de abrir el piloto se deben aprobar y versionar
  al menos **dos ubicaciones independientes**, ajustar `failedLocationCount` y recalcular el costo,
  como exige el runbook general de observabilidad. Mientras eso no ocurra, la disponibilidad del
  piloto sigue siendo un gate pendiente.
- Las dos consultas se evalúan cada cinco minutos, miran cinco minutos, se auto-resuelven y silencian
  acciones durante 30 minutos para evitar una tormenta de correo.
- El workspace conserva datos durante 30 días y continúa cubierto por el presupuesto mensual del
  Resource Group. Revisar el precio vigente de pruebas estándar, reglas de consulta e ingesta en el
  `what-if`/calculador antes de activar.
- `/health` no se exporta como traza del API, así que la prueba no duplica telemetría de request. Sí
  puede despertar una Container App con escala a cero cada 15 minutos.

Referencias oficiales: [pruebas de disponibilidad de Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/availability),
[recurso Bicep de pruebas estándar](https://learn.microsoft.com/azure/templates/microsoft.insights/2022-06-15/webtests),
[alertas métricas](https://learn.microsoft.com/azure/templates/microsoft.insights/2026-01-01/metricalerts),
[reglas de consulta](https://learn.microsoft.com/azure/templates/microsoft.insights/2023-12-01/scheduledqueryrules),
[Action Groups](https://learn.microsoft.com/azure/templates/microsoft.insights/2023-01-01/actiongroups),
[`AppRequests`](https://learn.microsoft.com/azure/azure-monitor/reference/tables/apprequests) y
[`AppExceptions`](https://learn.microsoft.com/azure/azure-monitor/reference/tables/appexceptions).

## Activación controlada

Antes de activar, confirmar que el API ya existe, tiene ingress HTTPS abierto, `/health` responde
`200`, `OTEL_SERVICE_NAME=FundingPlatform.Api` y la telemetría real aparece en `AppRequests`. Validar
también que el pipeline de excepciones alimenta `AppExceptions`; no agregar un endpoint que falle ni
forzar errores con datos reales sólo para probar la regla.

1. Ejecutar `what-if` desde `main`, con el SHA aprobado y
   `deploy_operational_alerts=true`. Revisar que sólo se agregan el Action Group, una prueba y tres
   reglas, además de cualquier cambio ya esperado del release.
2. Revisar costo, correo receptor, período de mantenimiento y efecto de la sonda sobre escala a cero.
   Para el piloto, detenerse si el template todavía conserva una sola ubicación.
3. Ejecutar `apply-base`/`DEPLOY-DEV-BASE` o `apply`/`DEPLOY-DEV` con el mismo SHA y el opt-in en
   `true`. Sólo una operación `apply*` crea recursos y puede iniciar pruebas/correos.
4. Esperar una ejecución natural saludable y confirmar el resultado en Application Insights. Las
   reglas de `5xx` y excepción se validan con telemetría sanitizada de una prueba funcional aprobada
   en staging o con un evento real, nunca introduciendo una ruta de fallo en producción.

`deployOperationalAlerts=false` es una barrera de **creación**, no un teardown: ARM incremental no
elimina recursos creados anteriormente. Antes de pausar/cerrar ingress o durante mantenimiento,
deshabilitar explícitamente la prueba y las tres reglas mediante un cambio operativo revisado; de lo
contrario la prueba puede despertar el API o notificar la pausa como caída.

## Backlog y jobs atascados

No se crean todavía alertas de backlog ni jobs atascados. Las Functions siguen sin publicar y todos
sus triggers permanecen deshabilitados, por lo que hoy no existe una línea base de carga ni una señal
end-to-end confiable. Umbrales arbitrarios producirían falsos positivos o esconderían fallas.

Después de autorizar/publicar los workers, recopilar al menos siete días representativos y definir:

- backlog: profundidad, edad del mensaje más antiguo, tasa de llegada/proceso y poison queue, con
  umbral ligado al tiempo operativo comprometido;
- jobs: estados terminales/no terminales, heartbeat y duración p95/p99 por tipo, sin IDs, payloads ni
  contenido de ONG en dimensiones;
- ventanas de mantenimiento, runbook, dueño, severidad y máximo de notificaciones.

Sólo entonces agregar reglas Bicep con consultas agregadas, `what-if`, presupuesto y una validación
controlada. Esta postergación no modifica ni habilita ninguno de los 16 flags de Functions.
