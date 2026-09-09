# Mapa de proyectos — bloque 3

Implementado localmente. Ruta `/marketplace/map`, enlazada desde el catálogo.
API anónima `GET /api/v1/marketplace/project-map`, limitada por `marketplace-read`.

## Contrato y privacidad

Filtros `q` (200 caracteres), país, área de impacto, ODS, etapa y estado independientes.
Página 1–10000; tamaño 1–200, interfaz 100. Orden estable por ID descendente.
La respuesta separa `totalCount` de proyectos mapeables y `withoutPublicLocationCount`:
ambos respetan los filtros y la guarda existente de publicación/organización/adjuntos.
No incluye borradores, coordenadas privadas, correos, contactos ni documentos.

Solo `locationVisibility = 2` y un par válido de coordenadas permiten un punto.
SQL y API redondean a dos decimales. No se deduce una ubicación a partir del país,
localidad o dirección. Los proyectos sin punto continúan disponibles en el catálogo.
La caché pública dura hasta 60 segundos: una retirada de consentimiento puede tardar
ese intervalo en desaparecer de una respuesta ya cacheada.

Mapa base autocontenido Natural Earth, sin fronteras políticas, geocodificación,
teselas externas ni claves nuevas. Proyección simple para descubrimiento, no navegación.
Agrupa solo los resultados de la página actual y lo informa explícitamente.
Zoom y desplazamiento tienen botones de teclado; una lista paralela permite abrir
las fichas sin interactuar con puntos. No hay contactos ni matching implícitos.

## Verificación y despliegue posterior

Migración forward-only `041_project_map.sql`; conserva la función de publicación
existente y concede solo EXECUTE sobre la nueva consulta al rol API.
Smoke `041` de lectura: inspecciona guardas/permisos, rechaza páginas sin límite y
ejecuta ambos resultados. El smoke transaccional `040` sigue cubriendo la proyección
de ubicaciones privadas/públicas; no se ejecutó SQL contra una base real en este corte.

Verificación local: 803 unitarias .NET, 243 HTTP con repositorios simulados,
914 frontend (71 archivos), 162 navegador aprobadas; una comprobación de SHA Azure
omitida en local. Compilación, lint y tipos E2E aprobados. Navegador cubre 320/1024px,
ES/EN sin borrar filtros ni repetir consultas, agrupación, paginación, vacío/reintento,
claro/oscuro y accesibilidad. Las APIs son sintéticas; no se escriben datos reales.

Despliegue posterior: aplicar `041` tras `040`, ejecutar smokes `027`, `040`, `041`
en dev y publicar API antes del frontend. Validar puntos con consentimiento real
controlado y retirada de publicación antes de aceptación. Sin push ni Azure aquí.
