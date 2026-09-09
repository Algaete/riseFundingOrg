# Espacio de financiadores — bloque 4

Ruta `/funder-workspace/funders`, accesible desde el menú de usuario autenticado.
Registro de perfiles nuevos, edición de sus datos y gestión de oportunidades propias.
No requiere ni concede el rol global Admin. No modifica cuentas, correos ni SSO.

## Propiedad y revisión

- `FunderWorkspaceOwners`: propietario explícito del perfil nuevo; hasta tres perfiles
  por cuenta, incluidos los archivados. No se reclama un perfil existente por nombre,
  correo, URL ni coincidencia con fuentes importadas. No hay transferencia automática.
- `OpportunityWorkspaceOwners`: asignación explícita al crear desde este espacio.
  Un vínculo editorial de financiador principal no otorga propiedad sobre un fondo.
  El portal acepta exactamente un financiador principal propio y no permite transferirlo.
- El contenido usa las mismas entidades, validadores, versiones, ETags, claves
  idempotentes, eventos y transacciones que administración. Borrador/rechazado puede
  editarse; pendiente/publicado no cambia silenciosamente. Corregir o desactivar usa
  las confirmaciones y estados editoriales existentes.
- Las colas administrativas existentes reciben los perfiles y fondos enviados a revisión.
  Solo las rutas administrativas con Admin/MFA pueden aprobar o rechazar. El portal
  no registra rutas `reviews`; su repositorio y cliente también rechazan esa operación.
- Lecturas y escrituras verifican usuario activo y propietario. Las escrituras repiten
  la autorización con bloqueos dentro de la transacción, antes de ejecutar o reproducir
  un evento. Los listados filtran tanto el conteo como la página. La creación y su
  asignación son atómicas; los replays tampoco pueden reclamar registros administrativos.

La fuente nativa `funder-workspace` es solo procedencia de una declaración del financiador:
no es una certificación ni una importación automática. La URL oficial, elegibilidad,
alcance y demás requisitos editoriales siguen siendo revisados por administración.
No se programan adquisiciones ni se descargan las URLs ingresadas.

## Módulos y contratos

API `/api/v1/funder-workspace/{funders|funding-opportunities}` con GET/POST, GET/PUT
por ID, `submit-review`, `start-correction` y `deactivate`. Los contratos HTTP se
reutilizan con servicios registrados bajo una clave de ámbito explícita. Las rutas
administrativas conservan su política; no hay suplantación de administradores.
`funding-sources` devuelve únicamente la opción de procedencia del portal.
Todas estas rutas tienen `Cache-Control: no-store`, incluidas respuestas de error.

La interfaz ES/EN reutiliza formularios y panel editorial mediante `editorial-scope`.
URLs, consultas, claves de caché y comandos idempotentes del propietario se separan
de administración. No muestra aprobación/rechazo ni roles de cofinanciador en este
primer corte. Cambiar idioma conserva el borrador y no repite operaciones.
El nombre obligatorio se indica con asterisco y `aria-required`; descripción opcional
se limita a 2000 caracteres, alineada con el validador de servidor.

## SQL y verificación local

Migración forward-only `042_funder_workspace.sql`. Reemite 14 procedimientos
editoriales de `010` con parámetro opcional `@OwnerWorkspace = 0`; no crea un segundo
motor editorial ni cambia los procedimientos de revisión. Agrega dos tablas privadas,
una guarda interna sin permiso directo para runtime y una lectura de fuente nativa.
`027` incorpora únicamente el EXECUTE de esa lectura; no hay permisos de tablas,
ALTER ROLE, EXECUTE AS ni cambios en las funciones de publicación.

Smoke `042`: fixtures sintéticos con rollback para creación/replay, actualización
versionada, asignación de oportunidad y denegación de lecturas ajenas/administrativas.
Está validado por parser; aún no ejecutado contra SQL real. Ejecutar tras las migraciones
en dev junto a `010`/`027`, comprobando publicación y ETags reales antes de aceptación.

Verificación local: 808 unitarias .NET, 252 HTTP, 918 frontend en 72 archivos y
168 navegador aprobadas; un SHA Azure omitido localmente. Compilaciones, lint y tipos
E2E aprobados. Pruebas HTTP/navegador usan repositorios/APIs sintéticas, no datos reales.
Sin push, despliegue Azure, asignación de perfiles existentes ni cambios de cuentas.
