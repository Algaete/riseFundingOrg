# Portadas editoriales de oportunidades — bloque 4A

Estado: **implementación local, sin desplegar** (21-09-2026). Esta biblioteca no
habilita archivos adjuntos, carga de fotografías/logos propios ni contenido de pago.

## Experiencia y alcance

- En crear/editar una oportunidad, administración y espacio del financiador usan
  el mismo selector de portada: predeterminada, naturaleza, educación, comunidad
  y ciencia. Solo se puede editar en borrador/rechazado, como el resto del contenido.
- La elección se guarda con el fondo, no al pulsar la miniatura. Conserva ETag,
  idempotencia, versión, revisión editorial y permisos de propietario/MFA existentes.
- Tarjetas públicas, búsqueda de oportunidades de la organización, favoritos y
  fichas públicas/de organización muestran la misma portada. No se deduce del
  título ni cambia cuando el usuario cambia el idioma de interfaz.
- Los fondos antiguos/importados sin selección usan la ilustración de comunidad.
  «Predeterminada» restablece explícitamente ese mismo comportamiento.
- Las imágenes están identificadas como «Ilustración temática · IA». No representan
  proyectos reales, logos oficiales, evidencia de impacto o avales del financiador.
- No cambia categorías, elegibilidad, geografía, puntajes ni matching.

## Módulos y contrato

- `funding-covers.ts`: catálogo cerrado de claves y rutas estáticas propias.
- `funding-cover.tsx`: portada compartida, carga diferida en tarjetas y respaldo
  accesible si un archivo falla. En detalle carga inmediata.
- `funding-cover-picker.tsx`: selección por controles radio nativos, ES/EN y errores
  asociados al campo. Hereda el bloqueo editorial del formulario.
- `FundingCoverRules`: lista permitida en servidor, sin aceptar URLs ni paths.
- `coverKey` opcional en escrituras, detalle administrativo y lecturas públicas/de
  organización. Valores: `auto`, `nature-v1`, `education-v1`, `community-v1`,
  `research-v1`; `null` es compatible con registros/clientes anteriores.
- Migración `056_funding_cover_library.sql`: columna nullable, CHECK, snapshot
  coherente y procedimientos existentes de guardado/lectura. No agrega grants.
  Conserva `EXECUTE AS OWNER` en la búsqueda que usa Full-Text dinámico.

Las claves desconocidas fallan con 422 y código de campo `funding-cover-invalid`.
El cliente nunca convierte una clave desconocida en URL: usa el respaldo local.
Un cliente antiguo que omite la clave de una oportunidad que ya tiene selección
recibe `funding-cover-required` (resultado SQL `cover-selection-required`) en vez de
borrarla. Para restablecer debe mandar `auto`. El control se ejecuta bajo los bloqueos
del guardado, después de reconocer replays y validar ETag/estado; no crea versión
al rechazar una omisión. La portada forma parte del snapshot/hash editorial.

Cambiar portada crea versión editorial; por diseño actual también vuelve obsoletas
las traducciones ligadas a la versión anterior, aunque el texto no haya cambiado.
Se deben revisar/guardar de nuevo antes de mostrarlas como vigentes. No se altera
silenciosamente ese contrato en este bloque.

## Assets

Cuatro ilustraciones generadas con la habilidad `imagegen` y su herramienta integrada,
inspeccionadas individualmente. Copias de entrega JPEG 1200×800, unos 1,4 MB en total,
en `frontend/funding-platform-web/public/images/funding-covers/`. Los originales
generados se conservan fuera del repositorio. No se consultó una biblioteca de stock.

Ver [archivos y prompts finales](../frontend/funding-platform-web/public/images/funding-covers/README.md).
Las rutas `*-v1.jpg` son versionadas: para reemplazar contenido publicado, añadir una
clave nueva con su validación/migración; no sobrescribir imágenes cacheables de v1.

No hay llamadas de generación en producción, servicios cloud nuevos ni dependencia
de imágenes externas. La entrega usa el hosting existente y su tráfico habitual.

## Verificación local

- Frontend: **1200 pruebas / 96 archivos**, build y lint aprobados.
- .NET unitarias: **1110 aprobadas**; incluye parser Azure SQL de migración/smoke 056.
- Integración HTTP: **390 aprobadas**, con repositorios simulados, no una BD real.
- Cobertura nueva: claves válidas/URLs inválidas, snapshot, reapertura, reset explícito,
  ETag/idempotencia del formulario, bloqueo pendiente/publicado, idioma, imágenes
  fallidas, respuestas públicas, búsqueda/favoritos y portada en ficha traducida.
- `git diff --check` limpio.
- **QA visual real pendiente:** la habilidad Browser devolvió `No browser is available`
  y su catálogo de navegadores estaba vacío. No se usó una alternativa no conectada.
- **Preflight SQL aprobado posteriormente:** smoke056 ejecutado en Azure dev con
  rollback dentro de052–059; propietario, snapshot, omisión legacy y replay.
  Ver [evidencia de validación](runbooks/feedback-sql-preflight-2026-09-21.md).

## Publicación pendiente

1. Revisar los cambios de esta entrega junto a los bloques locales anteriores;
   no desplegar indiscriminadamente la rama de respaldo ni importadores pausados.
2. Ejecutar preflight SQL real hasta 056 en entorno acordado, con smokes, rollback,
   permisos mínimos y reapply; no arrancar SQL continuo ni activar costes nuevos.
3. Aplicar esquema antes de API y frontend. La API nueva envía `@CoverKey`, por lo
   que no puede publicarse contra procedimientos anteriores. Evitar API antigua
   escribiendo selecciones nuevas; la omisión está bloqueada deliberadamente.
4. QA de extremo a extremo: seleccionar → guardar → enviar a revisión → aprobar →
   comprobar tarjeta/ficha/favoritos; confirmar rechazo sin rol/propiedad/MFA/ETag.
   Revisar móvil/escritorio, temas claro/oscuro y ES/EN.

No se hizo commit, push, cambios permanentes de datos ni despliegue en Azure.
Siguen pendientes: fotografías/logos propios, fotos/videos/documentos del proyecto,
adjuntos de oportunidades, material por suscripción, traducción automática/listados
y descubrimiento abierto. Los flags del módulo de archivos permanecen desactivados.
