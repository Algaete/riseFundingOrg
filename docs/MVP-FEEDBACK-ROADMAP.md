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

La traducción completa de la aplicación NO está terminada. Siguientes bloques:

1. I18N-04A: resumen y Mi cuenta.
2. I18N-04B: catálogo público y marketplace.
3. I18N-04C: matching y red de organizaciones.
4. I18N-04D: postulaciones, calendario, alertas y planes.
5. I18N-05: administración, estados/errores de API, catálogos bilingües y formatos restantes de fechas/montos.

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
[activación de adjuntos](runbooks/project-assets-rollout.md). Los idiomas de I18N-01/02/03 no requieren
migración SQL, pero siguen siendo cambios locales hasta publicar el frontend.

No se asigna un porcentaje global: algunos bloques son ampliaciones de módulos existentes y otros
son módulos nuevos. El cierre se acredita por criterios y pruebas de cada bloque.
