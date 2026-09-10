# Importaciones bajo demanda en Azure dev

## Objetivo y límites

Reemplazar los sondeos SQL periódicos de importaciones por activación desde la cola
`imports` existente. SQL serverless puede volver a pausarse cuando no hay actividad;
no se cambia el tamaño, los datos ni los siete días de recuperación PITR. Las
operaciones de Storage, el almacenamiento SQL y las consultas reales siguen teniendo
su costo: no es una promesa de factura cero ni de pausa inmediata.

## Flujo

1. El administrador inicia una importación en la consola. Se conserva la validación
   de MFA, permisos SQL, límites de proveedor y la clave de idempotencia existente.
2. API guarda ejecución y outbox, envía `{runId, version:1}` a Storage Queue y solo
   entonces devuelve 202. No se crean colas ni se consultan sus mensajes desde API.
3. El QueueTrigger confirma la recepción para esa ejecución y usa el procesador
   existente. Los límites de intentos, exclusión por lease, deduplicación y revisión
   editorial siguen vigentes. No publica fondos automáticamente.
4. Si SQL indica reintento pendiente o lease vigente, se deja otro mensaje con
   visibilidad diferida. Se envía antes de terminar la entrega actual. Un fallo del
   envío o caída del worker conserva el reintento nativo del host (31 minutos,
   máximo 5 entregas antes de `imports-poison`). No hay bucle de sondeo ni espera
   activa. Los reintentos normales mantienen el máximo de intentos del run.
5. Al terminar no se envían más mensajes. Los temporizadores quedan deshabilitados
   y, además, `ImportWorkers__OnDemandOnly=true` evita que consulten SQL incluso si
   se habilitasen por error. Los calendarios de fuentes se conservan pero son inertes.

La escritura SQL y el envío a Storage no son una transacción distribuida: un corte
entre ambos conserva la ejecución, pero exige repetir la misma solicitud o usar
**Reenviar a la cola** en su detalle. El error confirmado de envío es HTTP 503
`import-queue-unavailable`, no 202. La recuperación no crea otro run ni reinicia sus
intentos. Los estados terminales no vuelven a procesarse. Si un mensaje alcanza
`imports-poison`, diagnosticar la causa antes de reenviar; no vaciar colas ni borrar
historial para recuperarlo. Los mensajes tienen una retención de siete días.

Las pantallas de importaciones limitan el refresco automático a cinco minutos y no
refrescan al recuperar foco. **Actualizar estado** abre otra ventana acotada. Cerrar
la pantalla o agotar esa ventana no cancela el trabajo.

## Despliegue acotado y verificaciones

Destino: suscripción `3ff82cd2-ffe5-4196-bc0f-547a0cc099cf`, grupo
`rg-rf-dev-ag26rf01`; API `ca-rf-dev-ag26rf01-api`; worker
`func-rf-dev-ag26rf01-general`; SQL `sql-rf-dev-ag26rf01-centralus/risefunding-dev`.

1. Mantener los tres triggers de importaciones deshabilitados durante la publicación.
   Comprobar que la cola `imports` no contiene trabajos anteriores; no purgarla. Si
   contiene trabajos, revisar y resolver explícitamente el alcance antes de activarla.
2. Usar SHA exacto de main y CI aprobado. `check-dev-database.sh --release` comprueba
   PITR, aplica preflight con rollback, migración 047, segundo apply sin pendientes
   y todos los smokes. El permiso nuevo de ejecución es solo para
   `FundingPlatform_GeneralWorkerRole`; API no recibe ese permiso ni permisos de tabla.
3. Publicar el paquete general verificado con `release-general-worker-dev.sh`, que
   conserva el flag inicial de la cola y rechaza temporizadores SQL habilitados.
   No publicar ni habilitar extracción, adjuntos, Defender, correo, billing o IA.
4. Conceder a la identidad API `id-rf-dev-ag26rf01-api` únicamente **Storage Queue
   Data Message Sender**, rol `c6a89b2d-59bc-44d0-9896-0f6e12d7b80a`, con alcance
   `/storageAccounts/stfuncrfdevag26rf01gendi/queueServices/default/queues/imports`.
   El worker reutiliza sus permisos anteriores. No usar claves de almacenamiento.
5. Establecer en API `ImportDispatch__Enabled=true`,
   `ImportDispatch__QueueServiceUri=https://stfuncrfdevag26rf01gendi.queue.core.windows.net`
   y `ImportDispatch__ManagedIdentityClientId` igual al clientId verificado de su
   identidad. `UseDevelopmentStorage` no se permite fuera de Development local.
6. Publicar API y frontend por sus workflows dev. Habilitar exclusivamente
   `AzureWebJobs.ImportQueueFunction.Disabled=false` y mantener
   `ImportWorkers__OnDemandOnly=true`. Los otros 16 triggers generales y ambos de
   extracción permanecen deshabilitados. El perfil `on-demand-imports` verifica
   esa frontera y la configuración API; el perfil foundation sigue siendo inerte.
7. Probar una importación manual acotada; comprobar resultado y ausencia de publicación
   automática. Después, no realizar health checks SQL periódicos: observar el estado
   de pausa mediante el plano de control de Azure, sin abrir conexiones SQL.

Bicep declara el permiso mínimo y los nombres de configuración, pero deja
`ImportDispatch__Enabled=false` y los triggers deshabilitados por defecto. El despliegue
de infraestructura inicial no activa este módulo; una futura reaplicación de foundation
exige revisar la activación. El release de código API conserva el resto de configuración.

## Detener o revertir

Deshabilitar `ImportDispatch__Enabled` en API y el QueueTrigger; mantener ambos timers
deshabilitados y el guard OnDemandOnly verdadero. No revertir la migración ni borrar
ejecuciones, outbox o mensajes. La versión anterior depende del dispatcher SQL:
no rehabilitarlo para resolver un incidente sin revisar el costo y pedir autorización.

## Evidencia previa a publicación

El 10 de septiembre de 2026, el contador de Storage devolvió cero mensajes en `imports`
con HTTP 200; esta comprobación no consultó SQL. La contención y la pausa confirmada
anterior están en `sql-dev-cost-containment-2026-09-09.md`. Registrar por separado el
SHA publicado, las validaciones SQL y el resultado real de Azure; este documento
describe el procedimiento y no constituye evidencia de despliegue completado.
