# Revisión de la visión global de fundraising

**Fecha:** 17 de agosto de 2026

**Estado:** aceptada como ampliación funcional del diseño técnico

**Documento revisado:** “Plataforma Global de Fundraising e Inteligencia para ONG”
**Regla de precedencia:** cuando esta revisión contradiga el alcance funcional o el roadmap de
`FASE-0-DISENO-TECNICO.md`, esta revisión es la decisión vigente. La arquitectura base, la
seguridad y las decisiones que no se modifican continúan válidas.

## 1. Veredicto ejecutivo

La visión nueva es compatible con la arquitectura existente, pero cambia el centro funcional del
producto. FundingPlatform ya no debe entenderse solamente como un catálogo que recomienda fondos
a una organización. El agregado central de descubrimiento será el **proyecto**:

```text
Proyecto + versión del perfil de la organización
    -> Opportunity Match explicable
    -> Funder Match estratégico
    -> partner recomendado cuando existe una brecha de capacidad
```

Sí se necesita adquisición automática de oportunidades desde Internet, pero la implementación
correcta no es un crawler universal ni un proceso infinito dentro de la API. Será un pipeline
asíncrono gobernado, ejecutado por Azure Functions mediante timers y colas:

```text
fuente autorizada -> captura raw -> normalización -> deduplicación
                  -> extracción semántica -> validación -> revisión editorial
                  -> publicación -> embedding -> matching -> alertas
```

La IA no publica libremente ni navega con credenciales. Extrae y clasifica mediante salidas
estructuradas, conserva evidencia, distingue hechos de inferencias y entrega el resultado a reglas
determinísticas y a una persona revisora. Un agente de recomendación puede explicar la estrategia
después, pero no reemplaza provenance, validación ni autorización editorial.

## 2. Estado real del repositorio

| Componente | Estado actual | Diferencia frente a la nueva visión |
|---|---|---|
| Clean Architecture | Solución con `Core`, `Application`, `Infrastructure`, `Contracts`, API y Workers | Base correcta; faltan módulos y casos de uso reales |
| Azure SQL | Baseline 001 aplicado: organizaciones, oportunidades/fuentes canónicas, catálogos, plan Free y outbox | No existen todavía `Project`, `Funder`, raw/import/evidence, partners, consorcios ni donaciones |
| API ASP.NET Core | Health, readiness SQL, ProblemDetails, CORS, Swagger y DI | No existen endpoints funcionales de organización, proyectos, fondos ni importación |
| Workers | Health HTTP y consumidor de humo de la cola `imports` | No existe scheduler, provider, fetch HTTP, parser, deduplicación ni IA ejecutable |
| Frontend | Shell, rutas y placeholders de organización/fondos/admin | No existen rutas de proyectos, funders, partners o marketplace público |
| IA y matching | Diseño técnico detallado | No hay servicio OpenAI, embeddings, corpus dorado ni matches persistidos |
| Fuentes web | Reglas de seguridad y compliance documentadas | No hay fuente real aprobada ni términos/robots registrados |

Conclusión: **la infraestructura de base existe, pero el scraper y el agente semántico aún no están
implementados**. La migración 001 permanece inmutable; toda ampliación será aditiva y
`FundingPlatform_*` dentro de la base compartida `res`.

## 3. Cobertura del documento conceptual

### 3.1 Ya cubierto por el diseño anterior

- identidad, membresía y tenancy por organización;
- perfil institucional normalizado y versionado;
- oportunidad canónica, fuente original, workflow editorial y trazabilidad;
- importación manual, archivo, API/RSS y web provider condicionado;
- deduplicación exacta y candidatos semánticos de duplicado;
- extracción IA con evidencia, campos `unknown` y revisión humana;
- matching híbrido, versionado, explicable y con cobertura de evidencia;
- búsqueda, favoritos, postulaciones, calendario y alertas;
- suscripciones, administración, outbox, Queue Storage y Functions;
- controles de SSRF, prompt injection, malware, robots/términos y costos IA.

### 3.2 Parcialmente cubierto y que debe corregirse

- El matching actual se diseñó principalmente para `Organization -> FundingOpportunity`; ahora el
  match principal será `Project + Organization -> FundingOpportunity`.
- `SponsorName` no sustituye un agregado `Funder`; debe quedar como texto de presentación o dato
  transitorio, no como identidad del financiador.
- `FundingSource` representa de dónde se adquirió un dato, no quién entrega el dinero.
- El tracking de postulaciones necesita enlazar organización, proyecto, oportunidad y eventualmente
  consorcio.
- El perfil público debe existir tanto para la organización como para cada proyecto publicado.
- El networking básico entra al primer MVP, aunque rooms de consorcio y colaboración compleja se
  mantienen posteriores.

### 3.3 Requisitos nuevos sin implementación ni modelo físico actual

- proyectos estructurados, versionados, públicos y con funding gap;
- funders canónicos, aliases, prioridades e historial de financiamiento;
- Opportunity Match por proyecto y Funder Match separado;
- ODS, indicadores de impacto y necesidades no monetarias;
- conexiones entre organizaciones y búsqueda de partners;
- consorcios, work packages, tareas y presupuesto por miembro;
- marketplace de proyectos y verificación visible;
- donaciones, corporate challenges y reporting de impacto;
- Proposal AI, Funding Strategy AI y Funding Readiness Score.

### 3.4 Trazabilidad funcional y prioridad

| Capacidad del documento conceptual | Entrega | Observación |
|---|---|---|
| perfil ONG y múltiples usuarios | MVP 1 | tenant y suscripción siguen en Organization |
| proyectos independientes | MVP 1 | requisito previo al matching |
| estados de proyecto | MVP 1 | estado operativo separado de publicación pública |
| funding marketplace | MVP 1 | oportunidad canónica, provenance y revisión |
| Opportunity Matching/Funding Score | MVP 1 | por proyecto y explicable |
| recomendación estratégica | MVP 1 acotado | solo desde facts/rules calculados |
| alertas, pipeline y calendario | MVP 1 | ligados a proyecto y oportunidad |
| networking/Connect | MVP 1 básico | opt-in, moderación y rate limit |
| proyecto público | MVP 1 | sin Donate hasta compliance de pagos |
| suscripción y admin | MVP 1 | gateway sandbox antes del piloto |
| Funder Matching e historial | MVP 2 | requiere datos licenciados y funder canónico |
| partner matching avanzado | MVP 2 | capacidades y complementariedad evaluadas |
| Consortium Builder | MVP 2 | colaboración, roles, documentos y tareas |
| donaciones | MVP 2 condicionado | no se reciben fondos sin revisión legal/KYC/payouts |
| corporate challenges | MVP 2 | línea B2B después del marketplace base |
| verification avanzada | MVP 2 | proyecto y organización tienen estados distintos |
| Proposal AI | MVP 3 | human review obligatorio; no inventa información |
| Funding Strategy/Readiness | MVP 3 | necesita historial y evals para no dar falsa precisión |
| similares/analytics/API enterprise | MVP 3 | controles de privacidad, licencia y agregación |

## 4. Modelo de dominio corregido

### 4.1 Agregados y límites

| Agregado/módulo | Responsabilidad |
|---|---|
| `Organization` | identidad institucional, miembros, capacidades, experiencia y verificación |
| `Project` | necesidad concreta, impacto, presupuesto, funding gap, territorio, documentos y publicación |
| `Funder` | entidad financiadora, prioridades, presencia geográfica e historial conocido |
| `FundingOpportunity` | convocatoria o mecanismo concreto con elegibilidad, montos y fechas |
| `FundingSource` | origen técnico/editorial de datos: API, RSS, sitio, archivo o carga manual |
| `Ingestion` | runs, observaciones raw, documentos, evidencia, validación y deduplicación |
| `Matching` | Opportunity Matches, Funder Matches, reglas, scores, evidencia y explicaciones |
| `Networking` | capacidades, búsqueda de partners, conexiones y mensajes iniciales |
| `Consortium` | espacio privado, miembros, roles, work packages, tareas y propuesta |
| `FundingPipeline` | seguimiento de prospectos, LOI, propuestas, resultados y calendario |
| `Donations` | intentos/transacciones, fees, reembolsos, payout/reconciliación y compliance |
| `CorporateChallenges` | necesidad corporativa estructurada, postulaciones y preselección |

`Partner` no será una copia de `Organization`: es un rol que una organización cumple respecto de
otra organización, un proyecto, una oportunidad o un consorcio.

### 4.2 Relaciones principales

```text
Organization 1 --- N Project
Organization N --- N Organization        mediante Connection/Partnership
Project      N --- N FundingOpportunity  mediante ProjectFundingMatch
Funder       N --- N FundingOpportunity  con rol Primary/CoFunder/Manager
FundingSource 1 -- N RawObservation      -- N:1 FundingOpportunity canónica
Project      1 --- N FundingApplication  N:1 FundingOpportunity
Consortium   N --- N Organization
Donation     N --- 1 Project
CorporateChallenge N --- N Project       mediante ChallengeSubmission
```

El lifecycle de proyecto mantiene dos ejes distintos:

- `ProjectStatus`: Idea, Design, SeekingFunding, PartiallyFunded, Funded, Implementing, Completed;
- `PublicationStatus`: Draft, PendingReview, Published, Rejected, Archived.

Así un proyecto puede estar buscando financiamiento sin ser público, o permanecer publicado durante
implementación. `FundingGap` nunca se persiste como un número independiente susceptible de divergir
si puede calcularse de montos confirmados en la misma moneda; si existen varias monedas, se muestra
por moneda y no se inventa conversión.

### 4.3 Modelo físico incremental recomendado

No se edita `001_initial_schema.sql`. Las migraciones futuras, en su fase correspondiente, deberán
añadir únicamente lo necesario para el vertical que se implementa.

**Núcleo de proyectos:**

- `FundingPlatform_Projects` y `FundingPlatform_ProjectVersions`;
- junctions de países, regiones, categorías, beneficiarios, tipos, tags, idiomas y ODS;
- documentos, medios e indicadores como tablas separadas cuando sus flujos se implementen;
- `FundingGap` derivado de presupuesto y financiamiento confirmado, conservando moneda.

**Funders y oportunidades:**

- `FundingPlatform_Funders`, aliases y prioridades normalizadas;
- `FundingPlatform_FundingOpportunityFunders` con rol, evitando duplicar funders en texto;
- historial de grants solamente cuando exista una fuente con licencia y provenance.

**Adquisición:**

- compliance de fuentes, snapshots/documentos, raw observations, import runs/items/errors;
- evidencia por campo, issues de validación y candidatos de duplicado;
- versión del parser/provider y headers de caché (`ETag`/`Last-Modified`).

**Matching MVP:**

- `ProjectFundingMatches` y resultados de reglas ligados a `ProjectVersion`,
  `OrganizationProfileVersion`, `FundingContentVersion`, perfil de matching y engine version;
- `OrganizationFundingMatches` solo si se conserva un modo de descubrimiento sin proyecto, rotulado
  explícitamente y sin mezclarlo con el score de proyecto.

No se usará una tabla genérica `Entities` ni relaciones polimórficas sin FK para ahorrar tablas.

## 5. Adquisición automática: el “demonio” correcto

### 5.1 Hosts y responsabilidades

- La API recibe comandos administrativos, valida autorización y crea `ImportRun + OutboxMessage`.
- `SourceSchedulerFunction` usa Timer Trigger y solicita runs vencidos de fuentes habilitadas.
- `OutboxDispatcherFunction` publica mensajes pequeños en Queue Storage.
- `FundingImportFunction` reclama el run y ejecuta el provider específico.
- `AiEnrichmentFunction` procesa únicamente raw ya persistido y validado por tamaño/tipo.
- `EditorialReview` permanece en la API/admin; un worker nunca se autoasigna permiso de publicar.

No se usa `BackgroundService` dentro de App Service ni un proceso con `while(true)`. Functions puede
reiniciar, repetir o escalar; SQL conserva el estado y las claves de idempotencia.

### 5.2 Prioridad de proveedores

1. API oficial/licenciada.
2. RSS/feed oficial.
3. importación manual o archivo controlado.
4. página pública, únicamente con fuente aprobada y adapter específico.

Cada provider implementa un contrato estable, pero su parser es propio por fuente. No se crea un
parser HTML “universal” que dependa de selectores arbitrarios configurados por un usuario.

### 5.3 Alta obligatoria de una fuente web

Antes de habilitarla se registra:

- propietario, dominio y finalidad;
- resultado y fecha de revisión de términos/licencia y `robots.txt`;
- rutas permitidas y prohibidas;
- frecuencia máxima, concurrencia, User-Agent y email de contacto;
- tamaño, redirects, MIME y timeout máximos;
- retención permitida de raw y fragmentos publicables;
- versión del provider/parser, responsable y kill switch;
- fecha de próxima revisión.

Se prohíbe evadir login, paywall, CAPTCHA, Cloudflare o controles anti-bot. La ausencia de una regla
en `robots.txt` no equivale por sí sola a una licencia de reutilización.

### 5.4 Estado durable e idempotencia

```text
Scheduled -> Fetching -> Fetched -> Parsed -> Deduplicated
          -> Enriching -> NeedsReview -> Published
          -> NoChange / Rejected / Failed / Quarantined
```

- HTTP usa caché condicional y límites por host.
- El raw es inmutable; un nuevo contenido crea otra observación.
- Retries reutilizan la misma observación y no crean otra oportunidad.
- Hash, external key, URL canónica y fingerprint anteceden a similitud semántica.
- La similitud nunca fusiona automáticamente dos oportunidades.
- Poison messages se aíslan y el run conserva un error sanitizado.

## 6. IA y agente semántico

### 6.1 Etapas separadas

1. **Extracción:** texto no confiable a JSON Schema estricto con valor, estado, evidencia y locator.
2. **Normalización:** taxonomías, moneda, fechas y enums mediante reglas/allowlists.
3. **Validación:** coherencia, completitud y requisitos críticos; `unknown` no se inventa.
4. **Deduplicación asistida:** similitud crea candidato de revisión, no merge.
5. **Embedding:** representa versiones canónicas publicadas y proyectos vigentes.
6. **Matching:** hard gates + reglas ponderadas + similitud calibrada.
7. **Recomendación:** redacta estrategia usando solo el breakdown ya calculado.

### 6.2 Límite del agente

El agente de MVP no recibe navegador libre, conexión SQL, secretos, herramienta de publicación ni
capacidad de enviar mensajes. Su entrada es un DTO allowlisted; su salida es una recomendación
revisable. Hechos, inferencias y advertencias se muestran por separado.

Una recomendación del tipo “busca un partner europeo” debe provenir de:

- requisito de partnership con evidencia en la oportunidad;
- brecha objetiva en el proyecto/organización;
- regla determinística que identifica la incompatibilidad;
- búsqueda posterior de partners autorizada por el usuario.

El LLM puede explicar esa conclusión, pero no crear el requisito ni afirmar experiencia de un
partner sin evidencia.

### 6.3 Matching revisado

El fingerprint reproducible incluye como mínimo:

```text
ProjectId + ProjectVersion
+ OrganizationId + OrganizationProfileVersion
+ FundingOpportunityId + FundingContentVersion
+ MatchingProfileId + EngineVersion + SemanticCalibrationVersion
```

Los hard gates institucionales se evalúan con el perfil de la organización. Temática, territorio,
beneficiarios, presupuesto, duración e impacto se evalúan principalmente con el proyecto. El score
conserva `RuleScore`, `SemanticScore`, puntos semánticos, coverage, razones y evidencia.

## 7. Clean Architecture y módulos

Se mantiene el monolito modular. La incorporación de proyectos o scraping no autoriza dependencias
directas desde Controllers hacia Dapper, Azure SDK, HTTP clients o OpenAI.

```text
Api / Workers
    -> Application use cases
        -> Core entities + ports
            <- Infrastructure adapters
```

Puertos nuevos o corregidos:

```csharp
IProjectRepository
IProjectApplicationService
IFunderRepository
IFunderApplicationService
IFundingSourceProvider
ISourceComplianceRepository
IImportRunRepository
IRawFundingRepository
IAiFundingExtractionService
IEmbeddingService
IProjectOpportunityMatchingService
IPartnerDiscoveryService
```

Reglas:

- `Core` no referencia ASP.NET, Dapper, OpenAI, Playwright ni Azure Functions.
- `Application` orquesta casos de uso y permisos; no contiene SQL ni selectors HTML.
- `Infrastructure` contiene Dapper, HTTP providers, Blob, Queue y adapters de IA.
- `Workers` deserializa IDs/versiones y llama un caso de uso; no duplica reglas.
- `Contracts` contiene DTO HTTP estables, nunca entidades persistentes.
- repositorios orientados a agregados; no `IRepository<T>` genérico.
- un cambio transaccional complejo usa un SP agregado o una sesión SQL explícita.

## 8. Contratos API revisados

Se conservan `/api/v1`, JSON camelCase, ProblemDetails, autorización tenant, `ETag/If-Match`,
`Idempotency-Key`, paginación server-side y `202 Accepted` para trabajo asíncrono.

### 8.1 Proyectos

| Método | Ruta | Resultado |
|---|---|---|
| `GET/POST` | `/api/v1/organizations/{organizationId}/projects` | lista/crea proyectos del tenant |
| `GET/PUT` | `/api/v1/organizations/{organizationId}/projects/{projectId}` | snapshot completo con ETag |
| `POST` | `/api/v1/organizations/{organizationId}/projects/{projectId}/publish` | publicación moderada/idempotente |
| `GET` | `/api/v1/organizations/{organizationId}/projects/{projectId}/matches` | matches vigentes y recálculo |
| `POST` | `/api/v1/organizations/{organizationId}/projects/{projectId}/match-recalculations` | `202` con URL de estado |
| `GET` | `/api/v1/projects/{slug}` | proyección pública, solo proyecto publicado |

### 8.2 Funders y oportunidades

| Método | Ruta | Resultado |
|---|---|---|
| `GET` | `/api/v1/funders` | búsqueda pública limitada |
| `GET` | `/api/v1/funders/{idOrSlug}` | perfil y oportunidades públicas |
| `GET` | `/api/v1/projects/{projectId}/funder-matches` | reservado a MVP 2 y con autorización |
| `GET` | `/api/v1/funding-opportunities` | catálogo público limitado |
| `GET` | `/api/v1/organizations/{organizationId}/projects/{projectId}/funding-opportunities` | búsqueda tenant/project-aware |

### 8.3 Administración e ingesta

| Método | Ruta | Resultado |
|---|---|---|
| `GET/POST` | `/api/v1/admin/funding-sources` | configura fuente; web inicia deshabilitada |
| `POST` | `/api/v1/admin/funding-sources/{sourceId}/compliance-reviews` | registra decisión, responsable y vigencia |
| `POST` | `/api/v1/admin/funding-sources/{sourceId}/import-runs` | `202`; exige idempotency key |
| `GET` | `/api/v1/admin/import-runs/{runId}` | progreso y contadores server-side |
| `GET` | `/api/v1/admin/import-runs/{runId}/items` | errores/candidatos paginados |
| `GET/PUT` | `/api/v1/admin/funding-opportunities/{id}` | revisión canónica con ETag |
| `POST` | `/api/v1/admin/funding-opportunities/{id}/publish` | publicación auditada |
| `POST` | `/api/v1/admin/funding-opportunities/{id}/reject` | motivo obligatorio |

El request de importación nunca contiene una URL arbitraria para que el worker la visite. Selecciona
un `sourceId` previamente autorizado; el adapter construye la URL dentro de su allowlist.

## 9. Alcance de producto revisado

### MVP 1

- autenticación y perfil de organización;
- creación/versionado/publicación de proyectos;
- funders y oportunidades canónicas;
- importación manual, archivo y una fuente oficial API/RSS;
- un web provider específico solo si supera compliance;
- extracción IA con evidencia y revisión editorial;
- Opportunity Matching por proyecto, score y explicación;
- búsqueda, alertas, pipeline/calendario básico;
- networking básico y botón Connect;
- perfil público de proyecto;
- plan Free/Premium, administración y observabilidad.

### MVP 2

- Funder Matching por historial;
- partner matching avanzado y consorcios;
- donaciones después de decisión legal/tributaria/pagos;
- corporate challenges;
- verificación avanzada e impacto/reporting.

### MVP 3

- Proposal AI;
- Funding Strategy AI y Funding Readiness;
- analytics avanzados, API enterprise y marketplace corporativo completo.

## 10. Roadmap técnico revisado

| Fase | Entrega |
|---:|---|
| 0–2 | completadas: diseño, solución base y baseline SQL |
| 3 | autenticación segura y sesiones |
| 4 | organización, membresía, onboarding y tenancy |
| 5 | proyectos estructurados, versiones y perfil público |
| 6 | funders, oportunidades y workflow editorial admin |
| 7 | adquisición durable: manual/archivo/API-RSS y, si se aprueba, un web provider |
| 8 | búsqueda, project marketplace, favoritos y postulaciones |
| 9 | matching por proyecto, extracción IA, embeddings y explicaciones |
| 10 | alertas, pipeline, calendario y networking básico |
| 11 | suscripciones, administración operativa y métricas |
| 12 | hardening, seguridad, accesibilidad, restore y piloto |

No se mueve el scraper antes de autenticación/tenancy, porque el panel editorial, la auditoría y la
autorización de fuentes dependen de ellas. Sí se pueden desarrollar adapters y contract tests con
fixtures offline mientras avanzan esas fases.

## 11. Criterios de aceptación del pipeline

- ninguna fuente web se ejecuta sin compliance vigente y kill switch;
- un retry no duplica raw, oportunidad, embedding, match ni alerta;
- cada campo crítico publicado tiene evidencia o estado `unknown` explícito;
- la IA no publica ni fusiona candidatos por sí sola;
- el enlace oficial y la fecha de verificación son visibles;
- un cambio de contenido genera versión y deja obsoleto el match anterior;
- el match puede reproducirse con snapshots/versiones registradas;
- una oportunidad draft/rejected no aparece en búsqueda, matches ni alertas;
- los workers no reciben secretos/documentos en mensajes de cola;
- tests demuestran aislamiento entre dos organizaciones y dos proyectos;
- métricas registran lag, volumen, costo, errores, duplicados y cobertura de evidencia;
- existe un corpus dorado revisado por una persona experta antes de activar matching semántico.

## 12. Decisiones de negocio todavía bloqueantes

Antes de una fuente o capacidad transaccional se debe resolver:

1. lista de las primeras fuentes y derecho/licencia de reutilización;
2. país/idioma iniciales del catálogo y frecuencia editorial;
3. taxonomía/ODS y responsable experto de calidad;
4. criterios de organización y proyecto verificados;
5. qué datos de funders históricos pueden almacenarse legalmente;
6. presupuesto/modelo IA y política de retención;
7. si las donaciones usan redirect externo, marketplace de un tercero o flujo propio;
8. entidad jurídica, KYC/AML, impuestos, chargebacks, payouts y términos antes de cobrar;
9. alcance real del networking y moderación/denuncias;
10. SLA y dataset de evaluación del piloto.

## 13. Referentes revisados

- Instrumentl confirma un flujo de matches organizado por proyecto y separa oportunidades activas
  de Funder Matches estratégicos: https://help.instrumentl.com/en/articles/8218918-what-are-matches
- GlobalGiving documenta fees variables más procesamiento y condiciones específicas para uso
  comercial de su API; sirve como referencia de complejidad, no como contrato para FundingPlatform:
  https://www.globalgiving.org/aboutus/fee/ y
  https://www.globalgiving.org/api/legal/terms-of-service/

Estos productos son referentes funcionales. No autorizan copiar datos, interfaz, modelos ni
contenido, y sus condiciones pueden cambiar.

## 14. Resultado de la revisión

La arquitectura existente se conserva. Los cambios obligatorios son:

1. introducir `Project` antes del matching;
2. separar `Funder` de `FundingSource`;
3. convertir la ingesta automática en un pipeline gobernado de Functions/colas;
4. hacer el match principal por proyecto con contexto institucional versionado;
5. limitar la IA a extracción/recomendación con evidencia y supervisión;
6. reordenar el roadmap para entregar proyectos e ingesta antes del matching;
7. diferir donaciones, consorcios y corporate challenges hasta resolver compliance y validar el
   núcleo de descubrimiento.
