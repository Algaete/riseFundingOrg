# Bloque 2: proyecto enriquecido

Estado: implementado localmente; pendiente de ejecutar SQL y desplegar en Azure.
Este bloque extiende la ficha del proyecto, no implementa todavía el mapa, el directorio
profesional ni la gestión de consorcios.

## Contrato y módulos

`ProjectEnrichment` es una extensión tipada del agregado de proyecto. Tiene reglas propias
en `ProjectEnrichmentRules`, contrato HTTP y mapeador explícito. El formulario y la ficha
de lectura son componentes separados (`project-enrichment-fields.tsx` y
`project-enrichment-summary.tsx`); reutilizan los recursos ES/EN y formatos existentes.

Todos los campos nuevos son opcionales. Solo se exigen datos dependientes cuando se elige
usarlos: nombre/unidad de un indicador, ambas coordenadas o la localidad que se decide publicar.
No se cambian la completitud ni los requisitos de publicación existentes.

| Campo dentro de `enrichment` | Regla |
| --- | --- |
| `problem`, `solution` | Texto independiente, máximo 3000 caracteres cada uno. No se deduce automáticamente de la descripción anterior. |
| `beneficiaryCount` | Entero entre 0 y 2147483647; `null` significa no informado. No confundir con los tipos de beneficiarios. |
| `impactIndicators` | Hasta 20 objetos: `name` (200), `unit` (80), `baseline` y `target` opcionales. Nombre/unidad obligatorios si se agrega una fila. |
| `baseline`, `target` | Números entre −10¹² y 10¹². Se permiten negativos y metas inferiores a la línea base (p. ej. emisiones). No se agrega una cifra de avance real no solicitada. |
| `locality` | Texto hasta 200 caracteres. No sustituye los países/regiones catalogados. |
| `latitude`, `longitude` | Ambas o ninguna, límites ±90/±180. Se acepta 0; no se obtiene ubicación del dispositivo. |
| `locationVisibility` | 0 = país/región; 1 = localidad sin coordenadas; 2 = punto aproximado y localidad si fue informada. Predeterminado 0. |
| `soughtPartners`, `soughtProfessionals` | Descripciones de necesidades, hasta 2000 caracteres cada una; no son perfiles, relaciones ni invitaciones. |
| `seekingConsortium` | `true`, `false` o `null` (sin informar). No crea un consorcio ni dispara contactos. |

Los textos se recortan en sus extremos; vacíos pasan a `null`. Se conserva el contenido
original al cambiar idioma y no se envía a servicios de traducción. Los indicadores no se
reordenan ni se les inventan unidades. La moneda, el presupuesto total, lo confirmado y la
brecha siguen usando el contrato financiero anterior; no hay conversión de moneda.

## Guardado y compatibilidad

- POST/PUT existentes reciben `enrichment`; GET privado, revisión administrativa y ambas
  fichas públicas lo devuelven. Las listas ligeras permanecen sin esta extensión.
- En PUT, propiedad omitida o `null` conserva la extensión vigente. La API obtiene el proyecto
  autorizado y aplica el mismo `If-Match` al guardado. Un objeto explícito reemplaza la extensión
  completa; `{}` la vacía. No son actualizaciones parciales de los campos internos del objeto.
- La UI envía el objeto completo; permite quitar indicadores y limpiar campos individualmente.
  Se mantienen 0 y `false`. Guardar es explícito; traducir no repite escrituras ni resetea el borrador.
- `040_project_enrichment.sql` agrega una columna JSON nullable sin backfill. El objeto y su
  snapshot se guardan en la misma transacción, junto con `ProjectVersion`, `RowVersion` y outbox.
  El hash SHA-256 de contenido incluye la extensión. SQL compara el JSON de la extensión con
  el objeto del snapshot y acota propiedades, tamaños, tipos, indicadores y ubicación.
- El límite de almacenamiento es 240000 bytes UTF-16: contempla escapes Unicode del serializador,
  además de los límites por campo. No se serializan textos ni coordenadas en eventos del outbox.
- Un proceso API pre-040 puede seguir creando/editando proyectos sin extensión. Si intenta
  actualizar uno enriquecido sin conocer este contrato, SQL falla con `51411` y no escribe un
  snapshot incompleto. No se retiran columnas ni se reescriben migraciones históricas.
- La edición continúa limitada a borrador/rechazado, con membresía administradora activa;
  pendientes, publicados y archivados quedan congelados. No cambia la autorización editorial.

## Ubicación pública y privacidad

Las coordenadas originales solo están disponibles en la lectura autorizada de la organización,
la revisión administrativa y los snapshots privados. Con visibilidad 0 tampoco sale la localidad.
Con visibilidad 1 sale la localidad pero ninguna coordenada. Con visibilidad 2 se redondean ambas
coordenadas a dos decimales; no se publica precisión completa.

SQL aplica una proyección explícita de campos y la API vuelve a aplicar `ForPublic()` en
`/api/v1/projects/{slug}` y `/api/v1/marketplace/projects/{slug}`. La UI pública añade una defensa
de presentación. El acceso público conserva `FundingPlatform_ifn_ProjectMarketplaceReady()`
y, por tanto, las reglas vigentes de organización, publicación y seguridad de adjuntos.
No se hace público el JSON privado completo ni se crea una ruta alternativa sin esas guardas.

El redondeo **no garantiza anonimato**. La UI advierte que no se ingresen localizaciones sensibles
ni datos personales en textos públicos. No hay geocodificación, validación territorial de las
coordenadas, dirección postal ni detección automática de residencia. El punto es una referencia
declarada, no una ubicación verificada. Las fichas públicas conservan su caché de 60 segundos;
las lecturas privadas siguen con `no-store`.

## Verificación y rollout

Corte local: build .NET/frontend, lint y tipos E2E aprobados; 790 unitarias .NET, 235 de
integración HTTP simulada, 908 frontend y 159 de navegador. Se omite solo el SHA Azure en local.

- Unitarias: normalización, límites, opcionalidad, privacidad, snapshots/hashes y análisis
  ScriptDom T-SQL 170 de la migración y smoke.
- Integración HTTP con repositorios simulados: preservación/limpieza del objeto, errores por
  campo, ETags, revisión privada y redacción de ubicación en las dos rutas públicas.
- Frontend/navegador: creación/edición, filas dinámicas, límites, 0/false, errores ES/EN,
  bloqueo editorial, cambio de idioma sin pérdida, guardado/recarga y accesibilidad a 320/1024px.
- Smoke `040`: fixtures sintéticos con rollback para crear, actualizar y limpiar la extensión
  versionada; proyecciones públicas por visibilidad, borrador, archivo y organización inactiva.
  Su validación local de sintaxis no equivale a ejecutarlo en SQL Server/Azure SQL.
- El smoke histórico `008` adapta sus tablas de captura al resultado actual (etapa/ODS/extensión)
  para poder ejecutar la cadena completa. Las migraciones históricas se mantienen inmutables.

Antes del despliegue: backup/preflight, ejecutar la cadena pendiente `031`–`040` y todos los
smokes en SQL desechable, verificar permisos runtime, después aplicar en dev. Orden obligatorio:
**base de datos → 100 % de API nueva → frontend**. La API nueva no debe recibir tráfico contra
una base pre-040. Verificar un ciclo real de guardar/reabrir/revisar/publicar y los tres niveles
de ubicación con fixtures de dev. No usar proyectos reales como fixtures ni forzar su aprobación.

En un rollback de aplicación, conservar la migración y los datos; la API antigua rechazará
ediciones de proyectos enriquecidos. No deshabilitar `51411` ni borrar la extensión para sortearla.
El flag de adjuntos sigue apagado y su [runbook](runbooks/project-assets-rollout.md) sigue vigente.

Siguiente bloque: mapa de proyectos publicados, con endpoint de puntos/paginación o agrupación,
filtros y ficha, consumiendo únicamente ubicación pública. No iniciar cambios de matching ni
consorcios como efecto implícito de haber agregado estos campos.
