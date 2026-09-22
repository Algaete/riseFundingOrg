# Idioma de listados de fondos — bloque 2B-1

Estado: **implementación local, sin activar ni desplegar** (21-09-2026).
Extiende las traducciones editoriales 2A a títulos/resúmenes de listados. No genera
traducciones ni cambia los datos originales; solo proyecta una revisión existente.

## Superficies y comportamiento

- Catálogo público `/funding`.
- Búsqueda de la organización `/opportunities` y favoritos `/favorites`.
- Explorador avanzado `/funding/explore` y sección de fondos de `/search`.
- Idioma ES/EN seleccionado en interfaz, alternativa para ver originales dentro
  de la plataforma y aviso individual de traducción revisada/original no traducido.
- Cambiar idioma conserva filtros, página, texto sin enviar, favoritos, URLs,
  portadas, cantidades, monedas, fechas y clasificación. No ejecuta escrituras.
- Durante la carga de otro idioma no se reutiliza como placeholder la página del
  anterior. Cachés separadas por idioma, `staleTime: 0`, `gcTime: 0` para listas con
  el módulo habilitado y respuestas HTTP localizadas `no-store`.

**Actualización 2B-2:** se implementó localmente la búsqueda sobre original y
títulos/resúmenes de traducciones revisadas vigentes ES/EN, antes de contar/paginar.
No traduce consultas ni crea un índice externo. `locale` sigue siendo presentación;
`languageId` sigue siendo elegibilidad/documentación. Ver
[búsqueda bilingüe, coste y límites](FUNDING-BILINGUAL-SEARCH.md).

## API y límites

Se admite `locale=es|en` en:

- GET `/api/v1/funding-opportunities`.
- GET `/api/v1/organizations/{id}/funding-opportunities`.
- GET `/api/v1/organizations/{id}/favorites`.
- GET `/api/v1/funding-discovery`.

Idiomas inválidos/duplicados se rechazan con 400. Sin `locale`, no se consulta la
proyección traducida de la página; 2B-2 puede buscar coincidencias revisadas si el
módulo está activo. Con flags desactivados no se resuelve el repositorio de traducción.
Se conservan controles de sesión/membresía, publicación y rate limiting existentes.
Las lecturas privadas siguen siendo `no-store` aun sin idioma solicitado. Desde 2B-2
también las búsquedas públicas con módulo habilitado, aunque se muestren originales.

Primero se obtiene la página autorizada y filtrada. Luego, como máximo **una lectura
SQL adicional por página**, únicamente de los IDs y versiones de esa página:

- Proyección limitada a título/resumen; no trae las descripciones completas.
- Límite defensivo de 100 referencias y 40.000 bytes de JSON en SQL; los endpoints
  mantienen su paginación acotada existente.
- `ReadSummaries` vuelve a exigir publicación, revisión y versión igual a la del
  registro y a la referencia de la página. No expone borradores ni revisiones viejas.
- El servicio descarta idiomas/IDs/versiones ajenos, títulos inválidos, duplicados
  y cobertura incompleta. No mezcla título traducido con resumen original.
- Si falta traducción válida devuelve el original con `localization.status=original`;
  una proyección válida devuelve `translated` y su revisión.
- Un error SQL no se confunde con «no existe traducción»: sigue el manejo normal de
  error del endpoint. Las páginas ya abiertas no reciben retirada en tiempo real;
  deben recargar/consultar de nuevo, como el resto del catálogo.

No hay generación por visita, proveedor de IA, temporizador, job permanente ni
servicio cloud nuevo. Las lecturas adicionales al habilitarlo sí consumen SQL;
no se promete costo operativo cero.

## Persistencia y despliegue pendiente

`057_funding_translation_summaries.sql` añade un procedimiento de lectura y su
EXECUTE exclusivo para `FundingPlatform_ApiRuntimeRole`, sin permisos de tablas.
Las proyecciones de listado incluyen ContentVersion para verificar coherencia.
Se preserva `EXECUTE AS OWNER` de búsqueda Full-Text y los filtros previos.
Manifiesto de permisos del smoke 027 actualizado.

Flags existentes `FundingTranslations__Enabled` y
`VITE_FUNDING_TRANSLATIONS_ENABLED` siguen desactivados. No se modifica `.env` real.
Rollout: revisar release seleccionado → preflight SQL hasta 057 y smokes 027/053/057
→ migración → API → frontend → activar flags solo tras QA con traducción revisada.
No desplegar toda la rama de respaldo ni el importador internacional pausado.
La ampliación 2B-2 requiere añadir SQL058 al preflight y aplicarlo antes de la API nueva.

Pruebas SQL preparadas con datos sintéticos y rollback: borrador, revisión vigente,
idioma incorrecto, página vacía, cambio de versión y pérdida de publicación del
financiador. **Aprobadas en Azure dev con rollback** dentro del preflight052–059
(21-09-2026); ver [evidencia](runbooks/feedback-sql-preflight-2026-09-21.md).
QA visual/end-to-end en navegador real también pendiente.

## Verificación del corte local

- Frontend: **1208 pruebas / 97 archivos**, build y lint aprobados.
- Unitarias .NET: **1124 aprobadas**; parser Azure SQL del nuevo script/smoke.
- Integración HTTP: **405 aprobadas**, con repositorios simulados.
- Casos nuevos: lote único y límites, idioma/versión/revisión/ID incorrectos,
  duplicados, campos incompletos, original por defecto, flags desactivados,
  pérdida de membresía, filtros conservados, favoritos, caché por idioma y
  cambio de idioma con consulta anterior pendiente.
- `git diff --check` limpio. No equivale a preflight SQL o QA de navegador.

## Qué sigue pendiente

- Generación automática bajo demanda/lotes con proveedor y presupuesto acordados.
- Carga/revisión de traducciones de los fondos existentes; no se tradujo Azure.
- Activación de búsqueda literal bilingüe implementada en 2B-2; alertas, matching
  y otros textos fuera de los campos editoriales 2A siguen separados (por ejemplo,
  descripción libre de categoría «Otros»).
- Adjuntos/fotos/logos propios y material por plan continúan separados y pausados.
- Descubrimiento abierto por palabras clave hacia revisión editorial.

Sin commit, push, despliegue, lectura de credenciales ni cambios de datos reales.
