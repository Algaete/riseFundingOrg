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
