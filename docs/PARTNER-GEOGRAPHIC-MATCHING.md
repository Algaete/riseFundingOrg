# Matching geográfico de aliados

## Estado — 2026-09-12

Desarrollado localmente sobre el bloque de apoyos 050. **No publicado ni desplegado**.
Azure dev mantiene el release `3784dc8`, con migraciones definitivas hasta 049.
No activa adjuntos, proveedores de seguridad, temporizadores ni servicios de pago.

Preflight real de SQL dev aprobado: 050 y 051, siete lotes de migración,
51/51 smokes y 23 comprobaciones de resultados del mapa. Se revirtieron migraciones
y fixtures. La regla temporal de una IP se retiró; una lectura independiente confirmó
`[]`. SQL conserva `GP_S_Gen5`, mínimo 0,5/máximo 1 vCore, autopausa 60 minutos.
La prueba puede despertar SQL bajo demanda; no equivale a costo cero ni a despliegue.

Validación de código: 987 pruebas unitarias .NET, 355 HTTP con repositorios
simulados y 1.078 frontend aprobadas; lint, build y tipos E2E correctos.
Regresión de navegador: 216 aprobadas, una omitida porque localhost no ofrece
metadatos de release Azure. Incluye edición y matching a 320/1024 px, ES/EN,
accesibilidad, conservación del borrador ante conflicto, ausencia de escrituras
automáticas y consulta bajo demanda. Capturas de móvil/escritorio inspeccionadas.
No había navegador conectado mediante la habilidad disponible; las verificaciones
se ejecutaron con Playwright local, sesiones sintéticas y API bloqueada por defecto.

La regresión detectó un manifiesto unitario que aún enumeraba permisos solo hasta
047, aunque el smoke SQL ya contemplaba el permiso exacto de 050. Se actualizó la
prueba para incluir 050/051 (36 procedimientos posteriores, sin nuevos grants en
051); el segundo recorrido completo .NET quedó aprobado. También se verifica que
quitar un país tras guardar retire el aviso de éxito y use el nuevo ETag al confirmar.

## Uso

En **Administración → Fondos → Gestionar → Revisar clasificación**, el editor
puede declarar la geografía de las **sedes de las organizaciones aliadas**:

- Pendiente de confirmar: no se inventa una restricción ni se presume alcance global.
- Sin restricción: afirmación editorial explícita respaldada por las bases.
- Países/regiones específicos: selección múltiple; unión de países concretos y
  miembros de los grupos seleccionados. Debe existir al menos una selección.

La fuente vinculada, versión de contenido, MFA administrativo, ETag, clave de
idempotencia y auditoría siguen siendo obligatorios según el flujo existente.
Guardar esta clasificación **no publica** una oportunidad.

En **Matching → Cómo abordar los requisitos → Buscar apoyos para este fondo**,
las organizaciones sugeridas deben compartir un área de impacto y tener sede
en un país admitido si hay una restricción específica vigente. Si además se exige
socio internacional, su sede debe ser distinta de la organización solicitante.
La ubicación operativa del proyecto no sustituye al país de sede de la organización.
Se muestra la selección aplicada y la sede declarada del candidato.

Sin sede conocida no se afirma una coincidencia específica/internacional. Sin
clasificación vigente, las necesidades declaradas del proyecto pueden orientar
sugerencias, pero la geografía del socio se señala como pendiente de confirmar.
Una clasificación geográfica inválida no devuelve organizaciones como compatibles:
requiere revisión. Los profesionales se evalúan por capacidades; esta restricción
de sedes de organizaciones **no se aplica a individuos**.

Una condición geográfica sin requisito de incorporar socios activa una tarjeta
condicional: «se aplica si incorporas una organización aliada». No inventa una
carencia ni presume que deba añadirse otra persona/organización al equipo.

## Catálogo y procedencia

Snapshot `partner-geography-2026-09-12`, en
`src/FundingPlatform.Core/FundingOpportunities/partner-regions.json`.
Los grupos estadísticos se obtuvieron de la [tabla oficial ONU M49](https://unstats.un.org/unsd/methodology/m49/overview/):
África 002, América 019, Asia 142, Europa 150, Oceanía 009 y América Latina/Caribe 419.
No expresan afiliación política, elegibilidad legal ni pertenencia institucional.

La [lista oficial de países de la Unión Europea](https://european-union.europa.eu/principles-countries-history/eu-countries_en)
se incorpora separadamente como `EU`, con 27 miembros (incluida su
[segunda página](https://european-union.europa.eu/principles-countries-history/eu-countries_en?page=1)).
Europa y UE no son equivalentes: Reino Unido y Suiza están en Europa M49, no en UE;
Chipre está en UE y se clasifica en Asia M49. Estos casos tienen pruebas explícitas.
No se añaden territorios asociados por vínculo político. Si las bases definen otro
conjunto, se seleccionan países concretos. No existe una inferencia de Schengen,
EEE, eurozona o elegibilidad por el mero hecho de que el financiador sea europeo.

El catálogo emplea los identificadores numéricos ISO del catálogo mundial 048.
La selección explícita permite también los países/territorios activos que no figuran
en los grupos ofrecidos. No se llama a la ONU/UE en tiempo de ejecución.

## Contrato y módulos

`FundingDiscoveryData.partnerGeography` es opcional para compatibilidad:

```json
{
  "scope": 2,
  "countryIds": [826],
  "regionCodes": ["EU"],
  "catalogVersion": "partner-geography-2026-09-12"
}
```

- Core: contrato, catálogo regional versionado y validación de estructura.
- API: el catálogo público existente añade `partnerRegions` y
  `partnerGeographyVersion`; no se abre un nuevo endpoint de escritura.
- SQL 051: función tabular del mismo snapshot y reemplazo de los procedimientos
  `FundingDiscovery_Review` y `GapRecommendations_Context`. Sin tablas ni grants
  adicionales. Se comprueba paridad exacta JSON Core/SQL en las pruebas.
- Contexto SQL: expande la unión de selecciones contra países activos. Un país
  explícito inactivo invalida la selección; un miembro regional inactivo se excluye.
- Servicio: aplica geografía antes del orden y límite de tres sugerencias por
  necesidad. Un catálogo regional obsoleto o una expansión no disponible falla
  de forma cerrada. Motor `gap-actions-v2`; no cambia los puntajes persistidos.
- Frontend: editor geográfico y resumen del matching separados, traducciones
  compartidas ES/EN. Selecciones conservadas al buscar, cambiar idioma o fallar
  el guardado. No hay guardado automático ni consulta periódica de candidatos.

Clientes antiguos que omiten/envían `null` conservan la geografía existente solo
para la **misma versión** de contenido. No pueden resucitar la de una versión vieja.
Para eliminar una restricción se envía explícitamente `scope: 0` con listas vacías.
La auditoría almacena el dato efectivo, manteniendo el hash de la solicitud para
replays idempotentes. Cambiar un catálogo regional exige un snapshot nuevo y una
revisión explícita; no se amplían automáticamente las restricciones ya revisadas.

## Límites y aceptación

Las sugerencias siguen limitadas a los 200 perfiles más recientemente actualizados
por tipo, con máximo tres por necesidad y aviso de truncamiento. Se mantienen
publicación, consentimiento, exclusión de la organización propia y bloqueos del
directorio 044. No se verifica si un consorcio existente ya satisface las bases,
no se infiere la condición desde texto, no se envían invitaciones ni se certifica
elegibilidad total. El resto de las condiciones del postulante no cambia.

Para publicar: preparar un cambio aislado **050 + 051** desde main, excluyendo
adjuntos/infra/workers pausados. Tras la autorización de publicación/despliegue,
aplicar SQL, desplegar API y finalmente frontend; ejecutar aceptación autenticada
con un proyecto propio, fondo publicado y clasificación revisada. El preflight
con rollback no sustituye esa aceptación ni deja el cambio disponible en Azure.
