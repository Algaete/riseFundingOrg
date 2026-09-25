# Verificación manual de organizaciones

Estado al 25-09-2026: validado en SQL Server 2025 local; publicación Azure en preparación.
Consultar `docs/runbooks/organization-verification-release-2026-09-25.md` para el resultado del release.

## Decisión de producto y alcance

El dueño confirmó que revisará organizaciones manualmente, con registro abierto,
alcance global y ES/EN. Este bloque separa esa decisión de `ProfileStatus` y del
porcentaje de completitud. Completar un perfil no lo verifica automáticamente.
La etiqueta del nivel de perfil 2 es «Datos suficientes» (umbral actual 80%),
no «perfil completo» ni una promesa de publicación o verificación.

Mientras el cliente define qué acciones exigirán verificación, se conservan todos
los permisos existentes. Pendiente o rechazada **no** desactiva una cuenta ni
bloquea consultas, publicaciones o contactos; verificada tampoco concede roles,
planes, privilegios ni una certificación legal. La decisión y sus notas son
privadas para administradores, sin distintivo público ni aviso por correo.

## Funcionamiento

- Estados: 0 pendiente, 1 verificada, 2 rechazada. Una organización sin decisión
  se lee como pendiente con revisión 0, sin crear registros mediante GET.
- En Administración → Organizaciones aparece filtro/distintivo independiente.
  En el detalle se puede verificar, rechazar o volver a pendiente.
- Cada decisión exige motivo de 5–2.000 caracteres y confirmación explícita.
  Registrar qué se revisó, sin contraseñas, documentos sensibles ni datos innecesarios.
- Se guarda responsable, fecha UTC, versión del perfil y revisión consecutiva.
  Se conservan todas las decisiones; la consulta muestra las últimas 50.
- Una edición posterior del perfil hace que verificada/rechazada vuelva a
  aparecer pendiente. La decisión anterior permanece en el historial. Esto se
  calcula por versión: no necesita timers ni consultas periódicas adicionales.
- Dos administradores, o un editor y un administrador, no deben sobrescribirse:
  el guardado exige la versión del perfil y revisión vistas. Un conflicto requiere
  recargar **ambos** recursos y confirmar una nueva decisión; no hay reintentos
  automáticos de escritura. Cambiar de organización descarta el borrador anterior.
- Textos ES/EN y presentación móvil/escritorio. Las notas son texto del revisor,
  no se traducen ni envían a IA.

## API y persistencia

`GET /api/v1/admin/organizations/{organizationId}/verification`
y `POST` en la misma ruta. Lectura y decisión exigen `admin-mfa`, límites de
frecuencia y respuestas privadas `Cache-Control: no-store`.

POST recibe `{ status, reason, expectedRevision, expectedProfileVersion }`.
Campos ausentes/incorrectos: 422; organización inexistente: 404; conflicto: 409;
rol/MFA inválido: 403; dependencia no disponible: 503 sin diagnóstico SQL sensible.
El actor se obtiene de la sesión, nunca de un campo suministrado por el cliente.

La migración nueva `063_organization_verification.sql` crea estado e historial
separados, extiende la consulta administrativa y concede únicamente dos EXECUTE
al rol de API. No modifica migraciones ya desplegadas, datos de perfiles ni
permisos de acceso de organizaciones. El worker no recibe nuevos permisos.
SQL verifica de nuevo administrador/MFA, bloquea el actor y el perfil, compara
ambas versiones y guarda estado/historial en una transacción.

## Validación y límite conocido

Las pruebas de servicio y HTTP usan repositorios simulados; no prueban por sí
solas la persistencia real ni las carreras de dos conexiones SQL. Hay parser
T-SQL y smoke transaccional sintético para alta pendiente, aprobación, edición,
rechazo, reapertura, atribución, historial y preservación del perfil/acceso.
El manifiesto de permisos de la cadena registra exactamente dos procedimientos
adicionales (50→52). No se amplían permisos de tablas ni de esquema.

Las pruebas de navegador usan datos sintéticos y niegan llamadas no previstas;
incluyen confirmación, conflicto, recarga, ES/EN, accesibilidad, temas y anchos
320/1024/1280. No equivalen a aceptación con cuentas reales.

Resultado local: 1.230 unitarias .NET, 487 HTTP y 1.277 frontend aprobadas,
sin omisiones; ocho recorridos Chromium aprobados con datos sintéticos, revisión
visual de capturas 320/1280, accesibilidad y temas. Lint/build/tipos E2E correctos.
Las cifras incluyen el workspace original con cambios previos, no un release aislado.

**SQL real validado localmente el 25-09:** baseline001–062 sin cambios, preflight
de063 con63smokes y rollback, aplicación063, reaplicación0 y63smokes aprobados.
Se corrigió `history:null` detectado en motor real: ahora devuelve `history:[]`.
El comprobador `tools/FundingPlatform.OrganizationVerificationSqlChecks` pasó21
comprobaciones reales, incluidas conexiones concurrentes bloqueadas observadas,
conflictos de revisión/perfil, revocación de rol/MFA, permisos efectivos API/worker,
historial y deserialización del repositorio. Limpia exclusivamente sus fixtures.
Exige localhost14363/base`res` y confirmación de servidor desechable; no carga`.env`.
No equivale a una prueba con cuentas reales del dueño ni a una prueba de carga.
Antes del despliegue sigue siendo obligatorio preflight Azure. Aplicar
SQL063 antes de API y frontend: la nueva lista envía `@VerificationStatus`.
No publicar solo el frontend o solo la API contra SQL062.

## Pendientes independientes

Política del dueño sobre organizaciones pendientes/rechazadas; aceptación real
de registro, correo, recuperación, perfiles, consultas, contacto y permisos;
presupuesto y dominio/productivo. Adjuntos, antivirus e IA permanecen apagados.
El presupuesto se documenta en `docs/owner/PRESUPUESTO-OPERACION-2026-09-24.md`.
