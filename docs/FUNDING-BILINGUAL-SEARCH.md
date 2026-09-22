# Búsqueda bilingüe de fondos — bloque 2B-2

Estado: **implementación local, sin activar ni desplegar** (21-09-2026).
Continúa las traducciones revisadas 2A y su presentación en listados 2B-1.

## Comportamiento

- Catálogo público, búsqueda de organización, explorador y sección fondos de
  búsqueda unificada consultan el original y los títulos/resúmenes con traducción
  **revisada, vigente y pública** en ES/EN.
- Una oportunidad aparece una sola vez aunque coincidan original y ambos idiomas.
- Coincidencia literal de la frase en título/resumen traducidos, sin distinguir
  mayúsculas ni tildes. `%`, `_`, `[` y `~` se buscan como caracteres, no comodines.
  Se alinea también el catálogo público con el escape literal de los otros buscadores.
- No traduce la consulta, no añade sinónimos y no hace búsqueda semántica. Si no
  existe traducción revisada, una palabra en español no descubre automáticamente
  su equivalente inglés. No incluye los demás campos traducidos en esta fase.
- `locale` sigue siendo solo presentación. Ver originales o cambiar ES/EN no
  cambia por sí mismo el conjunto de coincidencias. `languageId` sigue filtrando
  idiomas de elegibilidad/documentación, no el idioma de la traducción.
- Favoritos conserva la proyección localizada anterior; no tiene buscador nuevo.
  Alertas guardadas y matching no cambian y siguen usando sus reglas canónicas.

## API y control de activación

La API pasa `includeReviewedTranslations` internamente desde
`FundingTranslations__Enabled`. No es una opción pública de querystring.
Las pruebas HTTP comprueban que un parámetro añadido por el cliente no activa ni
desactiva esa política. Es independiente de `locale` y no se modifica `.env` real.

Con el flag desactivado o sin palabras clave, los procedimientos no ejecutan la
búsqueda de traducciones. La proyección de listados 2B-1, si está activada y se pide
un idioma, sigue siendo una lectura acotada adicional de los elementos de la página.
Respuestas de búsqueda con módulo habilitado son `no-store`, incluso al mostrar
originales, para no cachear coincidencias de revisiones retiradas. Las páginas ya
abiertas no reciben invalidación en tiempo real: deben volver a consultar.

## SQL y coste

`058_funding_translation_search.sql` incorpora una función interna compartida y
actualiza Public_List, OrganizationSearch y FundingDiscovery_Search:

- Exige `Reviewed=1`, versión exacta, ES/EN y `PublicReady()`; descarta títulos o
  resúmenes incompletos. Agrupa por oportunidad antes de contar y paginar.
- Materializa coincidencias una vez por búsqueda. Conserva filtros de pertenencia,
  país, categoría, moneda, plazos e idioma de elegibilidad; no filtra en memoria
  después de paginar ni mezcla páginas calculadas por separado.
- Organización combina rangos literales traducidos con los rangos originales y
  Full-Text existentes: exacto 1000, título parcial 800, resumen 400. No añade otro
  modo de ordenación ni un índice Full-Text de traducciones.
- Los parámetros SQL son opcionales y por defecto 0; los llamadores antiguos,
  incluidas alertas, siguen buscando solo originales. Conserva EXECUTE AS OWNER.
- Sin tablas, índices, grants de tablas ni permisos directos nuevos para la función;
  se usa mediante la cadena de propiedad de los procedimientos existentes.

No hay llamadas IA por visita, indexador externo, proceso permanente ni recurso
Azure nuevo. **La búsqueda sí añade trabajo al SQL existente** cuando se habilita;
lee título/resumen del JSON de traducciones. Medir duración y lecturas con un volumen
representativo antes de activar. No promete coste cero ni rendimiento probado a escala.

## Validación y despliegue pendiente

- 1208 pruebas frontend / 97 archivos; build y lint correctos.
- 1130 unitarias .NET, incluidas sintaxis Azure SQL y contratos de migración.
- 421 pruebas HTTP con repositorios simulados; flag, idioma, filtros y caché.
- API compila sin errores/advertencias. `git diff --check` correcto.
- Smoke058 transaccional aprobado en Azure dev: borrador, ES/EN, acentos, puntuación literal,
  duplicados, retirada de revisión, cambio de versión, filtros, conteo/paginación,
  valor por defecto y pérdida de publicación; todos sus datos fueron revertidos.
- Docker local no está iniciado (comprobado); QA de navegador real pendiente.

Actualización de validación: preflight autorizado aprobado en Azure dev, con
052–059, 59 smokes, 23 checks de mapa y 13 de resultados reales de traducciones.
Todo revertido; reglas temporales retiradas y 1139 unitarias aprobadas. La059
repara solo dos identidades de fondos TEST. No hay publicación ni activación.
Ver [evidencia y release pendiente](runbooks/feedback-sql-preflight-2026-09-21.md).

Orden de release: seleccionar cambios preservando el trabajo ajeno → resolver
cadena 052–059 → repetir preflight del SHA final (ya aprobado en el checkout local)
→ migraciones → API compatible → frontend → revisión de prueba y medición → flags.
La nueva API requiere SQL058 antes de desplegar, aun con el módulo desactivado,
porque envía el nuevo parámetro. Revertir funcionalmente desactivando ambos flags,
sin borrar traducciones/historial. Mantener una versión de API compatible con SQL058.

No hay commit, push, despliegue, datos reales traducidos ni proveedores activados.
Faltan generación automática con presupuesto, carga/revisión inicial y despliegue;
adjuntos/seguridad pagos y FundsforNGOs continúan pausados.
