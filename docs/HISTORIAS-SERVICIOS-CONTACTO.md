# Historias, Servicios, Contacto y donaciones futuras

Implementación del requerimiento 9–12 recibido el 22-09-2026. Publicación dev en preparación; consultar el runbook de release para el resultado efectivo.
La activación de traducciones automáticas queda en pausa; su código se conserva.

## Alcance del MVP

| Módulo | Disponible en el código | Límite explícito |
| --- | --- | --- |
| Historias | Crear/editar borradores, publicar/retirar, nueve tipos, vínculo opcional a un proyecto propio, áreas, ODS y países; listado, detalle y aparición en perfiles/proyectos | Texto plano y taxonomías; sin archivos, editor HTML, generación IA ni traducción automática de historias |
| Donaciones | Botones deshabilitados distintos para organización y proyecto; contrato de dominio separado | Sin cobros, proveedor, comisión, endpoints ni tablas de transacciones activas |
| Servicios | Siete servicios públicos y solicitud de cotización preseleccionada | No incluidos automáticamente en suscripciones; sin precios fijos ni contratación/pagos automáticos |
| Contacto | Formulario guiado, consentimiento, datos opcionales, recibo, bandeja privada y cambio de estado con versión | No chatbot de pago, promesas de elegibilidad ni aceptación de acuerdos; adjuntos aplazados |

Rutas públicas: `/stories`, `/stories/:id`, `/services`, `/contact`.
Espacio de organización: `/organization/stories`.
Administración: `/admin/inquiries` (administrador de plataforma con MFA).
Historias/Servicios/Contacto aparecen en el menú «Más»; Contacto también en el pie.
Interfaces ES/EN. El contenido escrito por organizaciones conserva su idioma original.

## Historias: publicación y privacidad

- Solo administradores activos de la organización pueden escribir/publicar. Miembros activos pueden leer sus borradores a través de la API privada; la pantalla de gestión se reserva a administradores.
- El proyecto vinculado debe pertenecer a esa misma organización. FK compuesta y validación SQL, no solo filtro en el formulario.
- Para ser pública, la organización debe cumplir el contrato existente `OrganizationMarketplaceReady` (perfil publicado/completitud mínima 80 y catálogos activos). El proyecto, si existe, debe cumplir `ProjectMarketplaceReady`.
- Confirmación explícita de derechos; consentimiento adicional si se declara experiencia personal o el tipo es beneficiarios. Se registra actor, fecha, revisión y confirmaciones en un historial privado.
- Guardar cambios devuelve la historia a borrador y reinicia confirmaciones. Volver a publicar es una decisión explícita; conflictos de versión no sobrescriben contenido.
- Retirar la historia o quitar la visibilidad de organización/proyecto la excluye de lecturas públicas. Estas respuestas usan `no-store`.
- Una organización con una historia pública puede abrir su perfil público aunque no tenga proyectos públicos. Se conserva el filtro de privacidad de la organización y los siete resultsets del perfil existente.
- Territorio inicial = países seleccionados; no se publican coordenadas, direcciones personales ni documentos de consentimiento. La organización conserva la evidencia real del consentimiento; la plataforma registra su declaración.

## Contacto, cotizaciones y correo

Datos obligatorios: nombre, email, país, motivo, descripción y consentimiento de contacto.
Organización, referencia de proyecto/fondo y fecha son opcionales; servicio obligatorio solo al solicitar cotización.
Las referencias son texto declarado por el solicitante, no relaciones confiables ni URLs que el servidor visite.
No adjuntar datos bancarios, credenciales o datos sensibles de beneficiarios.

Cada envío tiene UUID y hash del contenido normalizado. Repetirlo devuelve el mismo recibo; cambiar el contenido exige otra clave. Un mismo envío no genera múltiples avisos. Límites: 5 intentos por IP/10 minutos en la API; 3 registros/email/hora y 500 globales/24 horas en SQL (globales entre instancias). Honeypot adicional. No sustituye una estrategia antispam si crece el tráfico.

Se guarda primero en SQL. El aviso al equipo utiliza el servicio Azure Communication Email ya existente, si está configurado; **no se provisionan recursos**. Destinatario único de configuración, nunca un correo suministrado por el visitante. Sin copiar automáticamente al remitente.

Configuración nueva, apagada en `.env.example`:

```dotenv
Inquiries__Notifications__Enabled=false
Inquiries__Notifications__TeamEmail=
```

Requiere además `Email:Enabled`, endpoint, remitente y permisos existentes correctos.
No se editó `.env` real. Falta indicar el correo del equipo y realizar una prueba acotada antes de activar.

Estados de aviso: pendiente (0), reservado/en proceso (1), aceptado por proveedor (2), resultado no confirmado (3). «Aceptado» NO asegura entrega. El aviso tiene límite de 15 segundos y no se reintenta automáticamente tras resultados inciertos. Si el proceso se interrumpe, la bandeja sigue siendo la fuente de verdad.
Los registros creados mientras el correo esté deshabilitado NO se envían masivamente al activarlo: revisar la bandeja; no hay worker, polling ni drenaje automático de históricos. El administrador puede responder desde el enlace de email y cambiar atención nueva/en seguimiento/cerrada.
Antes de producción, definir política de retención/eliminación de solicitudes y aviso de privacidad operacional.

## Donaciones: frontera preparada, no activada

`Core/Donations/DonationDesign.cs` distingue destinatario organización de destinatario proyecto, que incluye su organización propietaria. Contrato futuro con referencia privada del donante, monto/moneda, fecha, método/proveedor, estado, comisión monetaria opcional, neto opcional y referencias de transacción/comprobante.

No se presupone un 5% ni se elige proveedor. Comisión y neto desconocidos no se representan como cero. No se guardan tarjetas, no hay checkout/webhook ni recepción o distribución de dinero.
Los datos actuales de presupuesto y financiamiento confirmado **no son** donaciones procesadas por la plataforma. No se inventan recaudaciones, porcentajes ni contadores de donantes.
Antes de activar se requieren decisiones legales/operacionales y de proveedor; ledger y conciliación idempotente, verificación de organización receptora, reembolsos, monedas, privacidad y contratos de pago serán otro bloque.

## Arquitectura y despliegue pendiente

- Core: `Stories`, `Engagement`, `Donations` (solo diseño).
- Application: validaciones e interfaces; coordinación guardar/avisar.
- Infrastructure: repositorios Dapper, adaptador de correo separado de email de autenticación.
- API: rutas públicas, por organización y admin-MFA; errores sanitizados.
- Frontend: módulo `features/engagement`, feed reutilizable e i18n independiente.
- SQL061: historias, historial, visibilidad y tres procedimientos nuevos.
- SQL062: solicitudes privadas y cinco procedimientos nuevos.
- Ocho permisos EXECUTE adicionales solo a API; sin SELECT directo ni permisos nuevos al worker. Smokes027/037/038 y manifiesto ajustados (42→50 procedimientos posteriores).

Antes de publicar:

1. Preflight SQL real completado el 22-09-2026: migraciones 060–062 (18 lotes), 62 smokes, 23 comprobaciones del mapa y 13 de traducciones. Todo dentro de transacción revertida, sin conservar datos sintéticos; regla temporal de firewall eliminada. El primer intento agotó el tiempo al reanudarse la base; el segundo pasó. SQL Server local ARM no es una plataforma de prueba compatible.
2. Seleccionar el release sin importadores pausados. El código SQL060 de traducciones se incluye con todos sus mecanismos de activación apagados. No se cambiaron capacidad, autopausa ni servicios Azure.
3. Publicar SQL → API → frontend solo con CI verde para el SHA exacto de main. El wrapper de base repite preflight, aplica, repite aplicación (cero pendientes) y ejecuta todos los smokes.
4. Ejecutar los ocho nuevos recorridos Playwright de Servicios, Contacto e Historias en 320/1280 px, ES/EN y accesibilidad, junto a la suite existente. Los recorridos usan respuestas sintéticas y no escriben en datos reales; no equivalen a una aceptación manual con cuenta de organización/admin.
5. Configurar destinatario y comprobar un aviso de prueba. Mantener donaciones, proveedores IA y adjuntos fuera del release activo según sus propias condiciones.

Tests nuevos: validación de nueve tipos y taxonomías, normalización, consentimiento, límites, idempotencia/aviso, autorización HTTP, receipt privado, errores SQL sanitizados, catálogos de servicios, ausencia de endpoint de pagos y formularios/UI.
Los tests HTTP usan repositorios simulados; no reemplazan la ejecución de los smokes SQL.

Validación local: 1.195 unitarias, 451 HTTP y 1.246 frontend (98 archivos), todas
aprobadas sin omisiones. Builds API/frontend, lint, tipos E2E y `git diff --check`
correctos. Se corrigió una restricción SQL sin nombre detectada por la suite antes
de cerrar la verificación. El preflight SQL real posterior está registrado arriba.
Verificación posterior del release aislado (sin importador pausado): 1.115 unitarias,
451 HTTP y 1.232 frontend/96 archivos, sin omisiones. Suite local de navegador:
228 aprobadas en 3,2 minutos; una comprobación de metadatos Azure omitida por no
aplicar a localhost. Corregida la carga lazy de las traducciones del buscador de
países de Historias. CI remoto y publicación siguen pendientes: el control de
permisos pidió confirmación explícita para continuar en el repositorio público.
La rama inicial fue subida, pero las correcciones posteriores permanecen locales.
