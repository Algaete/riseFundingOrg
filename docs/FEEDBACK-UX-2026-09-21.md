# Feedback de producto — 21 de septiembre de 2026

El usuario pausó FundsforNGOs para priorizar este feedback. Este documento separa
el primer bloque implementado de los módulos que todavía faltan. **No es una
declaración de que todos los requerimientos estén terminados ni desplegados.**

Actualización de validación: preflight052–059 **aprobado en Azure dev con rollback**;
59 smokes SQL, 23 checks de mapa, 13 de traducciones y 1139 unitarias .NET aprobados.
Los estados «SQL pendiente» en los cortes históricos siguientes quedan superados.
Siguen pendientes despliegue, QA visual/funcional y los módulos aún no implementados.
Ver [evidencia y límites](runbooks/feedback-sql-preflight-2026-09-21.md).

## Bloque 1: formularios y navegación

Implementado localmente, sin migraciones, servicios nuevos ni llamadas a Azure:

- Proyectos nuevos: el formulario asigna USD cuando hay presupuesto, sin selector
  de moneda. Los borradores sin presupuesto siguen admitiendo moneda nula.
  Proyectos existentes con CLP u otra moneda conservan su moneda y sus importes;
  se muestra un aviso. No se aplican conversiones ficticias. La API general sigue
  aceptando las monedas válidas existentes; este cambio afecta al formulario.
- Países del proyecto: buscador por nombre localizado o código, ignorando tildes,
  lista acotada visualmente y selecciones siempre visibles/removibles. Se conserva
  la depuración de regiones al quitar un país.
- Indicadores: ejemplos de nombre, unidad, línea base y meta. No se precargan
  cifras ficticias; los indicadores siguen siendo opcionales.
- Ubicación: se sustituyen las entradas numéricas por un selector de punto en el
  mapa, con zoom, desplazamiento y selección por teclado. Reutiliza la proyección
  y el mapa base del mapa público; no hay geocodificador ni geolocalización del
  navegador. La publicación de un punto sigue siendo opt-in. Se preservan las
  coordenadas guardadas, las validaciones y la privacidad existente. Se puede
  quitar el punto y abrir `/marketplace/map` sin abandonar el borrador.
- Oportunidades: se quitan los enlaces públicos adicionales a la fuente y el
  enlace de fuentes en la ficha para organizaciones. Se mantienen las atribuciones,
  los datos de procedencia, los enlaces administrativos y la salida de postulación.
  Esto es una decisión de navegación, **no impide acceso al financiador ni protege
  la URL como secreto**; las APIs no han cambiado.
- Cierre exacto: fecha + hora local `HH:mm`, zona de una lista con búsqueda y
  conversión automática a UTC al enviar a la API. Santiago aparece con un nombre
  comprensible y es el valor inicial al elegir cierre exacto; el editor debe
  confirmar la zona de las bases, que puede ser distinta de la propia.
- Cambio de horario: se rechazan horas inexistentes o ambiguas, en vez de elegir
  un instante silenciosamente. En el caso excepcional de ambigüedad, el mensaje
  pide confirmar el instante oficial y permite ingresarlo con zona UTC.
- Compatibilidad: los cierres existentes no modificados conservan segundos y
  milisegundos, incluso en una hora ambigua ya resuelta. La última verificación se
  muestra en minutos y también conserva la precisión del valor original si no cambia.
- Carga manual: se preselecciona la entrada existente y habilitada `Manual editorial`
  cuando está disponible. El ID externo es opcional y se explica su propósito.
  No se inventan IDs, no se crean fuentes y no se habilitan entradas desactivadas.
  La URL oficial sigue siendo obligatoria como evidencia editorial interna.

### Módulos de código

- `features/funding/deadline-time.ts`: conversión y validación de zona horaria.
- `components/searchable-catalog-choices.tsx`: búsqueda y selección de países.
- `features/projects/project-location-picker.tsx`: selección geográfica en mapa.
- Adaptadores en formularios existentes y recursos ES/EN; contratos API sin cambios.

La conversión usa las partes de fecha y las zonas del entorno mediante
[`Intl.DateTimeFormat.formatToParts`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat/formatToParts)
y [`Intl.supportedValuesOf`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/supportedValuesOf).
Se comprueban candidatos por ida y vuelta para detectar saltos/repeticiones de hora;
no se usa el huso del equipo para interpretar el cierre del fondo.

## Bloque 2A: traducciones editoriales revisadas

Implementado localmente el almacenamiento por idioma/versión, API administrativa
con MFA, editor comparativo de once campos y lectura localizada ES/EN en las fichas
pública/de organización. Conserva el original; evita traducciones obsoletas y
mantiene montos, fechas y enlaces canónicos. Flags API/frontend desactivados.
La migración 053 aún no está aplicada. **No hay traducción automática implementada
ni fondos de Azure traducidos por este bloque.**

Ver [contrato, verificación y activación pendiente](FUNDING-CONTENT-TRANSLATIONS.md).

## Bloque 3: clasificación y antecedentes

Implementados localmente «Otros (especificar)» en categorías de oportunidades y
cuatro campos opcionales de antecedentes del proyecto: contexto adicional,
información técnica, alianzas existentes y resultados anteriores. Incluye API,
validación, snapshots/versiones, formulario ES/EN y presentación pública controlada.
No incorpora archivos adjuntos ni crea categorías globales con texto libre.

Migraciones 054 y 055/smokes preparados; falta preflight SQL real y despliegue.
Ver [contrato y compatibilidad](FUNDING-CATEGORIES-AND-PROJECT-BACKGROUND.md).

## Bloque 4A: biblioteca de portadas editoriales

Implementada localmente una biblioteca de cuatro ilustraciones temáticas creadas
con IA, seleccionables desde el editor del fondo. Se guardan con la versión editorial
y se muestran en tarjetas y fichas públicas/de organización; búsqueda y favoritos
conservan la elección. Respaldo local para fondos antiguos. Sin URLs externas,
uploads, cambios de categorías ni servicios cloud nuevos.

Migración 056/smoke preparados, sin aplicar. Ver [contrato y verificación](FUNDING-COVER-LIBRARY.md).
No sustituye ni completa la carga de fotografías/logos/videos/documentos propios.

## Bloque 2B-1: títulos/resúmenes localizados en listados

Implementada localmente la proyección de traducciones revisadas/vigentes en catálogo,
búsqueda de la organización, favoritos, explorador y sección de fondos de búsqueda
unificada. Un lote de lectura por página; conserva IDs, filtros, orden y cantidades.
Aviso de original cuando falta traducción, cambio de idioma sin perder formularios
y alternativa para ver originales. No genera traducciones ni traduce consultas.
SQL057 y smoke preparados, sin ejecutar; búsqueda ampliada en 2B-2 a continuación.

Ver [contrato, activación y límites](FUNDING-LIST-TRANSLATIONS.md).

## Bloque 2B-2: búsqueda literal bilingüe

Implementada localmente la búsqueda en original y títulos/resúmenes con traducción
revisada vigente ES/EN en catálogo, organización, explorador y búsqueda unificada.
Mantiene filtros, deduplica antes de contar/paginar y no depende del idioma de
presentación. No traduce consultas ni usa IA por visita. SQL058/smoke preparados;
activación y ejecución SQL real pendientes. Ver [contrato](FUNDING-BILINGUAL-SEARCH.md).

## Pendientes del nuevo feedback, por orden propuesto

| Bloque | Lo que falta | Dependencias y límites |
| --- | --- | --- |
| 2B. Contenido multilingüe | Generación automática, traducciones iniciales y otros consumidores (alertas/matching); despliegue de 2A/2B-1/2B-2 | Fichas, listados y búsqueda literal sobre títulos/resúmenes revisados ya implementados localmente. Definir proveedor/presupuesto antes de activar llamadas externas. Evitar cobro por cada visita. |
| 3. Clasificación y antecedentes | Preflight SQL, QA funcional y despliegue del bloque implementado | Otros/especificar y antecedentes de texto ya desarrollados localmente. Adjuntar informes/documentos sigue en bloque 4. |
| 4. Imágenes y adjuntos | Preflight/QA/despliegue de biblioteca 4A; carga de portadas propias, fotos/videos/documentos de proyectos y documentos de oportunidades | Biblioteca administrable implementada localmente. Reutilizar la preparación existente de adjuntos privados para uploads; completar activación segura de almacenamiento, procesamiento y controles. Distinguir portada pública de documento privado. No marcar archivos como limpios ni activar costes rechazados. |
| 4b. Material de suscripción | Ejemplos/guías o información adicional restringida por plan | Entitlements reales en API y descarga, no solo ocultar botones. Definir contenido con permiso de reutilización. |
| 5. Descubrimiento abierto | Buscar convocatorias por palabras clave en fuentes nuevas y enviarlas a revisión | Búsqueda programable, extracción con evidencia, deduplicación y cola editorial. Lotes bajo demanda/con frecuencia limitada y presupuesto máximo; no proceso SQL permanente ni publicación automática. Aún no implementado ni activado. |

En Azure, cambiar ES/EN todavía no traduce el texto editorial del fondo. El bloque
2A local podrá mostrar una traducción cuando un editor la cargue y revise; generar
traducciones automáticamente sigue pendiente. No se añadió un widget externo ni
se enviaron textos a un proveedor. La biblioteca local 4A añade selección editorial
de ilustraciones; no hay todavía carga de fotografías/logos propios ni está desplegada.

Los adjuntos ya tienen código preparatorio, pero están deshabilitados y su activación
segura sigue pendiente; ver `runbooks/project-assets-rollout.md` y
`PROJECT-PRIVATE-MULTIMEDIA.md`. Este feedback renueva el requerimiento funcional,
no constituye autorización para contratar/activar servicios con costo previamente
rechazados. No se han cambiado los flags.

## Validación y publicación

Último corte (2B-2): 1208 frontend/97 archivos, 1130 unitarias .NET y 421 HTTP
aprobadas; build frontend/API, lint y diff-check correctos. SQL y navegador real
pendientes. Los resultados que siguen corresponden al bloque 1 inicial.

- Resultado local: `npm test` — **1.164 pruebas aprobadas en 94 archivos**;
  `npm run build`, `npm run lint` y `git diff --check` aprobados.
- Pruebas frontend: conversión UTC/local, verano/invierno, saltos de fecha, husos
  fraccionarios, DST ambiguo/inexistente, conservación de precisión, valores USD/CLP,
  borradores opcionales, búsqueda de países, mapa, edición bloqueada y enlaces.
- La prueba visual en navegador quedó pendiente: Browser devolvió
  `No browser is available` y la lista de navegadores fue vacía. No se ejecutó una
  alternativa fuera del mecanismo disponible ni se accedió a sesiones privadas.
- No hay commit, push, despliegue ni cambios de datos en Azure de este bloque.
- Conservar los cambios previos de FundsforNGOs y moneda internacional sin mezclarlos
  con este release. La rama local de respaldo no debe desplegarse entera por accidente.
