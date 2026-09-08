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

La traducción completa de la aplicación NO está terminada. Siguientes bloques:

1. I18N-02: acceso, registro, recuperación, verificación, MFA y validaciones del formulario.
2. I18N-03: onboarding, perfil de organización y formularios/fichas de proyectos.
3. I18N-04: catálogo, marketplace, matching, red, postulaciones, calendario, alertas y planes.
4. I18N-05: administración, estados/errores de API, catálogos bilingües y formatos de fechas/montos.

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
[activación de adjuntos](runbooks/project-assets-rollout.md). Los idiomas de I18N-01 no requieren
migración SQL, pero siguen siendo cambios locales hasta publicar el frontend.

No se asigna un porcentaje global: algunos bloques son ampliaciones de módulos existentes y otros
son módulos nuevos. El cierre se acredita por criterios y pruebas de cada bloque.
