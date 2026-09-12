# Búsqueda unificada — corte local 2026-09-12

## Alcance

El usuario pausó adjuntos y pidió continuar con el siguiente bloque. Se agrega una
entrada común desde el inicio y la lupa del menú a `/search`. Ofrece Todo, Proyectos,
Oportunidades, Organizaciones y aliados, y Profesionales, con texto, país y área de
impacto. Las rutas y buscadores especializados anteriores siguen disponibles.

Es una composición frontend de consultas existentes, no un motor externo, índice
nuevo ni ranking entre tipos. No cambia contratos, backend, SQL, permisos, flags,
cuentas, publicaciones editoriales o configuración de Azure.

## Módulos

En `frontend/funding-platform-web/src/features/search`:

- `search-model.ts`: validación de URL, tipos, parámetros y límites por fuente.
- `search-api.ts`: GET a proyecciones existentes y adaptación mínima de tarjetas.
- `search-form.tsx`: borrador, catálogos, filtros y envío explícito.
- `search-results.tsx`: carga/error/vacío por sección, resultados y paginación.
- `search-page.tsx`: composición y autorización de directorios según sesión/membresía.

Recursos ES/EN en `src/i18n/unified-search`, cargados al navegar a la ruta. El idioma
de interfaz no traduce el contenido de usuarios o fuentes ni cambia los filtros.

## Fuentes y límites de visibilidad

| Sección | Endpoint GET existente, relativo a `/api/v1` | Acceso y filtros |
| --- | --- | --- |
| Proyectos | `marketplace/projects` | Público publicado; `q`, `countryIds`, `categoryIds`, orden `newest`. |
| Oportunidades | `funding-discovery` | Público publicado, `onlyOpen=true`; `query`, `countryId`, `categoryId`. |
| Organizaciones y aliados | `organizations/{miOrganizacion}/network/directory` | Sesión completa y membresía del actor; `q`, `countryIds`, `categoryIds`. Conserva opt-in, requisitos y bloqueos de la red. |
| Profesionales | `professionals` | Sesión completa y perfiles opt-in; `q`, `countryId`, `categoryId`. |

Sin sesión no se consultan los directorios privados: se muestra acceso con retorno
a la búsqueda. Para organizaciones se comprueba primero `GET organizations`. Una
sola membresía se selecciona automáticamente; varias requieren selección explícita.
Sin membresía no se consulta la red. Un `organizationId` agregado a la URL no otorga
contexto ni acceso. El servidor sigue siendo la autoridad de autorización.

El país representa alcance de proyectos/organizaciones, elegibilidad de fondos y
país del perfil profesional; no equivale a sede en todas las secciones ni garantiza
elegibilidad. Las categorías usan IDs compartidos, no etiquetas traducidas.

En Todo: hasta seis resultados por tipo, cada uno con su propio total y orden.
“Ver todos” abre ese tipo, veinte por página. No se suman totales incompatibles ni se
presenta un score global. Los profesionales muestran detalles compartidos en línea;
no se inventan rutas públicas de perfiles. Los otros tipos enlazan a fichas internas.

## Seguridad y uso bajo demanda

- Límite de 200 caracteres, IDs positivos dentro del rango de cada contrato y
  páginas 1–10000. Parámetros reconocidos duplicados o inválidos no disparan resultados.
- URL compartible con filtros, no tokens ni selección privada de organización.
- Solo proyecciones de lectura; sin llamadas administrativas, invitaciones o escrituras.
- Tarjetas con campos permitidos, texto escapado por React y enlaces internos construidos;
  no HTML de fuente, URLs externas de postulación ni imágenes/adjuntos privados.
- Cada consulta tiene cancelación. Las claves privadas incluyen actor y organización;
  desmontar/cambiar cuenta elimina resultados de pantalla y no conserva su caché inactiva.
- La ruta sin parámetros no consulta resultados. Escribir no consulta; enviar, paginar,
  seleccionar organización o reintentar sí. Sin polling ni reintentos automáticos;
  tampoco recarga por foco/reconexión. Los catálogos públicos se reutilizan una hora.
- Las búsquedas usan `cache: no-store`. Una falla no oculta los resultados de otros tipos
  ni expone diagnósticos técnicos. Se conservan las políticas de sesión del cliente HTTP.

No hay nuevo cargo fijo de infraestructura. **No significa costo cero:** las lecturas
a las APIs existentes consumen recursos y pueden despertar SQL serverless. Se mantienen
los límites y la configuración de autopausa; esta entrega no modifica Azure.

## Verificación y entrega

Pruebas unitarias/de componentes en `search-model.test.ts`, `search-api.test.ts` y
`search-page.test.tsx`; regresiones de portada en `home.test.tsx`. Navegador con fixtures
de solo lectura en `e2e/unified-search-checks.ts` y `e2e/home-reference-checks.ts`.
Cubren permisos de interfaz, aislamiento de caché, cancelación, filtros/paginación,
historial, idiomas, errores y presentación móvil/escritorio.

Validación local original (workspace con otros cambios pendientes):

- `npm test`: 1.029 pruebas aprobadas en 83 archivos; incluye 58 casos nuevos o
  ampliados respecto al corte previo a búsqueda unificada.
- `npm run lint`, `npm run typecheck:e2e` y `npx tsc -b --pretty false`: correctos.
- Build de producción: aprobado también al iniciar el servidor de la suite E2E.
- 16 pruebas focalizadas de navegador (portada y búsqueda) aprobadas, con auditoría
  de accesibilidad ES/EN, claro/oscuro y ausencia de desbordamiento. Capturas de búsqueda
  a 320 y 1280 píxeles revisadas visualmente.
- Regresión completa: `npm run test:e2e:public -- --workers=2`, 203 aprobadas y una
  omitida porque verifica metadatos de Azure que no existen en localhost. Incluye las
  16 focalizadas y las pruebas de sesión entre ventanas con servidores sintéticos.
- `git diff --check`: correcto. No se volvieron a ejecutar pruebas .NET ni SQL, ya
  que esta entrega no modifica backend o base de datos.

La skill de navegador no encontró un navegador interactivo disponible; las pruebas
se ejecutaron con la suite Playwright existente contra localhost y respuestas
sintéticas, no mediante la sesión real del usuario.

Preparación de publicación: se aislaron 25 archivos sobre main, conservando
el catálogo mundial ya desplegado y excluyendo los adjuntos en pausa. Esta versión
pasó 1.025 pruebas frontend, 8 pruebas focalizadas de navegador, lint, build y tipos E2E. No requiere migración SQL,
despliegue API/worker ni nuevos servicios. El release se verifica con CI y el workflow
existente de frontend antes de registrar su resultado. La prueba de interfaz sintética
no sustituye la aceptación posterior con datos y permisos reales en dev.

Publicación de estos 25 archivos en `Algaete/riseFundingOrg` y Azure dev autorizada
explícitamente el 2026-09-12. Se conserva la separación de alcance: búsqueda unificada,
sin el mapa avanzado ni los adjuntos. CI y despliegue se verifican sobre la revisión
exacta; la evidencia del resultado se registra tras completar la publicación.
