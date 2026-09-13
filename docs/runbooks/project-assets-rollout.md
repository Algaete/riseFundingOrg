# Adjuntos de proyectos: validación y activación 036–039

## Pausa solicitada — 2026-09-12

El usuario **rechazó contratar/habilitar Defender** y después dejó el bloque completo
en stand by para avanzar con búsqueda unificada. El orden de cierre y los costos de
abajo son antecedentes técnicos, **no un plan aprobado para ejecutar ahora**.
No activar adjuntos, contratar sustitutos, habilitar un escáner simulado ni marcar
archivos no analizados como limpios. Se conserva el trabajo local sin desplegarlo.

## Estado revisado — 2026-09-11

**Activación pendiente.** Las migraciones hasta `047` y el código de adjuntos hasta
`046` ya se desplegaron en dev en releases anteriores. Esto no acredita escaneo real
ni disponibilidad de cargas. El corte histórico `036`–`039` de abajo conserva sus
resultados originales; no describe la versión actual de la base.

La revisión de este día usó únicamente lecturas del plano de control Azure, sin
conectarse a SQL ni leer archivos/cookies/cuentas de usuarios. No se ejecutó un
despliegue, no se contrataron servicios y no se modificó infraestructura:

- API: revisión lista `0000007`; sin configuración explícita de adjuntos, por lo que
  aplica el valor deshabilitado del código.
- Worker: `PROJECT_ASSETS_ENABLED=false` y los tres triggers de adjuntos apagados.
- Cuenta de documentos: HTTPS obligatorio, sin acceso público ni claves compartidas;
  versionado activo y soft delete de 14 días. Aún **no existen** los tres contenedores
  `fp-project-incoming`, `fp-project-quarantine` y `fp-project-trusted`.
- CORS de Blob vacío; lifecycle sólo para `fp-source-incoming/uploads/`. No habilita
  cargas desde el navegador ni limpieza de cargas de proyectos abandonadas.
- Defender para esa cuenta deshabilitado, escaneo apagado y límite heredado `-1`
  (sin límite). No hay topics Event Grid en el grupo consultado. No activar ese
  valor ilimitado ni habilitar Defender para toda la suscripción.
- SQL conserva min 0,5 / max 1 vCore y autopausa de 60 minutos. La lectura devolvió
  `Online`; no se afirma que estuviera pausado ni que esta revisión lo despertase.
- RBAC efectivo, confianza SQL de eventos y E2E real de archivos: **no acreditados**.

### Preparación local de esta revisión

El panel tiene ahora una sola secuencia de consultas, cada cinco segundos y por
un máximo de cinco minutos. No consulta automáticamente en pestañas ocultas, por
recuperación de foco ni por reconexión. La fecha límite no se extiende al recibir
respuestas o cambiar idioma. **Actualizar estado** abre otra ventana sin reenviar
el archivo; completar una carga también abre una ventana nueva. Cambiar de proyecto
descarta selección/intentos locales. Una petición ya en vuelo puede terminar, pero
su respuesta tardía no inicia otra secuencia después de pausar.

Se agregó `ProjectAssetMaintenance:AllowSqlPolling=false` como barrera independiente
de las importaciones. Los timers de watchdog (5 minutos) y retención (15 minutos)
retornan antes de consultar SQL si no hay opt-in. El arranque rechaza activar el
pipeline actual sin ese opt-in: **no se permite aparentar que hay mantenimiento
activo mientras se omiten sus tareas de seguridad**. Infraestructura y ejemplo local
mantienen el flag en `false`; no hubo cambio del worker desplegado.

Esto es una protección previa, **no la implementación del mantenimiento bajo demanda**.
Antes de habilitar los adjuntos en este dev, reemplazar ambos sondeos por trabajo
durable dirigido por eventos/colas. No cambiar `AllowSqlPolling` a `true` para
saltear este pendiente: la configuración bajo demanda del usuario sigue vigente.

Validación local: 971 pruebas frontend, 926 unitarias .NET y 328 HTTP aprobadas;
lint y build frontend aprobados. Son pruebas sintéticas, no E2E de Defender real.

### Costo consultado y rechazado — referencia histórica

Consulta a la [API oficial de precios para East US 2](https://prices.azure.com/api/retail/prices?%24filter=productName%20eq%20%27Microsoft%20Defender%20for%20Storage%27%20and%20armRegionName%20eq%20%27eastus2%27),
el 2026-09-11: `Standard Node` USD 0,0134/hora; `Malware Scanning Data Ingested`
USD 0,15/GB. La base estimada a 730 horas es USD 9,78/mes por cuenta. Son precios
retail sin impuestos/descuentos; Blob, Event Grid, Functions y SQL por uso son
adicionales. No se presupone una prueba gratuita ni se promete una factura total fija.

Proponer un límite inicial de escaneo de 1 GB/mes y excluir los contenedores ajenos
y las copias confiables para evitar escaneos duplicados; conservar el escaneo de la
cuarentena de proyectos. Validar los filtros contra fixtures antes de habilitar.
Microsoft documenta [hasta 20 GB de desviación del límite](https://learn.microsoft.com/en-us/azure/defender-for-cloud/on-upload-malware-scanning#cost-control-for-on-upload-malware-scanning):
**no es un tope monetario estricto**. Al agotarse el análisis, los archivos sin
resultado confiable deben seguir inaccesibles, nunca marcarse limpios.

### Orden de cierre si se retoma — requiere nueva decisión

1. Acordar una solución de escaneo y su costo: Defender fue rechazado. Cualquier
   alternativa requiere validar garantías, permisos y mantenimiento antes de habilitarla.
   No habilitar planes a nivel suscripción.
2. Implementar mantenimiento durable bajo demanda: notificar sólo trabajo real al
   completar/eliminar un adjunto o recibir su resultado. Programar vencimientos y
   reintentos finitos, sobrevivir caídas entre SQL y cola, y recuperar sin sondear SQL
   cuando no hay tareas. Conservar las identidades exactas/leases de retención.
3. Aprovisionar únicamente los contenedores privados, CORS/lifecycle específicos y
   recursos de eventos/escaneo aprobados. No reaplicar todo `environment.bicep`:
   podría revertir configuración de sesión, importaciones y otras diferencias de dev.
4. Validar RBAC/identidad, filtros de escaneo, confianza de eventos y los gates de
   seguridad detallados más abajo; incluir archivos limpios, rechazos y resultados
   tardíos, aislamiento entre organizaciones y recuperación de retención.
5. Publicar código probado; activar backend/eventos y frontend al final. Conservar
   los temporizadores SQL apagados y registrar el release y las pruebas reales.

## Evidencia histórica local 036–039

Verificación local de este corte: 755 pruebas unitarias y 212 de integración aprobadas, sin
omisiones; compilación Bicep y sintaxis del verificador shell aprobadas. Las pruebas SQL de `039`
y los smokes revisados pasaron ScriptDom, pero no se ejecutaron contra un motor SQL.

## Componentes

| Módulo | Responsabilidad |
| --- | --- |
| 036 | Carga privada, cuotas, cuarentena, metadatos, portada y permisos por organización |
| 037 | Recepción Defender idempotente, watchdog y revocación tardía |
| 038 | Sanitización de imágenes y manifiesto de cada copia confiable |
| 039 | Retiro exacto de contenido eliminado/revocado, con lease e historial de intentos |

La API no ejecuta retención. El worker general dispone sólo de tres procedimientos de retención;
las tablas y la vista de candidatos no tienen permisos runtime directos. El timer
`ProjectAssetContentRetentionFunction` permanece deshabilitado en infraestructura y además exige
`ProjectAssets:Enabled=true`. Los valores iniciales son lote 25 y lease de 900 segundos.

## Gates antes de activar

1. Confirmar el destino Azure dev y su ventana PITR, registrar versión y revisar `031`→`039`.
   Ejecutar primero el preflight SQL transaccional completo. Deben pasar todos los smokes, con
   rollback. El parsing ScriptDom local no sustituye esta ejecución.
2. Aplicar las migraciones y repetir el migrador para comprobar que no quedan pendientes.
   Publicar la API nueva en todo el tráfico antes del frontend: las guardas de `034`/`035`
   protegen los nuevos perfiles frente a snapshots generados por API antigua.
3. Validar containers privados, RBAC mínimo, CORS del origen exacto y lifecycle de `incoming`.
   Publicar el worker Linux con Skia y revisar que los triggers sigan apagados.
4. Provisionar y validar Defender/Event Grid y su identidad, trust policy y receipts. Confirmar
   costes y configuración del servicio antes de activarlo; no sustituir el scan real por el fake.
5. Ejecutar E2E limpio, rechazado y tardío sobre fixtures de prueba aislados. Verificar carga,
   sanitización, ausencia de EXIF, acceso privado, portada y bloqueo de publicación mientras
   exista cualquier adjunto activo no confiable. Comprobar aislamiento entre organizaciones.
6. Ejecutar retención sobre fixtures elegibles: borrado lógico con gracia de 24 horas, cuarentena
   terminal con gracia y copia revocada sin gracia. Confirmar la indisponibilidad lógica del
   actual y de su versión exacta y el registro `completed` con fecha en SQL.
7. Probar reintento tras borrar Blob pero antes de completar SQL, expiración/reclamación del lease,
   límite de ocho intentos y rechazo de ETag/versión/hash/metadatos divergentes. Comprobar que
   el adjunto activo y otros blobs no fueron alterados. Un snapshot no identificado debe bloquear
   el borrado, no provocar una eliminación ampliada.
8. Activar backend y workers sólo después de esos gates; habilitar
   `VITE_PROJECT_ASSETS_ENABLED` al final. Registrar revisión, flags, resultados y responsables.

## Límites y operación

- `ContentDeletedAtUtc` en retención significa que no se puede leer la materialización reclamada,
  no que Azure haya purgado físicamente sus bytes. Soft delete y sus ventanas siguen vigentes.
- El historial durable conserva identidad y resultado de cada intento. Los logs del timer sólo
  incluyen contadores, sin nombres originales, rutas Blob, SAS ni contenido.
- Un conflicto de identidad es terminal; no se corrige ampliando permisos ni borrando por prefijo.
  Investigar la causa y documentar cualquier reparación con un procedimiento controlado.
- Si el worker pierde el lease después del borrado, SQL no lo da por completado: el siguiente
  intento vuelve a verificar ausencia y completa bajo su propio lease.
- `incoming` abandonado corresponde al lifecycle ya declarado. Promociones huérfanas sin un
  manifiesto persistido y snapshots no identificados requieren una política específica; `039`
  no los descubre ni purga. `046` añade MP4/TXT privados; ver
  [contrato multimedia](../PROJECT-PRIVATE-MULTIMEDIA.md). No habilita reproducción pública.
- Para detener el flujo, deshabilitar primero la recepción/carga y los triggers correspondientes.
  No restaurar confianza en archivos revocados ni revertir migraciones publicadas con un `down`.

Los smokes `027`, `037` y `038` mantienen comprobaciones compatibles con la cadena completa:
el fingerprint de permisos original sigue validándose, más una lista explícita de los nuevos
procedimientos. No se modificaron las migraciones históricas ni sus checksums.
