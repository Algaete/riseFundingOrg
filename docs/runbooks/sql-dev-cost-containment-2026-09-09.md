# Contención de costos SQL en dev — 2026-09-09

## Alcance y autorización

El usuario autorizó detener temporalmente las importaciones en dev y comprobar
la pausa automática de SQL. No autorizó eliminar datos, cambiar el SKU SQL,
reducir respaldos ni apagar la web. La operación se realizó el 10 de septiembre
en UTC (noche del 9 de septiembre en Santiago).

Recursos afectados por el cambio:

- Grupo: `rg-rf-dev-ag26rf01`.
- Function App: `func-rf-dev-ag26rf01-general`.
- Base observada, sin cambios de configuración: `risefunding-dev`, servidor
  `sql-rf-dev-ag26rf01-centralus`.

## Diagnóstico previo

Los timers de importación consultaban SQL cada minuto y cada cinco minutos,
incluso cuando no había trabajo pendiente. La base serverless está configurada
con 0,5–1 vCore y 60 minutos de inactividad antes de pausarse. La última
reactivación registrada antes de la intervención era
`2026-09-06T23:56:47.940Z`; no aparecían pausas posteriores.

Cost Management, consultado antes de la intervención, mostró USD 33,742553 de
SQL en el mes: USD 32,060180 de cómputo y USD 1,682373 de almacenamiento. Los días
completos 7 y 8 de septiembre costaron aproximadamente USD 10,38 diarios. El uso
real de datos era de 136.970.240 bytes; no era un problema de volumen almacenado.
Los importes son una instantánea de facturación y pueden actualizarse con retraso.

## Cambio aplicado y verificado

Aproximadamente a las `2026-09-10T02:07Z`, se cambiaron únicamente estos tres
app settings de `false` a `true`:

```text
AzureWebJobs.ImportOutboxDispatcherFunction.Disabled=true
AzureWebJobs.ImportQueueFunction.Disabled=true
AzureWebJobs.ImportSchedulerFunction.Disabled=true
```

Se verificó mediante una segunda lectura de configuración que los 17
interruptores de funciones generales estaban deshabilitados. El inventario de
funciones del host también confirmó `isDisabled=true` para las 17 funciones.
No se cambió el SKU, el retraso de pausa, los respaldos ni la aplicación web.
No se borraron datos, mensajes, importaciones ni historial.

Las importaciones nuevas pueden quedar en cola mientras dure esta medida.
Los fondos existentes siguen disponibles; detener las importaciones no los
despublica. La navegación que consulta datos puede reactivar SQL y reiniciar
su período de inactividad.

## Comprobación de pausa

Al aplicar el cambio, SQL seguía `Online`. Se inició observación del estado por
Azure Resource Manager y de `sessions_count` y `app_cpu_percent` por Azure Monitor,
sin abrir conexiones SQL ni ejecutar pruebas contra endpoints de datos.

Estado de esta comprobación: **pausa automática confirmada**.

- Azure informó `status=Paused` en la lectura de `2026-09-10T03:09:28.140Z`.
- `pausedDate=2026-09-10T03:08:41.183Z` (00:08:41 de Santiago del 10 de septiembre).
- Una segunda lectura independiente a las `03:10:49Z` mantuvo `Paused`.
- Se verificaron de nuevo los tres interruptores de importación: todos en `true`.
- SQL conservó `autoPauseDelay=60`, `minCapacity=0.5` y capacidad máxima de 1 vCore.

Las métricas registraron cero ejecuciones del worker desde `2026-09-10T02:09Z`
y cero sesiones SQL / CPU de aplicación en los puntos de `02:10Z` y `02:11Z`.
Las muestras posteriores conservaron cero sesiones; hubo pequeñas variaciones
de CPU que no se atribuyeron a consultas de usuarios. Una comprobación agregada
entre `02:09Z` y `02:27Z` confirmó cero conexiones nuevas/fallidas, cero ejecuciones
del worker y cero solicitudes de la API. La evidencia de pausa es el estado
explícito de Azure, no una inferencia a partir de cero CPU o cero sesiones.

La primera lectura de `app_cpu_billed`, a las `03:10Z`, aún contenía cómputo
facturado en sus puntos publicados hasta `03:09Z`. No se interpretó esa lectura
como ahorro ya reflejado en Cost Management; las métricas/facturación pueden
actualizarse después del estado del recurso.

En la lectura de `03:12:44Z`, los puntos de `03:10Z` y `03:11Z` de
`app_cpu_billed` ya no traían un valor `total`. Se registran como ausencia de
muestra, no como ceros medidos. El estado `Paused` y las reglas de facturación
de Azure sustentan la detención del cómputo durante la pausa; no se ha afirmado
que el acumulado monetario del portal ya esté actualizado.

El monitor local terminó al confirmar la pausa. No queda una tarea de
supervisión permanente ni reactivación programada creada por esta intervención.

El cómputo no se cobra mientras SQL esté pausada, pero el almacenamiento y los
otros recursos de Azure siguen facturándose. El uso real puede reactivar SQL.
Referencias: [pausa y reactivación](https://learn.microsoft.com/en-us/azure/azure-sql/database/serverless-tier-auto-pause-resume?view=azuresql-db)
y [facturación serverless](https://learn.microsoft.com/en-us/azure/azure-sql/database/serverless-tier-billing?view=azuresql-db).

## Precaución para próximos despliegues

El Bicep ya declara estos tres interruptores deshabilitados por defecto.
En el momento de esta contención, `infra/scripts/release-general-worker-dev.sh` exigía que los tres
imports estén habilitados y abortará con esta contención activa; no los
rehabilita automáticamente. No cambiar los flags a `false` sólo para satisfacer
ese preflight: primero revisar el diseño de ejecución/costos y obtener
autorización para reanudar las importaciones.

Para revertir la contención se requiere autorización explícita y una ventana
controlada o una solución al sondeo permanente. Rehabilitar los tres triggers
sin ese cambio puede volver a impedir la pausa de SQL. El cambio posterior autorizado
de importaciones bajo demanda actualiza ese guard para preservar la cola y rechazar
timers activos; véase `on-demand-imports-dev.md`.
