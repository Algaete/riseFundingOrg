# Idiomas: carga por módulo y formatos

Estado: I18N-05E, implementación local. Español e inglés; no traducción automática
de contenido escrito por usuarios, fondos importados ni catálogos personalizados.

## Recursos

- La aplicación arranca con el núcleo español (navegación, shell y mensajes básicos).
  La preferencia inglesa carga el núcleo inglés antes del primer render.
- `resource-loader.ts` registra importaciones dinámicas por idioma y módulo.
  `router.tsx` declara los módulos usados por cada pantalla, incluidos componentes y avisos
  compartidos. La pantalla espera sus recursos, no todos los idiomas de la aplicación.
- `resource-coordinator.ts` deduplica solicitudes, conserva recursos ya cargados e incorpora
  rutas abiertas durante un cambio de idioma. La selección más reciente prevalece.
- El cambio se confirma y persiste sólo tras cargar los módulos activos. Un fallo mantiene
  idioma, preferencia y formulario anteriores, con un aviso visible y selector habilitado.
  La caché del coordinador libera cargas fallidas; el navegador puede conservar fallos del
  módulo y requerir recarga. Nunca se fuerza una recarga que elimine un borrador.
- Los agregados `es.ts`/`en.ts` quedan para tipos y pruebas de paridad. No importarlos en
  código de producción en tiempo de ejecución. Algunos diccionarios españoles también
  participan en allowlists de mensajes heredados y se comparten con esos consumidores.
- El setup de componentes carga todos los recursos deliberadamente. Por ello las pruebas
  de navegador, con entrada real por router y detección de claves visibles, son necesarias:
  una prueba aislada de componente no detecta una dependencia omitida en una ruta.

Comprobación local: el chunk principal baja de aproximadamente 591 kB / 181 kB gzip
antes de este bloque a unos 390,5 kB / 120 kB gzip. Desaparece el aviso de 500 kB sin cambiar
su umbral. Esto mide un archivo del build, no el peso total descargado ni tiempo real de red.

## Formatos

`formats.ts` centraliza locale (`es-CL`/`en-US`), fechas, números y dinero.

- Una fecha civil `YYYY-MM-DD` conserva su día entre UTC-12 y UTC+14. Se valida el calendario,
  se rechazan días imposibles y no se inventa una hora para una fecha sin ella.
- Un timestamp conserva su instante. Se formatea según la zona pedida; cuando el producto
  muestra explícitamente UTC, se mantiene UTC. La conversión del editor hacia payloads ISO
  sigue separada y no depende del idioma.
- Los montos usan las unidades menores de la moneda (por ejemplo CLP/JPY 0, USD 2, KWD 3).
  Se conservan decimales monetarios en rangos públicos/editoriales; no se hace conversión
  cambiaria ni se altera el valor almacenado. Los valores no finitos o moneda malformada
  muestran un fallback seguro.
- Campos de formularios, IDs, versión, códigos, fechas ISO y payloads siguen sin localizar.
  Los contadores que ya usan locale conservan su comportamiento.

## Verificación y publicación

Pruebas del coordinador: deduplicación, caché, fracaso/reintento, selección concurrente y
ruta abierta durante carga. Pruebas de formato: zonas extremas, año bisiesto, valores inválidos,
instantes y monedas de 0/2/3 decimales. Navegador: entrada inglesa directa, carga acotada,
conservación de formulario y fallo de descarga a 320px.

El despliegue debe publicar todos los chunks del mismo build junto con su HTML. Mantener
una política de caché que no entregue HTML antiguo con chunks eliminados. Este bloque no
requiere SQL ni cambios de Azure; su código aún debe publicarse para llegar al sitio dev.
