# Evidencia de activación del importador dev — 2026-09-07

## Resultado

El worker general está publicado en `func-rf-dev-ag26rf01-general`. Sólo estas funciones están
habilitadas:

- `ImportOutboxDispatcherFunction`;
- `ImportQueueFunction`;
- `ImportSchedulerFunction`.

Las otras once funciones del host general conservan `AzureWebJobs.<Function>.Disabled=true`. La
Function App de extracción conserva sus dos triggers deshabilitados y no tiene paquete. No se
habilitaron correo, Defender/Event Grid, billing, IA ni retención.

El canary administrativo `8e813fce-6eaa-f111-a6a7-3833c5d78f35` consultó Grants.gov con la palabra
`nonprofit` y un máximo de 25 resultados. Terminó al primer intento con 25 recuperados, 24
borradores creados, uno sin cambios y cero fallos. Al cierre no había runs en cola/ejecución,
mensajes import pendientes ni items pendientes. Azure SQL contenía 25 borradores, cero fondos en
revisión y cero publicados. La API pública devolvió `totalCount=0`, confirmando que el importador no
publica automáticamente.

Los borradores se administran en
`https://salmon-glacier-0721afc0f.7.azurestaticapps.net/admin/funding`. El flujo deliberado es abrir
un fondo, completar o corregir sus campos, guardar, enviarlo a revisión y aprobar/publicar. Sólo
después aparece en `/funding` y en el feed autenticado `/opportunities`.

## Incidentes encontrados y correcciones

Las primeras corridas conservaron correctamente el contenido bruto pero fallaron al crear
borradores:

- `EA441FE5-4EAA-F111-A6A7-3833C5D78F35`, manual: 25 recuperados, fallo después de tres intentos;
- `9DBA0337-68AA-F111-A6A7-3833C5D78F35`, programada: 25 recuperados, fallo después de tres intentos;
- `C1E46F8C-6BAA-F111-A6A7-3833C5D78F35`, canary intermedio: creó un borrador y falló sobre los 24
  restantes después de tres intentos.

La causa inicial fue SQL 2628: Grants.gov entrega elegibilidad que puede superar los 2000
caracteres permitidos por la proyección `TargetOrganizationsDescription`. La migración `030` aplica
`LEFT(..., 2000)` únicamente a esa proyección y conserva completos la elegibilidad, requisitos y el
snapshot externo.

El siguiente elemento indicaba que requería aporte de contraparte sin entregar un porcentaje. El
modelo editorial no acepta `RequiresCofunding=true` sin porcentaje y no corresponde inventarlo. El
adaptador ahora deja el par canónico como desconocido para revisión humana y conserva la afirmación
original dentro de `SnapshotJson`.

## Validación y despliegue

- Migración `030`: preflight de una migración/un lote y 30 smokes con rollback; apply protegido por
  la comprobación PITR; 30 smokes posteriores con rollback.
- Pruebas focalizadas: 84/84. Suite unitaria completa: 506/506.
- Commit local desplegado: `93ad3574f5ba76347833608f100adfe9f58a8f35`.
- Paquete general: 92.853.761 bytes, 120 archivos, SHA-256
  `31625c15c5008699eed33e7b173c72ad7e694d215663fdca3c639eed5e529cb2`.
- One Deploy usó un blob privado con lectura SAS de corta duración. El contenedor temporal y la
  asignación temporal `Storage Blob Data Contributor` fueron eliminados y su ausencia fue
  verificada.
- El estado transitorio del plano de control quedó en `RuntimeStarting`, pero las comprobaciones
  independientes confirmaron cero instancias fallidas, inventario exacto de 14 funciones y
  telemetría `Worker process started and initialized`, `14 functions loaded` y `Job host started`.
  Durante el rollout apareció una advertencia transitoria de cliente Storage; los roles e identidad
  estaban completos, el arranque posterior no repitió la advertencia y el canary confirmó
  dispatcher, cola, SQL y staging de extremo a extremo.

## Rollback acotado

Para detener importaciones sin eliminar datos ni historial, cambiar únicamente estas tres variables
a `true` y verificar que las 14 barreras generales queden deshabilitadas:

```text
AzureWebJobs.ImportOutboxDispatcherFunction.Disabled
AzureWebJobs.ImportQueueFunction.Disabled
AzureWebJobs.ImportSchedulerFunction.Disabled
```

Los runs fallidos anteriores se conservan como auditoría y no se deben borrar. Los fondos importados
permanecen como borradores hasta una decisión editorial explícita.
