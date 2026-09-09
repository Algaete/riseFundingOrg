# Inicio público basado en la referencia visual

Fecha: 2026-09-09. Estado: implementado y validado localmente; este cambio aún no está desplegado en Azure.

## Alcance

Se adapta el inicio de FundingPlatform a la imagen entregada por el usuario: portada fotográfica, buscador superpuesto, cuatro accesos rápidos, proyectos y mapa en dos columnas, y cierre de impacto. Se conservan la marca existente, los idiomas ES/EN, los temas claro/oscuro/sistema y los destinos según sesión y permisos. La navegación pública incorpora Organizaciones, Alianzas y Profesionales; en pantallas pequeñas usa un menú desplegable accesible.

La fotografía decorativa fue generada con la herramienta integrada de imágenes y optimizada como JPEG de aproximadamente 247 KB. No representa un proyecto real. El archivo, su procedencia y el prompt están en [public/images](../frontend/funding-platform-web/public/images/README.md).

## Módulos

- `src/features/home/home-page.tsx`: composición, portada y accesos rápidos.
- `home-search.tsx` y `home-model.ts`: búsqueda explícita en proyectos u oportunidades, por texto, país y área de impacto; reutiliza los contratos y destinos existentes.
- `home-projects.tsx`: hasta tres proyectos publicados, ordenados por fecha, con importes y avance cuando los datos permiten calcularlo.
- `home-map.tsx`: vista compacta del mapa existente; solo ubicaciones públicas y agrupaciones de los resultados recibidos.
- `home.css`: estilos del inicio y adaptación móvil, sin cambiar los tokens de las pantallas administrativas.
- `src/i18n/catalog-display.ts`: traducción de etiquetas para consumidores de solo lectura, sin descargar anticipadamente los alias ingleses de validación. `catalog-labels.ts` conserva su API de validación existente.

## Datos y límites deliberados

No se agregan proyectos de demostración, porcentajes, marcadores ni categorías ficticias a la aplicación. El estado vacío invita a publicar una iniciativa; los errores se distinguen del catálogo vacío y permiten reintentar. El buscador conserva texto y filtros al cambiar de idioma y continúa permitiendo buscar por texto si no cargan los catálogos.

Los adjuntos de proyectos siguen siendo privados y su activación no forma parte de este cambio. Las tarjetas usan una ilustración vectorial genérica, no fotos privadas ni fotografías de terceros atribuidas al proyecto. Tampoco se incorpora un botón de favorito sin soporte funcional. El buscador no promete una búsqueda global de organizaciones, aliados o profesionales que los contratos actuales no ofrecen.

El mapa muestra hasta 100 ubicaciones de la respuesta pública e informa si hay más resultados. Los marcadores abren el mapa completo. Reutiliza la cartografía y la atribución de Natural Earth existentes. No se generan colores por sector cuando ese dato no está disponible en la respuesta.

No hay cambios de backend, base de datos, permisos, cuentas, publicaciones editoriales, configuración de Azure ni funcionalidades deshabilitadas.

## Verificación local

Desde `frontend/funding-platform-web`:

- `npm run lint`: correcto.
- `npm run typecheck:e2e`: correcto.
- `npm test -- --reporter=dot --silent=passed-only`: 950 pruebas aprobadas en 76 archivos.
- Compilación de producción: correcta, ejecutada también por el servidor de la suite de navegador.
- `CI=true npm run test:e2e:public -- --workers=2`: 197 aprobadas y 1 omitida por requerir metadatos del despliegue Azure, no presentes en el servidor local.

Se agregan 13 pruebas de unidad/componente y 12 de navegador. Cubren estados vacío/con datos/error, navegación, filtros, carga diferida de idiomas, rechazo de borradores, ausencia de imágenes privadas, accesibilidad automatizada y desbordamiento a 320, 768, 1024 y 1536 píxeles en claro/oscuro y ES/EN. La suite completa utiliza respuestas sintéticas controladas; no crea usuarios ni escribe en la API real. Esto no sustituye la comprobación posterior del despliegue en Azure.

Se revisaron visualmente las capturas de escritorio y móvil. Copias locales estables están en `artifacts/home-reference-review/` (ignoradas por Git). Las vistas previas de entrega muestran el estado vacío, no los proyectos sintéticos empleados en pruebas.
