# Profesionales, alianzas y consorcios — bloque 5

Implementado localmente. No está desplegado en Azure ni validado con SQL real.

## Recorridos

- `/professional/profile`: perfil profesional propio, sin exigir organización ni crearla
  automáticamente. Nombre público y especialidad obligatorios; trayectoria, país,
  competencias, idiomas y áreas de impacto opcionales. Los obligatorios llevan *.
- `/professionals`: directorio para usuarios autenticados, búsqueda por nombre/especialidad/
  competencia, país y área de impacto; paginación de 20.
- `/collaboration/consortia`: consorcios propios e invitaciones recibidas. El coordinador
  selecciona una organización que administra y uno de sus proyectos para crear el consorcio.
- `/collaboration/consortia/:id`: metadatos, estado, participantes e invitaciones.
  Una conexión previa entre organizaciones no equivale a aceptar un consorcio.

ES/EN con recursos diferidos por módulo, navegación móvil, confirmación de acciones,
validación localizada y conservación de borradores al cambiar idioma. El mensaje de error
desconocido del servidor nunca se presenta directamente. Cambiar idioma no repite escrituras.

## Privacidad y autoridad

Los perfiles son privados por defecto. Visibilidad y permiso de invitaciones son decisiones
explícitas; habilitar invitaciones exige visibilidad. El directorio no es una ruta pública:
requiere sesión completa. No copia ni devuelve correo, teléfono, roles o ID de cuenta.

Desactivar visibilidad impide nuevas invitaciones; no retira participaciones aceptadas.
Cada participante conserva una acción explícita para retirarse, incluso con consorcio cerrado.

| Actor | Puede ver | Puede gestionar |
| --- | --- | --- |
| Administrador de la organización coordinadora | Consorcio y todas sus invitaciones | Metadatos, invitación, cancelación y remoción |
| Miembro de la coordinadora | Consorcio y participantes aceptados | No |
| Profesional invitado / administrador de organización invitada | Consorcio y su propia invitación | Aceptar/rechazar, no aceptar por otro |
| Participante aceptado / miembro de organización aceptada | Consorcio y lista de aceptados | Solo el profesional o administrador destinatario puede retirar su participación |
| Usuario ajeno, incluso Admin global sin membresía | Nada | Nada |

El mensaje de invitación solo se muestra al administrador coordinador y al destinatario,
no a otros participantes aceptados. Antes de aceptar no se muestra el resto de la lista.
Un bloqueo en la red de organizaciones revoca su acceso a la lista compartida; puede conservar
su propia participación para retirarse. No borra el registro histórico del coordinador.
Rechazar, retirarse o ser removido elimina el acceso derivado de esa participación.
Si el proyecto deja de estar publicado se omiten su título privado y enlace para destinatarios;
sus miembros propios conservan acceso a su información.

Un consorcio se puede preparar con proyecto propio no archivado. Para enviar o aceptar
invitaciones, el proyecto y su organización deben cumplir la guarda existente de marketplace.
Organizaciones destinatarias: visibles, opt-in y conexión aceptada sin bloqueo.
Profesionales: cuenta activa/confirmada y perfil visible que permite invitaciones; no el
perfil personal del mismo actor que envía la invitación.

## Estados y límites

- Consorcio: 0 en formación, 1 activo, 2 cerrado. Activar requiere al menos un aceptado.
  No vuelve de activo a formación. Cerrar cancela pendientes y bloquea metadatos e invitaciones;
  se conservan las acciones de retiro/remoción de participantes aceptados.
- Participación: 0 invitado, 1 aceptado, 2 rechazado, 3 cancelado, 4 retirado, 5 removido.
  No se reinvita al mismo destinatario dentro del mismo consorcio.
- Un consorcio por proyecto. Hasta 50 participantes históricos y 20 invitaciones por actor
  en 24 horas, además del límite HTTP. No se reinician por cancelar/rechazar.
- Nombre profesional 2–120, especialidad 2–160, trayectoria hasta 2000.
  Hasta 20 competencias de 2–80 caracteres, 20 idiomas y 30 áreas vigentes.
- Nombre consorcio 2–160, resumen hasta 1000; aporte 2–160, mensaje 10–500.
  Mensajes sin correos, enlaces ni secuencias de 8 dígitos, como la red existente.

Las necesidades de aliados/profesionales e interés en consorcios ya son campos opcionales
versionados del proyecto (bloque 2); no se sobrescriben al crear un consorcio.

## Contrato técnico

Módulos separados `Core/Collaboration`, `Application/Collaboration`,
`Infrastructure/Persistence/Collaboration`, endpoints propios y
`features/collaboration`. No agrega roles ni privilegios globales.

- GET/PUT `/api/v1/me/professional-profile`; GET devuelve JSON `null` si no existe.
- GET `/api/v1/professionals?q&countryId&categoryId&page&pageSize`.
- GET/POST `/api/v1/consortia`; GET/PUT `/api/v1/consortia/:id`.
- POST `/api/v1/consortia/:id/invitations`.
- PATCH `/api/v1/consortia/:id/participants/:participantId`, acción numérica 1–5.

Todas las rutas requieren sesión completa y envían `Cache-Control: no-store`.
Escrituras: clave idempotente ASCII 16–128; versiones fuertes de 8 bytes.
Primer perfil: `If-None-Match: *`; cambios: `If-Match`; crear consorcio solo exige clave.
Invitar usa ETag del consorcio y devuelve ETag del participante nuevo.
Accionar usa ETag del participante; ambas operaciones también incrementan la versión padre.
El cliente vuelve a consultar para no reutilizar la versión del padre.

Respuestas de escritura: `entityId`, `eTag`, `wasReplay`.
Errores: 404 acceso inexistente, 403 cuenta no habilitada, 412 versión, 409 duplicado/
estado/idempotencia, 422 catálogo/consentimiento, 429 límite, 503 deadlock reintentable.
Las validaciones de campos usan el contrato de códigos existente; no texto SQL público.

Migración forward-only `043`: perfiles, consorcios, participantes, ledger privado y
9 procedimientos autorizados al runtime. Las tablas no reciben permisos DML adicionales.
Propiedad del proyecto y organización vinculadas por FK compuesta. Autorización, comparación
de versión, escritura y auditoría se ejecutan dentro de transacción, con savepoint si aplica.
Replay requiere autoridad vigente y hash idéntico; el destinatario puede reintentar su retiro
aunque la primera ejecución ya haya eliminado el acceso a la lista.

## Verificación y despliegue

Regresión local del cierre: 839 pruebas unitarias .NET, 282 de integración HTTP,
924 de frontend y 179 de navegador aprobadas; build, lint y tipos E2E aprobados.
Una prueba del SHA de Azure omitida por ejecutarse contra el servidor local.

Pruebas de dominio/normalización/consentimiento, contrato HTTP con repositorios simulados,
cliente/validadores, paridad ES/EN y navegador con API sintética. La suite de navegador incluye
320/1024px, accesibilidad claro/oscuro, creación/cierre, invitación profesional/organización,
aceptación, conflicto de versión y ausencia de escrituras al explorar o cambiar idioma.

`database/Tests/043_professionals_and_consortia_smoke.sql` prepara cuentas y un proyecto
sintéticos con rollback. Comprueba opt-in, replay, privacidad antes/después de aceptar,
participación de organizaciones conectadas, bloqueo, retiro, cierre y auditoría.
El parser SQL valida sintaxis; **este smoke todavía no se ejecutó en un motor SQL**.
La allowlist de permisos de `027` incluye los nuevos procedimientos.

Antes de habilitar en dev: copia de seguridad y preflight de migraciones pendientes en orden,
ejecución de smokes en SQL descartable/dev, despliegue API antes del frontend, comprobación
con dos organizaciones y dos profesionales de prueba. No modifica usuarios existentes.

Fuera de este corte: matching ampliado (6), conectores/ingesta (7), video (8),
chat, envío de correos de invitación y acuerdos legales. Las invitaciones aparecen en la
lista de consorcios al abrirla; no se prometen notificaciones externas.
