# Bloques restantes: 6–9

Solicitud: continuar los cuatro bloques restantes sin confirmaciones entre pasos.
El tablero tiene tres bloques funcionales pendientes; el cuarto corresponde a validación
integrada y despliegue dev. No se incluyen producción, cambios de cuentas, compra de servicios,
acceso a fuentes restringidas ni ampliación de privilegios permanentes.

- [x] 6. Matching ampliado: financiador/oportunidad → proyectos; proyecto/organización →
  organizaciones y profesionales; criterios, brechas y datos desconocidos explícitos.
- [x] 7. Oportunidades e ingesta: clasificación/filtros ampliados, fuente/actualización,
  conector de feed autorizado y revisión editorial; ninguna autopublicación ni scraping restringido.
- [x] 8. Multimedia: video y documentos adicionales privados con formatos/límites explícitos,
  inspección, cuarentena/scan, descarga segura y retención; sin publicación automática.
- [x] 9. Verificación integrada y despliegue dev: pruebas, preflight SQL/infraestructura,
  release reproducible API/worker/frontend y comprobación real de funciones habilitadas.

Cada cierre requiere pruebas y commit local. Los permisos, servicios de pago y credenciales
que falten para activar integraciones se registrarán como bloqueos reales, no como completados.

## Cierre local del bloque 6

Ruta `/matching/ecosystem`; motor determinista `ecosystem-rules-v1`. Solo candidatos públicos
u opt-in; origen privado limitado a su titular. Clasifica coincidencias, brechas y datos desconocidos,
muestra evidencia y cobertura; no convierte moneda, no presume elegibilidad por domicilio del
financiador, no puntúa «Otros» y no envía invitaciones. Evalúa los 200 candidatos visibles más
recientes y avisa cuando hay más; no se presenta como ranking exhaustivo ni predicción de éxito.

Validación focalizada: 18 pruebas .NET unitarias/permisos, 4 HTTP, 7 frontend y 2 E2E ES/EN
320/1024 px, accesibilidad, build y tipos aprobados. Migración/smoke 044 preparados; ejecución
SQL y disponibilidad en Azure pendientes del bloque 9. La búsqueda desde financiador requiere
prioridades explícitas; la elegibilidad legal/regional definitiva y el consentimiento siguen siendo humanos.

## Cierre local del bloque 7

Explorador público y clasificación administrativa versionada; ver `FUNDING-DISCOVERY.md`.
66 pruebas focalizadas de backend/migraciones/RSS, 10 HTTP y 4 E2E ES/EN/móvil/escritorio.
Conector RSS/Atom existente reforzado; activación de otra fuente condicionada a acceso autorizado.
No se configura ni promete acceso a FundsforNGOs sin esa información.

## Cierre local del bloque 8

MP4 privado y TXT UTF-8, sin reproducción pública ni transcodificación. Contrato y límites:
`PROJECT-PRIVATE-MULTIMEDIA.md`. Integrados en el flujo existente de cuarentena, análisis,
copia exacta, descarga autenticada y retención; comparten la cuota de documentos.
La bandera de Azure permanece apagada hasta comprobar Defender y permisos reales.

## Bloque 9 cerrado en Azure dev — 2026-09-09

Suite local: 887 unitarias .NET, 298 HTTP, 937 frontend y 185 E2E aprobadas;
se omite únicamente el metadato de revisión Azure en la ejecución local. Build, lint y tipos
aprobados. Preflight real completo aprobado: 16 migraciones (031–046), 144 lotes y
46 smokes sobre la base dev con 30 migraciones aplicadas; todo revertido y firewall limpiado.
CI Linux detectó desbordes móviles que no aparecieron en macOS: corregidos en los
componentes compartidos y aprobados en CI, sin ocultar contenido ni reducir accesibilidad.
El verificador diferencia explícitamente la infraestructura futura de adjuntos del perfil
`imports-only` observado en dev; las pruebas rechazan CORS, contenedores y retención ajenos
a cada perfil. El worker se publica antes de API/frontend para cerrar los tres triggers nuevos.

Con autorización explícita del usuario se fusionó la PR #13 y se desplegó el commit
`4db49d40d8d950ce640e03caa7882ae87b19edb5`, después de aprobar CI e infraestructura en main.
Las 16 migraciones se aplicaron; la segunda aplicación confirmó cero pendientes y las
46 pruebas SQL posteriores pasaron con rollback de sus fixtures. Se eliminó la regla
temporal de firewall. El worker general publicó el paquete verificado de CI: 17 funciones
indexadas, únicamente las tres importaciones activas. API y frontend quedaron publicados
y sus verificadores `imports-only` aprobados. Las 186 pruebas de navegador sobre Azure
pasaron, incluida la comprobación del SHA realmente servido.

Este cierre no activa los adjuntos: imágenes, PDF, MP4 y TXT mantienen la bandera apagada
hasta validar almacenamiento, permisos y Defender reales. Tampoco habilita SSO, correo,
fuentes restringidas, servicios de pago ni nuevos privilegios permanentes. No se usaron
contraseñas ni se modificaron cuentas reales. Los tests públicos usan fixtures sintéticos
para pantallas autenticadas, no acreditan un recorrido con un usuario real.

Evidencia, revisiones, rollback y límites: [release dev](runbooks/mvp-feedback-dev-release-2026-09-09.md).
