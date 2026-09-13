# Consorcios: colecciones nulas

## Incidente

La pantalla `/collaboration/consortia` publicada en Azure dev lanzaba
`Cannot read properties of null (reading 'map')` al renderizar `items`.
La comprobación `query.data &&` solo protegía el objeto de respuesta, no su
colección. Los contratos TypeScript no validan el JSON recibido en ejecución.

## Corrección acotada

- Normalización compartida en la frontera HTTP del módulo de colaboración.
- `items: null`, omitido o `[]` se convierte en una lista vacía cuando la
  paginación lo permite. Se conservan los totales y la página solicitada.
- Respuestas incompletas, tipos incorrectos o elementos ausentes donde el total
  indica resultados producen un error recuperable, no un falso “sin resultados”.
- La misma protección cubre las listas de profesionales/organizaciones del
  selector de invitaciones y los participantes vacíos del detalle.
- No cambia permisos, consentimiento, comandos, versiones ni idempotencia.

## Verificación

- La prueba de contrato nueva falló antes de la corrección para `items: null`.
- Pruebas HTTP: nulos, omitidos, arreglos, metadatos, errores HTTP y respuestas
  inconsistentes. Pruebas de componente: estado vacío, formulario usable y retry.
- Pruebas de navegador: creación del primer consorcio con lista nula; detalle
  sin participantes ni candidatos; ES/EN y 320/1024 px; accesibilidad y sin errores
  JavaScript. Los endpoints privados se simulan; no se usan cuentas reales.
- La verificación local completa del frontend pasó: 1127 pruebas unitarias y
  15 pruebas de navegador del módulo, además de lint, tipos y compilación.

## Despliegue

Solo frontend en el Static Web App existente. No requiere migración, escritura
de datos, cambio de API, reglas de firewall, servicios nuevos ni mayor capacidad.
No se ha inspeccionado una respuesta autenticada de la cuenta del usuario ni
se atribuye el origen del nulo a un procedimiento SQL específico.

## Evidencia de publicación — 2026-09-13

- [PR #23](https://github.com/Algaete/riseFundingOrg/pull/23), incorporada.
- Versión publicada: `ca3c28fce2d2c1c61fb9127d804ab40f9994ce7c`.
- [CI previa](https://github.com/Algaete/riseFundingOrg/actions/runs/34736110792):
  completa y correcta. El árbol del merge es idéntico al árbol validado.
- [Publicación Azure](https://github.com/Algaete/riseFundingOrg/actions/runs/34736620221):
  destinos, compilación y publicación/verificación completados correctamente.
  La auditoría general final en navegador seguía ejecutándose al registrar esta
  evidencia; no se declara aprobado el workflow completo todavía.
- `/deploy-meta.json` confirmó `ca3c28fce2d2c1c61fb9127d804ab40f9994ce7c`
  y el run `34736620221`.
- Verificación dirigida adicional contra los archivos servidos por Azure:
  **15 pruebas de colaboración aprobadas**, con respuestas privadas simuladas,
  incluyendo los dos nuevos casos en ambas resoluciones. No utiliza la sesión
  del usuario ni escribe consorcios/perfiles/organizaciones reales.
- Suite local completa: **220 pruebas de navegador aprobadas** y una omitida
  por ser exclusiva de los metadatos de despliegue; **1127 unitarias aprobadas**.
- [CI del merge](https://github.com/Algaete/riseFundingOrg/actions/runs/34736602203):
  completada correctamente (.NET y frontend), confirmado durante la revisión
  posterior del reporte de profesionales.
- API y base de datos permanecen sin despliegue ni cambios por este arreglo.

## Reporte posterior de `/professionals`

- El error pegado mencionaba `professional-directory-page-BqDIfAxy.js` y
  `index-Ae3Txvnx.js`, anteriores a la publicación. El primero ya devuelve 404.
- Azure entrega `index-lq-4c2Ti.js` y `professional-directory-page-BBUQc9l9.js`.
  Este último importa `collaboration-api-CbqlEuhu.js`, donde se confirmó la
  normalización de páginas publicada. El contexto de la posición 2195 es
  `data.items.map`, no los catálogos.
- Se añadieron ocho pruebas locales específicas del componente del directorio:
  null/omitido/arreglo vacío en ES/EN, conservación de búsqueda y filtros,
  resultados presentes y fallo HTTP recuperable. Las 67 pruebas del módulo
  pasaron. No hay un nuevo cambio del código de aplicación ni otro despliegue.
- Es necesario recargar el documento en la pestaña que conserva el código viejo;
  navegar entre enlaces dentro de la aplicación no reemplaza ese código.
- No se inspeccionó una sesión autenticada real. La consulta directa a catálogos
  sin sesión devolvió 401 y no se intentó evitar esa autenticación.
