# Feedback MVP: desarrollo y despliegue separados

Este tablero compara el feedback entregado con el código, no con el estado del sitio Azure.
«Implementado localmente» no significa desplegado ni validado contra servicios reales.
Completar adjuntos `036`–`039` no completa todo el feedback.

## Base implementada localmente

- Mejoras del perfil de organización: tamaños, catálogos, selecciones múltiples, opciones privadas,
  experiencia con financiadores, tramos de presupuesto y financiamiento habitual, campos opcionales
  y señalización de obligatorios.
- Etapa independiente y los 17 ODS en proyectos; estados, presupuesto, financiamiento conseguido
  y brecha ya disponibles.
- Portada orientada a proyectos, financiamiento y alianzas, con sus dos CTA principales.
- Imágenes JPEG/PNG/WebP y PDF privados: carga, escaneo, sanitización, portada, permisos,
  revocación y retención exacta. Video no está implementado.
- Ya existían matching proyecto → fondos explicable, directorio de organizaciones, solicitudes de
  conexión, catálogo de financiadores administrado internamente e ingesta Grants.gov/RSS gobernada.

## 1. Idiomas — en curso

### I18N-01: selector, portada y navegación

Implementado localmente:

- Selector Español/English en cabeceras pública, de organización y administrativa, también móvil.
- Preferencia explícita en `funding-platform-language` del navegador; español por defecto.
  Si el almacenamiento no está disponible, el selector sigue funcionando durante la sesión.
- Portada, navegación, temas, pie de página, carga inicial y 404 traducidos con recursos tipados.
- `html.lang` acompaña el idioma; páginas aún no traducidas conservan `lang="es"` en su contenido.
- No modifica `preferredLocale` de la cuenta, sesiones, URLs, permisos, catálogos ni textos
  ingresados por usuarios. No hay traducción automática ni llamadas a proveedores externos.

Validación del corte I18N-01: build, lint y typecheck E2E aprobados; 221 pruebas de frontend y
21 pruebas de navegador aprobadas. Se omite una comprobación del SHA de Azure porque el entorno
es local. La suite cubre persistencia tras recarga, paridad ES/EN, almacenamiento bloqueado,
semántica de idioma, accesibilidad pública y cabeceras responsive con sesiones sintéticas.

### I18N-02: autenticación y validaciones

Implementado localmente:

- Acceso, registro, recuperación/restablecimiento de contraseña, verificación de correo, desafío y
  configuración MFA, callback Microsoft y comprobación de sesión en español e inglés.
- Recursos separados en `src/i18n/auth`, esquemas en `auth-validation.ts` y mapeo de errores
  de protocolo en `auth-feedback.ts`. La paridad de claves ES/EN se comprueba con tipos y pruebas.
- Validaciones y avisos ya visibles cambian de idioma sin borrar campos, repetir solicitudes,
  regenerar QR, modificar claves manuales/códigos de recuperación ni consumir otro handoff SSO.
- Errores conocidos usan identificadores de protocolo y estado HTTP; los desconocidos muestran
  un mensaje genérico traducido, no texto arbitrario del servidor. Registro y recuperación
  conservan respuestas genéricas que no revelan si una cuenta existe.
- Campos vinculados a sus errores para lectores de pantalla; enlaces de sesión vencida subrayados
  y contraste corregido en avisos. Pantallas de autenticación heredan el idioma seleccionado.

Validación del corte I18N-02: build, lint y typecheck E2E aprobados; 268 pruebas de frontend y
32 pruebas de navegador aprobadas. Se omite únicamente el SHA de Azure en esta ejecución local.
Incluye formularios a 320px, accesibilidad en claro/oscuro, errores y MFA con respuestas sintéticas;
el test de contraste espera el fin de las transiciones de tema. No se utilizan cuentas reales.

Límites: no cambia permisos, autenticación, política de contraseñas, payloads ni `preferredLocale`
de cuentas. No habilita SSO/correo ni traduce plantillas de email o páginas de Microsoft. Mi cuenta
y el contenido de los espacios internos quedan fuera de este corte. No hay despliegue ni migración SQL.

### I18N-03: organización, proyectos y adjuntos

Implementado localmente:

- Alta de organización, perfil de tres pasos, campos obligatorios/opcionales, opciones privadas,
  experiencia y tramos financieros: interfaz, ayudas, validaciones y avisos en español e inglés.
- Lista, creación y edición de proyectos; etapas, estados, requisitos de publicación,
  envío a revisión, confirmación de archivo y ficha pública en ambos idiomas.
- Panel de adjuntos: selección, límites, carga, cuarentena, resultados del escaneo, edición de
  metadatos, descarga y confirmación de eliminación. El flag de adjuntos continúa apagado.
- Recursos tipados separados en `src/i18n/organization`, `projects`, `project-assets` y
  `workspace-feedback`; `workspace-messages.ts` centraliza mensajes heredados y formatos locales.
- Cambiar el idioma conserva borradores, opciones privadas pendientes, selecciones de ODS/etapas,
  errores visibles y confirmaciones. No repite cargas, solicitudes de contenido ni operaciones.
  Se mantienen payloads, ETags, permisos, bloqueos editoriales y aislamiento de archivos.
- Fechas y montos de proyectos siguen el idioma de interfaz; las fechas sin hora conservan su
  día y no hay conversión de moneda. Nombres, descripciones y metadatos del usuario no se traducen.
- Semántica accesible del progreso del perfil, contraste de avisos y menú de pasos apilado en
  pantallas estrechas. Las páginas incluidas heredan el idioma elegido.

Validación del corte I18N-03: build, lint y typecheck E2E aprobados; 292 pruebas de frontend y
41 pruebas de navegador aprobadas, con la comprobación del SHA de Azure omitida en local.
Incluye accesibilidad en claro/oscuro, pantallas de 320/1024px y conservación del estado entre
idiomas con datos sintéticos. Las rutas simuladas de lectura rechazan escrituras inesperadas.

Límites: los nombres de catálogos aún vienen en español, se conservan con `lang="es"` y se
abordarán en I18N-05. Los errores heredados conocidos se mapean por texto exacto y los errores
de protocolo por tipo/estado; una validación desconocida de API muestra un aviso genérico en
inglés y conserva el diagnóstico original en español, hasta incorporar códigos de regla estables.
La revisión administrativa de proyectos sigue en español. Sin cambios de backend, SQL,
`preferredLocale`, políticas de seguridad, habilitación de adjuntos ni despliegue Azure.

### I18N-04A: Resumen y Mi cuenta

Implementado localmente:

- Resumen: métricas, próximos hitos, postulaciones recientes, estados de postulación, cargas,
  estados vacíos, fallos parciales y reintentos en español e inglés. Contadores y fechas se
  formatean con el idioma elegido; las fechas sin hora mantienen el día informado.
- Cambiar idioma conserva la organización seleccionada, los parámetros de URL, enlaces y
  títulos originales. No cambia el rango de 60 días, paginación, claves de caché ni permisos;
  no introduce consultas adicionales por idioma ni escrituras en módulos de seguimiento.
- Mi cuenta separada en `features/account/account-page.tsx`, con recursos propios en
  `src/i18n/account`; el resumen tiene recursos independientes en `src/i18n/dashboard`.
- Textos y resultados de vinculación Microsoft bilingües, conservando identidad local, sesión,
  preferencia de cuenta y URL. Una vinculación pendiente no se reinicia al cambiar idioma.
- La consulta de proveedores distingue carga, fallo de conexión y configuración pendiente.
  El botón de reintento sólo consulta proveedores; no inicia una vinculación ni habilita SSO.
- Límites de idioma actualizados para ambas rutas; selector de organización, correos largos y
  botón de vinculación adaptados a móvil, con contraste legible en los avisos de error.

Validación del corte I18N-04A: build, lint y typecheck E2E aprobados; 315 pruebas de frontend y
50 pruebas de navegador aprobadas. Se omite la comprobación del SHA de Azure en local.
Las nuevas pruebas cubren estados de proveedores y vinculación pendiente, seis estados de
postulación, fallos parciales, selección de organización, no repetición de solicitudes,
accesibilidad claro/oscuro y pantallas de 320/1024px. Sesiones, proveedores y datos son simulados.

Límites: este corte no agrega edición de datos personales ni métodos de seguridad nuevos; traduce
las funciones existentes de Mi cuenta. No habilita SSO ni modifica autenticación, MFA, roles,
backend o SQL. Los títulos recibidos de la API se conservan, sin traducción automática.
Las páginas completas de postulaciones, calendario y alertas siguen pendientes en I18N-04D,
aunque sus indicadores del resumen ya son bilingües. Sin push ni despliegue Azure.

### I18N-04B: catálogo público y marketplace

Implementado localmente:

- Catálogo público de oportunidades: búsqueda, paginación, carga, estados vacíos, errores,
  disponibilidad, fechas, montos y fichas completas en español e inglés.
- Marketplace: búsqueda con debounce, filtros, orden, paginación, tarjetas, perfil público de
  organización y conexión con el detalle canónico de proyectos ya traducido en I18N-03.
- Recursos separados en `src/i18n/funding-catalog`, `marketplace` y `discovery-feedback`;
  las claves ES/EN se verifican con tipos y pruebas. Los errores públicos usan mensajes seguros
  basados en estado HTTP y no muestran diagnósticos arbitrarios del servidor.
- Cambiar idioma conserva borradores de búsqueda, filtros, IDs de catálogo, orden, página,
  parámetros de URL y consultas pendientes. Se mantiene el orden financiero limitado a una
  misma moneda, sin conversión de importes ni cambios de precisión o reglas de cierre.
- Confirmación de salida externa traducida: se preservan destino exacto, hostname, foco,
  cierre con Escape, rechazo de URLs inseguras y necesidad de una acción explícita para continuar.
- Atribuciones y contenido de las fuentes permanecen intactos. El aviso de Grants.gov conserva
  su texto original en inglés con `lang="en"`; las categorías visuales siguen siendo orientativas.
- Las fichas compartidas con el espacio privado declaran su idioma; las acciones privadas
  todavía pendientes mantienen `lang="es"`. Paginación y confirmación externa se ajustan a móvil.

Validación del corte I18N-04B: build, lint y typecheck E2E aprobados; 347 pruebas de frontend y
58 pruebas de navegador aprobadas, con la comprobación del SHA de Azure omitida en local.
Incluye cierres por día y hora exacta, filtros y debounce, atribuciones, enlaces seguros, exclusión
de borradores y PII adicional, accesibilidad claro/oscuro y vistas a 320/1024px. Sólo datos sintéticos;
las pruebas no siguen los enlaces de postulación ni escriben en la API.

Límites: los nombres de catálogos conservan el español de la API con `lang="es"`; su traducción
pertenece a I18N-05. No se traducen títulos, descripciones, requisitos ni atribuciones de fuentes.
Las rutas privadas `/opportunities`, su detalle y `/favorites` tienen filtros y acciones propios
que no quedan completos por traducir sus fichas compartidas; se explicitan en I18N-04B.2 antes
de seguir con matching y red. No hay cambios de backend, SQL, permisos, seguridad de cuentas,
flags de adjuntos, push ni despliegue Azure.

### I18N-04B.2: oportunidades internas, detalle y Favoritos

Implementado localmente:

- Catálogo interno: búsqueda con debounce, filtros avanzados, orden, moneda, paginación,
  contadores, validaciones, cargas, errores y estados vacíos en español e inglés.
- Detalle autenticado: condiciones de las bases, admisión/exclusión por tipo de organización
  y personalidad jurídica, fuentes, modalidad/precisión de cierre y acciones privadas traducidas.
  La hora exacta permanece en UTC; no se modifica la zona horaria informada ni se convierte moneda.
- Favoritos: guardar/quitar, estado inmediato del botón, avisos, fallos y navegación tras quitar
  el último resultado de una página. Los mensajes ya visibles acompañan el cambio de idioma.
- Corrección reproducida con respuestas lentas: la operación de favorito captura la intención
  del clic como variable de la mutación. Su resultado ya no se invierte si el estado optimista
  o el idioma provocan un render antes de que responda el servidor.
- Corrección del orden por monto sin moneda: el aviso se muestra fuera del panel plegable de
  filtros, abre inicialmente los campos pertinentes y no deja un indicador de búsqueda infinita.
  La consulta sigue bloqueada hasta corregir los criterios; aviso con contraste claro/oscuro.
- Recursos tipados propios en `src/i18n/organization-funding` y mapeo seguro de errores HTTP
  en `organization-funding-feedback.ts`. Las tres rutas heredan el idioma de interfaz.

Cambiar idioma mantiene el texto pendiente, los filtros e IDs, la página, los parámetros de URL
y la organización usada por estas pantallas, sin consultas adicionales ni escrituras por idioma.
Se conserva el comportamiento previo de usar la primera organización de la lista: este corte
no agrega un selector ni un contexto global de organización. Las claves de caché y el rollback
de Favoritos siguen acotados a esa organización; no se tocan cachés de otra.

Los enlaces de guardar búsqueda e iniciar postulación mantienen su destino y no crean nada por
cambiar de idioma. Las pruebas no siguen enlaces de postulación. Títulos, bases y atribuciones
permanecen originales; los catálogos conservan su español con `lang="es"`, separado de los
sufijos traducidos de admisión/exclusión. Se mantiene el aviso de que clasificar no confirma elegibilidad.

Validación del corte I18N-04B.2: build, lint y typecheck E2E aprobados; 370 pruebas de frontend y
65 pruebas de navegador aprobadas. Se omite únicamente la comprobación del SHA de Azure en local.
La suite de navegador comprueba vistas de 320/1024px, accesibilidad, filtros, ausencia de
escrituras por idioma y eliminación explícita de un favorito sintético. Todos los datos y
respuestas están simulados bajo la guarda que bloquea solicitudes API inesperadas.

Límites: I18N-05 sigue pendiente para nombres de catálogos y códigos estables de reglas de API.
Sin cambios de backend, SQL, roles, seguridad, `preferredLocale`, flags de adjuntos, push ni Azure.

### I18N-04C: compatibilidad y red de organizaciones

Implementado localmente:

- Matching por proyecto: selección, cálculo explícito, historial y paginación, resultados
  actuales/históricos, cobertura, puntajes, condiciones excluyentes y desglose ES/EN.
  Las nueve reglas actuales y los 72 códigos de explicación existentes tienen recursos propios.
- El idioma no modifica el motor, pesos, resultados, clasificación, datos desconocidos ni
  frescura del cálculo. Se conservan proyecto, ejecución, página, URL y reglas desplegadas,
  sin consultas ni cálculos adicionales por idioma. Los proyectos archivados siguen sin
  admitir cálculos nuevos; el historial permanece disponible.
- Fechas, puntajes y avisos traducidos; el cierre exacto conserva UTC y las fechas sin hora
  mantienen su día. Las versiones del motor, perfil y bases permanecen intactas.
- Las evidencias continúan limitadas a fuentes/campos conocidos y conteos, sin revelar
  valores crudos, parámetros no permitidos ni datos privados fuera del contrato. Reglas
  desconocidas conservan su nombre y usan el resultado recibido como explicación de respaldo.
- El aviso estándar se traduce solo si coincide exactamente con el contrato conocido.
  Avisos nuevos o personalizados de la fuente se conservan originales, sin traducción supuesta.
- Red: directorio, búsqueda, filtros de dirección, estados, propósitos, privacidad,
  preparación de invitaciones y acciones de solicitudes en ambos idiomas. Se conservan
  texto pendiente, destinatario, proyecto opcional y mensaje privado al cambiar de idioma.
- Visibilidad, permisos de miembro/administrador y capacidades de acción informadas por
  el servidor no cambian. Traducir no activa el directorio ni envía, acepta, rechaza,
  cancela o bloquea solicitudes. Mensajes de éxito/error visibles siguen el idioma elegido.
- Cálculos y solicitudes pendientes no se repiten al traducir. Se mantienen las claves
  idempotentes y las reglas de reintento existentes, además de los ETags de configuración
  y acciones. No se modifican contratos ni políticas de concurrencia del backend.
- Corrección de estados de lectura de la red: un fallo al cargar la organización ya no
  se confunde con tener que crearla; configuración, directorio y conexiones muestran errores
  y reintentos de lectura explícitos. Un fallo de configuración no se presenta como opt-out.
- Recursos separados en `src/i18n/matching`, `network` y `collaboration-feedback`;
  `collaboration-messages.ts` resuelve códigos y errores de protocolo sin exponer diagnósticos
  arbitrarios. Contraste de avisos y controles de invitación adaptados a pantallas estrechas.
  `/matching` y `/network` heredan el idioma elegido.

Validación del corte I18N-04C: build, lint y typecheck E2E aprobados; 410 pruebas de frontend y
73 pruebas de navegador aprobadas. Se omite únicamente la comprobación del SHA de Azure en local.
Las comprobaciones de navegador cubren 320/1024px, claro/oscuro, reglas abiertas, permisos
de miembros, borradores de invitación, errores y un cálculo sintético con reintento idempotente.
Se usan datos y sesiones simulados bajo la guarda que bloquea solicitudes API inesperadas;
no se envían invitaciones a organizaciones reales ni se ejecutan cálculos en Azure.

Límites: no agrega matching con IA, profesionales, consorcios ni chat. Conserva la primera
organización de la lista en ambas pantallas; no implementa un selector global nuevo.
Nombres de organizaciones, proyectos, mensajes y catálogos permanecen originales; los
catálogos bilingües y códigos de validación por campo siguen en I18N-05.
Sin cambios de backend, SQL, roles, `preferredLocale`, SSO, flags de adjuntos, push ni despliegue.

La traducción completa de la aplicación NO está terminada. Siguientes bloques:

1. I18N-04D: postulaciones, calendario, alertas y planes.
2. I18N-05: administración, estados/errores de API, catálogos bilingües y formatos restantes de fechas/montos.

Cada bloque incorpora recursos ES/EN, pruebas y actualización de sus límites `lang`. No se debe
presentar una pantalla como traducida sólo porque su menú ya cambió de idioma.

## Desarrollo posterior, en orden de dependencias

| Bloque | Desarrollo pendiente |
| --- | --- |
| 2. Proyecto enriquecido | Localidad/coordenadas, problema y solución estructurados, cantidad de beneficiarios, indicadores, aliados y profesionales requeridos, búsqueda de consorcio. |
| 3. Mapa | Descubrimiento geográfico de proyectos publicados, filtros y fichas; privacidad de ubicación y agrupación de puntos. Depende del bloque 2. |
| 4. Financiadores | Registro/propiedad del perfil y espacio propio para gestionar oportunidades con revisión editorial. El rol global Admin no debe sustituir permisos de un financiador. |
| 5. Profesionales y alianzas | Perfiles profesionales, capacidades, necesidades de colaboración y gestión de consorcios sobre la base del directorio/conexiones. |
| 6. Matching ampliado | Financiador/oportunidad → proyectos y proyecto/ONG → aliados/profesionales, con explicaciones y brechas. Depende de los nuevos perfiles y datos. |
| 7. Oportunidades e ingesta | Tipos de financiador, filtros faltantes (idioma y socios/consorcios, entre otros), conectores nuevos y actualización/deduplicación. FundsforNGOs depende de acceso autorizado. |
| 8. Multimedia adicional | Video y otros formatos requieren políticas propias de límites, seguridad, procesamiento y costes. No basta con agregarlos al selector de archivos. |

## Validación y despliegue — trabajo diferente

Las migraciones locales `031`–`039`, infraestructura y adjuntos necesitan preflight SQL, pruebas
reales de almacenamiento/Defender y publicación coordinada. Ver
[activación de adjuntos](runbooks/project-assets-rollout.md). Los idiomas de I18N-01/02/03/04A/04B/04B.2/04C no requieren
migración SQL, pero siguen siendo cambios locales hasta publicar el frontend.

No se asigna un porcentaje global: algunos bloques son ampliaciones de módulos existentes y otros
son módulos nuevos. El cierre se acredita por criterios y pruebas de cada bloque.
