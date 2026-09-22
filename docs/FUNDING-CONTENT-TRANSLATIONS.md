# Traducciones de contenido de fondos — bloque 2A, 21-09-2026

Estado: **implementación local de traducciones editoriales revisadas**. No se ha
desplegado ni habilitado en Azure. No implica que los fondos existentes ya estén
traducidos, ni completa todavía el requisito de traducción automática.

Actualización posterior 2B-1: títulos/resúmenes de catálogo, organización, favoritos,
explorador y búsqueda unificada ya están conectados localmente a las traducciones
revisadas. Ver [contrato del listado y límites de búsqueda](FUNDING-LIST-TRANSLATIONS.md).
Actualización 2B-2: búsqueda literal en original y títulos/resúmenes revisados ES/EN
implementada localmente; ver [búsqueda bilingüe](FUNDING-BILINGUAL-SEARCH.md).
No hay generación automática.

Validación posterior (21-09-2026): SQL053 y todos los smokes pasaron en el
preflight autorizado de Azure dev, con rollback, incluida la corrección de
collation de campos JSON. Los resultados de prueba originales de abajo son
históricos. Ver [ejecución y limpieza](runbooks/feedback-sql-preflight-2026-09-21.md).

## Alcance implementado

- Idiomas ES/EN, los mismos soportados por la interfaz actual.
- Texto original canónico separado de traducciones. No se alteran patrocinador,
  importes, monedas, fechas, identificadores, relaciones ni URLs.
- Once campos: título, resumen, descripción, elegibilidad, requisitos, objetivos,
  actividades permitidas/excluidas, restricciones, organizaciones y poblaciones.
- Pantalla administrativa `/admin/funding/:id/translations`, original y traducción
  lado a lado, borrador o aprobación explícita, límites por campo, aviso de versión
  obsoleta y confirmación al abandonar cambios sin guardar. Cambiar texto retira
  la confirmación de revisión. Los fallos de guardado mantienen el texto visible.
- Solo un administrador con MFA puede leer o escribir por la API administrativa.
  SQL vuelve a comprobar que el administrador está activo y tiene MFA habilitado.
- Publicación de traducción exige cobertura completa de los campos con texto en
  el original; no permite añadir texto a campos vacíos. La revisión humana sigue
  siendo responsable de fidelidad semántica, cifras y requisitos dentro del texto.
- Una traducción revisada solo aparece si coincide con `ContentVersion` y el fondo
  satisface los controles existentes de publicación. Al cambiar el original se
  vuelve a mostrar el original hasta revisar la nueva versión.
- Detalle público y detalle de organización solicitan el idioma seleccionado.
  Muestran un aviso de traducción revisada o de original sin traducción disponible,
  y permiten alternar al **texto original dentro de la plataforma**. Esto no
  repone los enlaces adicionales de fuente retirados en el bloque 1.
- API pública mantiene sus seis campos textuales existentes; la ficha del espacio
  de organizaciones localiza sus once campos. No se cambió el alcance de los DTOs.
- Sin `locale`, la presentación sigue siendo original. Con el módulo desactivado no se
  consulta el almacenamiento de traducciones. No hay proveedor invocado en lecturas,
  procesos periódicos ni SQL mantenido despierto por este módulo.

## Contrato y almacenamiento

- GET/PUT `/api/v1/admin/funding-opportunities/{id}/translations/{es|en}`.
  GET devuelve `{ translation: null | ... }`.
- PUT recibe `sourceContentVersion`, `expectedRevision` (0 si no existe),
  `reviewed` y `text`. Exige `If-Match` con el ETag de la oportunidad original.
- Respuestas: 428 si falta ETag válido; 412 si cambió original o traducción; 400
  para contenido/idioma inválido; 503 si el módulo está deshabilitado. También se
  conservan 401/403/404 y los límites de frecuencia administrativos.
- No hay replay idempotente de respuestas: repetir un PUT con revisión anterior
  recibe 412. Si se perdió la respuesta, copiar el borrador y recargar antes de
  reintentar; no sobrescribir cambios de otro editor.
- GET de detalle público y de organización acepta `?locale=es|en`. Responde con
  `localization` (`requestedLanguage`, `status`, `revision`). La lectura localizada
  es `no-store`; la caché de React distingue idioma y elimina entradas localizadas
  sin observadores. No hay actualización en tiempo real de una ficha ya abierta.
- Migración `053_funding_translations.sql`: tablas de traducción actual e historial
  por revisión; procedimientos AdminGet/Read/Save. Escritura y auditoría atómicas
  con bloqueos y doble comprobación de versiones. El rol de API recibe EXECUTE
  solo sobre esos tres procedimientos, no acceso directo a tablas.
- Guardar como borrador retira la versión pública de ese idioma; el historial
  conserva las revisiones anteriores. No hay restauración automática ni editor
  de historial en esta entrega.

## Activación futura, no realizada

1. Preparar una rama de release con los cambios seleccionados; **no publicar toda
   la rama de respaldo sucia** ni sobrescribir trabajo previo de importadores.
2. Preflight SQL transaccional de la cadena correspondiente. 052 (AUD) también
   está local y pendiente; resolver su inclusión antes de aplicar 053.
3. Ejecutar el smoke 053 y el manifiesto de permisos actualizado del smoke 027 en
   SQL real. Las pruebas de sintaxis no sustituyen esta ejecución.
4. Desplegar API compatible manteniendo `FundingTranslations__Enabled=false`.
   Habilitarlo solo después de la migración validada.
5. Compilar frontend con `VITE_FUNDING_TRANSLATIONS_ENABLED=true` y desplegarlo.
   Los ejemplos de configuración se entregan en `false`; no se editó `.env` real.
6. Cargar y revisar una traducción de prueba, comprobar ambos idiomas/original,
   modificar una versión original y confirmar que la traducción vieja no aparece.
   Verificar también roles, MFA, fondo no publicado y organización sin acceso.

Rollback funcional: deshabilitar ambos flags (frontend requiere recompilación).
Conservar tablas e historial; no borrar datos. Sin proveedor externo ni recursos
nuevos contratados. Una vez habilitado, sí habrá almacenamiento y lecturas SQL
adicionales; no se promete coste operativo cero.

## Pendiente para completar el requerimiento

- Generación automática por un proveedor, con presupuesto explícito, ejecución
  bajo demanda/lotes, límites, reintentos, validación y revisión. **No implementada**;
  la pantalla actual recibe traducciones redactadas o pegadas por el editor.
- Traducciones iniciales de los fondos existentes; no se enviaron textos reales
  a ningún servicio externo ni se generaron traducciones de datos de producción.
- Despliegue de listados 2B-1 y búsqueda literal bilingüe 2B-2 (migraciones 057/058).
  Alertas, matching y textos fuera de los once campos siguen separados.
  El bloque 2A inicial se centró en las fichas.
- QA visual en navegador y preflight del SHA de release final. El preflight local
  ya pasó contra Azure dev; el navegador de la sesión anterior
  no estaba conectado; no se ejecutó navegador alternativo en esta entrega.

## Verificación local

- API y proyectos de pruebas .NET compilan sin advertencias ni errores.
- Frontend: 1.169 pruebas aprobadas (95 archivos); build y lint correctos.
- Integración HTTP: 363 pruebas aprobadas, con repositorios simulados, no Azure.
- Unitarias: 1.079 aprobadas. Cobertura de idiomas, borrador/revisión, versiones, preservación de
  originales y sintaxis Azure SQL de migración/smoke 053. Incluye actualización
  del test del manifiesto de permisos. `git diff --check` correcto.
- Sin commit/push, migración ejecutada, despliegue, llamadas a proveedores ni
  modificaciones de datos del usuario en Azure.
