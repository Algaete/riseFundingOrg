# Apoyos vinculados a requisitos del fondo

## Estado — 2026-09-12

Ampliación posterior local: la selección de países/regiones de los socios ya está
implementada mediante 051. Ver [matching geográfico](PARTNER-GEOGRAPHIC-MATCHING.md)
para el contrato y la evidencia actuales. 050 + 051 pasaron el preflight real con
51 smokes y 23 comprobaciones del mapa, todo revertido. Ambas siguen sin desplegar.
Los conteos siguientes corresponden al corte inicial 050.

Implementado localmente después del release del mapa `3784dc8`. No publicado ni
desplegado: Azure dev conserva la revisión anterior y migraciones definitivas hasta
049. La migración nueva es `050_gap_recommendations.sql` (un procedimiento de lectura
y su permiso EXECUTE específico; ninguna tabla nueva).

Validación local: 963 pruebas unitarias .NET, 349 HTTP con repositorios simulados,
1.073 pruebas frontend; build, lint y tipos E2E correctos. Regresión completa:
212 pruebas de navegador aprobadas (una omitida, metadatos Azure no presentes en
localhost), incluidas las dos nuevas a 320/1024 px, ES/EN y claro/oscuro.
Capturas inspeccionadas: textos y acciones sin desbordamiento horizontal. La skill de
navegador no encontró una instancia conectada; se utilizó Playwright con sesiones
y respuestas sintéticas. No se usaron cuentas reales ni se enviaron invitaciones.
Preflight real de Azure SQL dev aprobado: una migración (050, tres lotes),
50/50 smokes y 23 comprobaciones adicionales de resultados del mapa correctas.
El smoke 050 comprueba contexto real, flags booleanos/desconocidos, pérdida de
vigencia editorial, membresía revocada, usuario ajeno, retiro de publicación y
procedencia e inactivación del proyecto. Se revirtieron tanto 050 como los fixtures.
El script confirmó retirada de la regla temporal de una IP; una lectura independiente
posterior devolvió cero reglas con el prefijo temporal de las comprobaciones.

Los intentos iniciales detectaron tres conteos de permiso que debían reconocer 050,
fechas obligatorias omitidas en fixtures y un estado de membresía sintético
inconsistente con su fecha de ingreso. Corregidos antes del preflight completo
aprobado, sin cambiar permisos generales ni datos reales. Lectura final: `GP_S_Gen5`,
0,5–1 vCore y autopausa de 60 minutos, sin cambios. La comprobación ejecutó consultas
que pueden despertar SQL bajo demanda; no habilitó tareas periódicas.

## Experiencia y alcance

En `/matching`, cada resultado ofrece **Cómo abordar los requisitos → Buscar apoyos
para este fondo**. No se consulta al abrir la pantalla, cambiar de idioma, enfocar la
ventana ni reconectar; solamente al pulsar Buscar/Actualizar. El panel usa datos
actuales, mantiene intacto el cálculo histórico y lo señala cuando está desactualizado.

- Requisito editorial de socio internacional: organizaciones de otro país de sede
  que comparten al menos un área de impacto con el proyecto.
- Requisito editorial o necesidad del proyecto de formar un consorcio:
  organizaciones con áreas compartidas.
- Socios declarados en el proyecto: mismo criterio de áreas compartidas. El texto
  de la necesidad se muestra, pero no se finge entender ni certificar el tipo de socio.
- Profesionales declarados en el proyecto: coincidencias de palabras normalizadas
  entre las capacidades solicitadas y las habilidades del perfil. Se muestran esas
  coincidencias; no equivalen a certificación de experiencia.

Cada necesidad identifica si proviene del fondo o del proyecto, justifica los
candidatos y enlaza a la organización o al flujo existente para evaluar un profesional
en un consorcio. Revisar necesidades y revisar consorcios son navegación, no comandos.
No se abre una solicitud ni se crea un equipo automáticamente.

## Arquitectura y permisos

`POST /api/v1/matching/gap-recommendations`, cuerpo `{ projectId, opportunityId }`.
POST mantiene el contexto privado fuera de URL/historial; la operación es de lectura.

1. Endpoint: sesión completa, limitador existente `organization-activity-read`,
   identificadores no vacíos, errores 404 no reveladores y `Cache-Control: no-store`.
2. `SqlGapRecommendationRepository` / procedimiento 050: usuario habilitado, miembro
   activo de la organización del proyecto, organización/proyecto activos y proyecto
   no archivado. El fondo debe pasar la proyección pública editorial existente.
3. Solo se usan flags y evidencia de `FundingDiscovery` si su versión revisada
   coincide con el contenido actual. Ausencia, `null`, `false` y desactualización
   no se convierten en requisitos afirmativos.
4. `GapRecommendationService` reutiliza el repositorio Discovery 044 para candidatos:
   organizaciones públicas y discoverable, excluida la propia y los bloqueos entre
   organizaciones; profesionales discoverable que aceptan invitaciones, con cuenta
   habilitada/correo confirmado y distintos del actor. Revalida el acceso al proyecto.
5. Frontend: consulta cancelable, clave por actor/proyecto/fondo, sin sondeo ni
   reintentos automáticos. Cambiar actor/proyecto desmonta el panel; un error de
   actualización oculta los datos anteriores. Los destinos se limitan a rutas
   específicas de la entidad y la evidencia externa a HTTPS sin credenciales.

No modifica tablas de matching, publicación, roles de usuarios, conexiones,
consorcios ni invitaciones. El smoke 027 añade solamente el permiso exacto de 050
al manifiesto de pruebas posteriores; 037/038 contabilizan ese único permiso nuevo
de API sin cambiar los de workers. No activa adjuntos ni cambia su implementación;
no se edita ninguna migración histórica.

## Límites deliberados

- Se examinan como máximo los 200 perfiles actualizados más recientemente por tipo
  usando Discovery 044. Hasta tres sugerencias por necesidad, ordenadas por evidencia
  y GUID para desempatar; se informa el tamaño de muestra y si fue truncada.
- `Otros` (categoría 16) no cuenta como coincidencia. Sin categorías compartidas
  no se inventan aliados; sin habilidades coincidentes no se inventan profesionales.
- País de sede de la organización solicitante ≠ países donde opera el proyecto.
  Sin país de sede o con geografía del candidato desconocida/ambigua no se afirma
  que un aliado sea internacional.
- La selección geográfica de socios se incorpora en el bloque 051 desarrollado
  posteriormente. Sin ese dato revisado, no se afirma «socio europeo» ni elegibilidad
  de un país por el solo hecho de ser extranjero.
- No se verifica automáticamente si un consorcio existente ya cumple las bases;
  se orienta a revisar el equipo. Son requisitos/necesidades a explorar, no brechas
  confirmadas ni garantías de que una invitación las cierre.
- No corrige condiciones excluyentes del solicitante (país, tipo de entidad,
  personería, experiencia, etc.), no aumenta puntajes y no calcula probabilidad de éxito.
- No hay embeddings, llamadas a modelos, proveedores externos, nuevos servicios
  cloud ni temporizadores. La lectura explícita puede despertar la SQL bajo demanda.

## Publicación pendiente

Preparar un cambio aislado desde el último main, sin adjuntos/infra/workers pausados.
Publicar código revisado; después aplicar 050 + 051 y desplegar API antes del frontend.
Ejecutar aceptación autenticada en dev con un proyecto propio, fondo publicado y
clasificación revisada; comprobar también un contexto sin perfiles aptos.
No marcar «desplegado» por haber ejecutado un preflight con rollback.

Fuera de este bloque: FundsforNGOs requiere acceso autorizado; adjuntos y seguridad
adicional permanecen en pausa por decisión del usuario; aceptación con usuarios
reales continúa separada de las pruebas sintéticas.
