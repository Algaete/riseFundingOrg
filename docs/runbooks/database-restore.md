# Runbook: restauración PITR de Azure SQL en dev

## Objetivo y límites

Este procedimiento demuestra que `risefunding-dev` puede restaurarse a un punto en el tiempo
(PITR) sin modificar, renombrar ni reemplazar la base de origen. La restauración siempre crea una
base temporal nueva en el mismo servidor. El script no cambia la conexión de la aplicación y no
elimina ninguna base, ni siquiera ante error o interrupción.

El modo `validate` es el dry-run disponible: realiza únicamente lecturas de Azure, valida el ámbito,
la ventana PITR, la forma de costo y que el destino no exista. Azure CLI no ofrece un `what-if` para
`az sql db restore`; por eso sólo `execute`, después de una confirmación vinculada a todos los
parámetros, envía la creación.

La forma serverless limita el cómputo. El script además muestra `maxSizeBytes` y lo vincula a la
confirmación; PITR puede duplicar almacenamiento hasta ese máximo y el auto-pause no elimina su
costo. El repositorio no declara un límite de costo total del simulacro.

Evidencia del 2026-09-06: `validate` pasó contra Azure dev con origen `risefunding-dev` en estado
`Paused`, punto solicitado `2026-09-06T04:00:00Z`, destino temporal inexistente y máximo de origen
`34359738368` bytes (32 GiB). Se comprobó el formato de fecha UTC `+00:00` que entrega Azure CLI.
Sólo se hicieron lecturas; no se envió `execute` ni se creó una base restaurada. Revalidar siempre
el plan antes de ejecutarlo porque la ventana PITR avanza.

## Precondiciones

- Ventana de cambio aprobada para dev y responsable identificado.
- Azure CLI autenticado como operador autorizado en la suscripción y tenant esperados.
- El mismo `AZURE_UNIQUE_SUFFIX` de ocho caracteres usado por el ambiente existente.
- Un punto UTC posterior a `earliestRestoreDate` y anterior al momento actual. Para un simulacro,
  elegir un punto ya consolidado (por ejemplo, al menos 15 minutos atrás), no “ahora”.
- Capacidad para conservar temporalmente una segunda base `GP_S_Gen5_1`. La base restaurada tiene
  auto-pause a 60 minutos, pero puede generar costo mientras se valida.
- No ejecutar este runbook contra la base histórica `res`, otro Resource Group ni producción.

## 1. Preparar nombres inmutables

Trabajar desde un checkout confiable del repositorio. Definir los IDs explícitos en minúsculas y el
sufijo real de dev:

```bash
export AZURE_SUBSCRIPTION_ID='<uuid-suscripcion-en-minusculas>'
export AZURE_TENANT_ID='<uuid-tenant-en-minusculas>'
export AZURE_UNIQUE_SUFFIX='<8-caracteres>'
export RF_DEV_RESTORE_SOURCE_DATABASE='risefunding-dev'
```

Definir el punto de recuperación con segundos completos y sufijo `Z`:

```bash
export RF_DEV_RESTORE_POINT_UTC='YYYY-MM-DDTHH:MM:SSZ'
```

Reemplazar el marcador por un valor real dentro de la retención vigente; no copiar una fecha de un
simulacro anterior.

Crear una sola vez el nombre temporal. En macOS o Linux con OpenSSL:

```bash
export RF_DEV_RESTORE_DESTINATION="risefunding-dev-restore-${AZURE_UNIQUE_SUFFIX}-$(date -u +%Y%m%dt%H%M%Sz)-$(openssl rand -hex 2)"
printf '%s\n' "$RF_DEV_RESTORE_DESTINATION"
```

No regenerar ese nombre entre `validate`, `execute` y la captura de evidencia. El formato incluye el
sufijo del ambiente, instante UTC y nonce hexadecimal; el script además exige que no exista en el
servidor. Nunca usar `risefunding-dev` como destino.

## 2. Validar sin mutaciones

```bash
bash infra/scripts/restore-database-dev.sh validate
```

La validación debe confirmar, antes de mostrar el plan:

- suscripción y tenant exactos, ambos habilitados;
- Resource Group `rg-rf-dev-${AZURE_UNIQUE_SUFFIX}` con tags de la aplicación y ambiente;
- exactamente un servidor SQL con el nombre derivado de dev;
- origen exacto `risefunding-dev`, estado `Online` o `Paused` y forma
  `GP_S_Gen5_1|1|60|0.5|false|Local`;
- punto solicitado dentro de la ventana PITR;
- destino nuevo, temporal y todavía inexistente.

Guardar la salida del plan como evidencia. `validate` termina declarando que no envió un restore y
no cambió recursos. Si falla cualquier guard, corregir la entrada o escalar la discrepancia; no
debilitar el script.

## 3. Ejecutar la restauración

Copiar literalmente la frase que imprimió `validate`. Está ligada a suscripción, tenant, IDs
completos de origen/destino, punto UTC y máximo de almacenamiento. No reconstruirla desde variables que puedan haber cambiado:

```bash
export RF_DEV_RESTORE_CONFIRMATION='<pegar aquí la frase exacta impresa por validate>'
bash infra/scripts/restore-database-dev.sh execute
```

`execute` repite todos los guards y vuelve a comprobar que el destino no exista antes de enviar
`az sql db restore`. Espera el resultado sin `--no-wait` y verifica nombre, ID, estado `Online`, tags
temporales, redundancia local y límites serverless. También vuelve a leer el ID del origen.

Si la terminal se interrumpe, asumir que Azure puede continuar la operación. No volver a ejecutar a
ciegas: inspeccionar el destino exacto registrado. El script nunca intenta “limpiar” una operación
parcial porque eso podría borrar evidencia o una restauración válida.

## 4. Validar datos y registrar evidencia

La prueba no termina sólo con estado `Online`. Sin apuntar la API pública a la base restaurada:

1. Registrar suscripción, tenant, Resource Group, servidor, origen, destino, punto solicitado,
   `earliestRestoreDate`, hora inicial/final y resultado del script.
2. Acceder a la base temporal mediante el flujo administrativo de Microsoft Entra aprobado y una
   regla de red temporal gobernada; no incorporar credenciales SQL ni secretos al log.
3. Ejecutar verificaciones de sólo lectura: presencia de las 29 migraciones, conteos esperados de
   tablas críticas y una muestra funcional acordada anterior/posterior al punto. Registrar sólo
   conteos o hashes no sensibles, nunca datos personales de beneficiarios o usuarios.
4. Confirmar nuevamente que `risefunding-dev` conserva su ID y que la API sigue usando el origen.
5. Obtener aprobación del responsable sobre la evidencia y el RTO observado.

Una promoción o cambio de cadena de conexión no forma parte de este runbook. Si el restore debiera
usarse para recuperación real, diseñar un cambio separado, revisado y reversible; no renombrar ni
sobrescribir el origen durante este procedimiento.

## 5. Retención y limpieza separada

Conservar la base temporal hasta que la evidencia tenga aprobación explícita. Luego abrir una
operación destructiva separada que:

1. identifique por ID completo únicamente `${RF_DEV_RESTORE_DESTINATION}`;
2. vuelva a demostrar que no es `risefunding-dev` y que lleva los tags
   `purpose=pitr-restore-drill` y `temporary=true`;
3. obtenga una confirmación nueva y específica para eliminar ese ID;
4. elimine sólo la base temporal y verifique que el origen sigue presente.

Este repositorio no automatiza esa eliminación. No borrar el servidor SQL, el Resource Group, la
base de origen ni una base temporal cuyo resultado aún no haya sido aprobado.

## Evidencia mínima de cierre

- Salida exitosa de `validate` y frase exacta usada por `execute`.
- ID de origen antes/después e ID distinto del destino.
- Punto PITR, `earliestRestoreDate`, duración y estado final.
- Forma final `GP_S_Gen5_1|1|60|0.5|false|Local` y tags temporales.
- Resultado de verificaciones de datos sin contenido sensible.
- Aprobador, decisión de promoción o descarte, y ticket separado de limpieza cuando corresponda.
