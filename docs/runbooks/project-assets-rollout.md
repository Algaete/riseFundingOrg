# Adjuntos de proyectos: validación y activación 036–039

Estado: implementación local. Azure dev continúa en `001`→`030`; este documento no acredita
un despliegue ni una prueba real de Defender o Azure SQL.

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
  no los descubre ni purga. Video sigue diferido.
- Para detener el flujo, deshabilitar primero la recepción/carga y los triggers correspondientes.
  No restaurar confianza en archivos revocados ni revertir migraciones publicadas con un `down`.

Los smokes `027`, `037` y `038` mantienen comprobaciones compatibles con la cadena completa:
el fingerprint de permisos original sigue validándose, más una lista explícita de los nuevos
procedimientos. No se modificaron las migraciones históricas ni sus checksums.
