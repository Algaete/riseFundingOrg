# Aceptación funcional: importar, revisar y aparecer en el catálogo

Fecha local: 2026-09-10 (America/Santiago). Comprobaciones Azure realizadas el
2026-09-11 entre 00:45 y 00:49 UTC. Estado: **aceptación parcial; recorrido
autenticado parcialmente confirmado por el usuario**. Las pruebas locales no acreditan operaciones reales con
la cuenta del usuario.

## Alcance y comprobaciones realizadas

- Frontend dev: `https://salmon-glacier-0721afc0f.7.azurestaticapps.net`.
- `deploy-meta.json` devuelve el commit
  `3776b0a7448229e099958494f92494db8a2ac218`, workflow `34438325507`.
- API: revisión más reciente y lista `ca-rf-dev-ag26rf01-api--0000005`, imagen
  `sha256:060146a2b8f2b47f83ec6580d02abe803772da8391ba567aa49db630eaf2a149`.
- SQL dev: el plano de control devolvió `Paused`, autopausa de 60 minutos y
  `pausedDate=2026-09-10T23:16:25.003000+00:00`. Esta observación sí es posterior
  al despliegue bajo demanda. No se abrió una conexión SQL para comprobarlo.
- Worker general: de los 17 flags de funciones consultados, únicamente
  `ImportQueueFunction` tiene `Disabled=false`. `ImportWorkers__OnDemandOnly=true`;
  ambos temporizadores de importaciones permanecen deshabilitados.
- API: `ImportDispatch__Enabled=true`.
- Posteriormente se hizo una sola lectura de
  `GET /api/v1/funding-discovery?page=1&pageSize=1`: HTTP 200, 2006 ms y
  `totalCount=0`, a las `2026-09-11T00:48:31.057Z`. La lectura puede reactivar SQL.
  No se atribuye ese tiempo exclusivamente a su reanudación ni se afirma que la
  base siguiera pausada entre ambas comprobaciones. No hubo sondeo recurrente.
- El resultado vacío acredita que la consulta respondió, no que una publicación
  haya sido probada. No informa cuántos borradores privados existen.

No se modificaron configuraciones Azure, cuentas, permisos, fuentes ni fondos.
No se publicaron datos ficticios ni se activaron servicios adicionales.

## Regresión local de este recorrido

| Capa | Selección ejecutada | Resultado |
| --- | --- | --- |
| .NET | OnDemandImportTests, ImportRunProcessingServiceTests, FundingEditorialServiceTests, ExternalFundingOpportunityStagingTests, GrantsGovProviderTests | 94 aprobadas, 0 fallidas, 0 omitidas |
| HTTP local | ImportRunEndpointTests, FundingEditorialEndpointTests, FundingDiscoveryEndpointTests | 55 aprobadas, 0 fallidas, 0 omitidas |
| Interfaz local | admin-import-pages, admin-import-api, admin-editorial, editorial-language, editorial-messages | 48 aprobadas en 5 archivos |

Total: 197 pruebas focalizadas aprobadas. Incluyen persistencia antes de encolar,
reenvío idempotente, permisos/MFA, errores editoriales por datos incompletos y
separación entre importación y publicación. Usan dobles de prueba; no sustituyen
una entrega real de Storage Queue ni la revisión con una cuenta de Azure dev.

## Evidencia aportada por el usuario

Tras solicitar la prueba, el usuario compartió el resultado del ítem con ID externo
`363846`: «Completado · created · 10-09-2026, 10:15 p. m.», «Dedupe: Sin evaluación
de duplicidad» y «Requiere decisión editorial; no está publicado».

Esto confirma por evidencia del usuario que un ítem llegó a creación y revisión
editorial sin autopublicarse. `363846` es el identificador externo de Grants.gov
mostrado en la lista, no el GUID del run ni el GUID interno de la oportunidad.
No se dispone todavía del estado global/contadores del run ni de su ficha privada.
«Sin evaluación de duplicidad» no acredita ausencia de duplicados.

La consulta pública a la API oficial de Grants.gov identificó el programa
`USDA-NIFA-HSI-011903`, **Hispanic-Serving Institutions Education Grants Program**.
Su [ficha oficial](https://simpler.grants.gov/opportunity/575f8146-88ca-42c7-abeb-6f9ae5549bdc)
declara NIFA como financiador, cierre el 3 de diciembre de 2026 y ayudas de
USD 25.000 a USD 1.200.000. La admisión está restringida a instituciones HSI,
no a cualquier ONG. Esta consulta no reemplaza revisar las bases ni comparar los
campos efectivamente guardados en FundingPlatform antes de aprobarlos.

Siguiente acción: abrir **Abrir candidato** en ese ítem y revisar su ficha y panel
**Flujo editorial**. No cambiar la elegibilidad ni aprobar para hacer pasar la prueba.

### Revisión de las capturas y envío a revisión

El usuario mostró la oportunidad en el listado administrativo y en su editor,
con ID interno `e512d837-7ead-f111-a6a7-000d3a912199`. Se observó estado Borrador,
nombre/financiador, cierre 03-12-2026 y rango USD 25.000–1.200.000 coincidentes
con la ficha oficial. La captura no acredita una revisión completa de elegibilidad.

Después de pulsar **Enviar a revisión**, el estado siguió en Borrador y la interfaz
mostró cuatro mensajes: integridad de catálogos, categoría obligatoria, financiador
principal publicado y alcance geográfico conocido. Se confirma el bloqueo editorial
visible, no un nuevo fallo de la cola. No se observó el código HTTP de esa solicitud.
El mensaje genérico de catálogos no prueba que la moneda esté incorrecta: requiere
comprobar los valores concretos y puede coexistir con los requisitos específicos.

La acción **Corregir financiador y alcance** apunta a `#financiadores-alcance`,
que contiene Financiadores asociados, Alcance geográfico, Países elegibles y
Categorías. La revisión del código confirma que el texto Organismo patrocinador
no sustituye el vínculo a un financiador principal publicado. No seleccionar Global
ni inventar países elegibles para eludir el bloqueo.

Se observaron además dos problemas de claridad que quedan registrados, no corregidos:
la cabecera del aviso concatena los mismos mensajes que vuelve a enumerar debajo;
Calidad 100/100 puede confundirse con preparación editorial completa. No se retiraron
las validaciones ni se cambió la clasificación del registro real.

### Reporte posterior: Guardar no responde — corrección local

El usuario informó que no se guardan los cambios y compartió una excepción
`VM272:2`, `reportAllChanges`, lectura de `startTime` sobre `undefined`. No se ha
relacionado esa traza con una petición de guardado. La búsqueda del identificador
`reportAllChanges` no lo encontró en el código ni en el bundle local del frontend;
esto no demuestra que una extensión sea la causa ni permite descartar el reporte.

Se reprodujo otro defecto concreto del formulario: un rechazo de validación local
podía quedar sin un resumen visible junto a Guardar; los errores anidados de los
financiadores tampoco se mostraban mediante la lectura anterior de `.message`.
Se agregó un resumen accesible ES/EN que recibe el foco y permite ir al campo
afectado. Conserva las categorías elegidas y no expone diagnósticos desconocidos.
No se relajaron las validaciones ni se alteraron elegibilidad o registros reales.

Regresión local: 960 pruebas aprobadas en 78 archivos, lint sin incidencias y build
aprobado. Incluye dos reproducciones que fallaron antes de la corrección, recuperación
tras corregir un campo y guardado de categorías en un borrador importado sintético
con alcance desconocido. El caso válido ya funcionaba antes de este cambio, por lo
que no acredita haber resuelto el problema del registro real `363846`.

La corrección está solo en el árbol de trabajo: sin commit ni despliegue en Azure.
La herramienta de navegador volvió a confirmar que no hay sesión disponible; no
se inspeccionaron credenciales ni se intentó eludir la autenticación. Quedan
pendientes desplegar la mejora, identificar el campo o respuesta que bloquea el
registro del usuario y confirmar la persistencia mediante una nueva lectura.

## Recorrido y comprobaciones restantes

1. Con cuenta administradora y MFA vigente, abrir `/admin/imports`, seleccionar
   Grants.gov, palabra `education` y máximo **1**. Iniciar una sola ejecución y
   registrar su ID, estado final, contadores y código seguro de error si lo hubiera.
   Cero coincidencias no es un fallo técnico, pero tampoco permite probar el paso 2.
2. Comprobar la oportunidad vinculada, su fuente oficial y estado editorial.
   Una importación no debe publicarla automáticamente. Una coincidencia ya existente
   puede quedar sin cambios; no forzar duplicados para conseguir un borrador nuevo.
3. Revisar los datos contra la fuente oficial. Los errores del reporte original
   exigen financiador principal publicado, catálogos activos y alcance geográfico
   coherente. No completar campos por suposición ni eliminar esas validaciones.
4. Enviar a revisión y aprobar únicamente un fondo real revisado que el responsable
   quiera mostrar en el entorno dev. No usar aprobación de contenido real como
   fixture sintético. Registrar el ID y el resultado de cada transición.
5. Verificar su ficha y búsqueda pública sin sesión y, por separado, el feed de
   oportunidades con una cuenta normal. Distinguir publicado de públicamente
   visible, filtros aplicados y caché pública de hasta 60 segundos.

Si queda en cola o falla, conservar el ID y diagnosticar esa ejecución antes de
reenviar. No crear importaciones repetidas, vaciar colas, reiniciar intentos ni
rehabilitar temporizadores para conseguir que la prueba pase.

## Bloqueo de la sesión

La habilidad de navegador se cargó y su diagnóstico confirmó que no hay ningún
navegador disponible (`agent.browsers.list()` devolvió `[]`). No se inspeccionaron
cookies, contraseñas ni archivos de sesión; tampoco se crearon tokens de usuario.
Se solicitó al usuario iniciar la prueba de máximo 1 y compartir su ID o captura,
sin aprobar/publicar todavía. Ya se recibió la evidencia del ítem descrita arriba;
la revisión de la ficha privada, aprobación y visibilidad pública siguen pendientes.
No se marcaron como probadas operaciones que no se observaron.

El siguiente trabajo tras este recorrido es cerrar las ampliaciones de mapa,
búsqueda unificada y matching identificadas en la revisión de requerimientos.
La activación de adjuntos o nuevas fuentes requiere su validación independiente.
