# FundingPlatform — FASE 0: diseño técnico del MVP

**Estado histórico al 2026-08-25:** baseline técnico aprobado; FASE 8A completada con gate SQL aplicado hasta `018` y
Full-Text provisionado; FASE 8B completada en código local, con `019` preparada pero no aplicada ni
validada contra un entorno de base de datos; FASE 9A completada en código local y `020` preparada,
sin aplicación ni prueba contra una base de datos; FASE 9B-A completada en código local y `021`
congelada; FASE 9B-B con adapters/gobierno/explicaciones shadow completados en código local mediante
`022`/`023`; FASE 10A completada localmente mediante `024`; FASE 10B completada en código local con
networking opt-in y Connect moderado mediante `025`, todos todavía sin aplicación ni prueba contra
una base de datos o proveedor real

**Fecha de referencia:** 25 de agosto de 2026

**Actualización operativa 2026-08-27:** la infraestructura base Azure dev ya existe y Azure SQL
tiene aplicadas `001`→`028`. El preflight conjunto de la cadena local pasó con 29
migraciones/355 lotes y 29/29 smokes bajo rollback total. La corrección forward-only `029` permanece
pendiente de aplicación; Full-Text, principals runtime, bootstrap SuperAdmin y paquetes de
aplicación siguen pendientes. Las afirmaciones
históricas de “sin conexión/validación DB” incluidas en los cierres por fase describen su fecha
original y quedan supersedidas por esta actualización.

**Ampliación vigente:** la revisión de visión del 17 de agosto de 2026 incorpora proyectos,
funders, networking e ingesta gobernada. En alcance funcional, matching y roadmap prevalece
[REVISION-VISION-FUNDRAISING-GLOBAL.md](REVISION-VISION-FUNDRAISING-GLOBAL.md).

**Convención física SQL agregada:** la base `res` es compartida y todos los objetos creados para este producto usarán el prefijo `FundingPlatform_`; los nombres sin prefijo de este documento permanecen como nombres lógicos para mantener legible el modelo.
**Alcance de este documento:** diseño, esquema lógico y estado arquitectónico por fase. No contiene
credenciales ni scripts DDL ejecutables.

---

## 1. Decisión ejecutiva

FundingPlatform se construirá como un **monolito modular** con tres procesos backend desplegables:
una API ASP.NET Core, un Azure Functions general y un Azure Functions aislado para extracción
documental. React será una SPA independiente y Azure SQL será la fuente de verdad transaccional. No
se necesitan microservicios, Kubernetes, un bus empresarial ni múltiples bases de datos para validar
el producto.

`FundingPlatform.Application` concentra los casos de uso y evita que los Controllers coordinen
repositorios o que `Core` dependa de HTTP, DTO públicos o proveedores. FASE 7B agregó
`FundingPlatform.ExtractionWorkers` como host de permisos reducidos; no duplica reglas de negocio.

Las cinco hipótesis que debe validar el MVP son:

1. Una ONG completa un perfil institucional suficientemente preciso.
2. El catálogo tiene información vigente, trazable y confiable.
3. Una ONG estructura al menos un proyecto con suficiente precisión para buscar financiamiento.
4. El matching explicable por proyecto reduce el tiempo de búsqueda y descubre oportunidades relevantes.
5. Existe disposición a pagar por recomendaciones, alertas y seguimiento.

La unidad de suscripción y autorización será la **organización**, no el usuario. El sujeto principal
de matching será el **proyecto**, usando además la versión vigente del perfil institucional para
elegibilidad y capacidades. En la interfaz del MVP un usuario operará normalmente con una sola
organización; el modelo N:N permitirá múltiples organizaciones sin rediseñar la base.

## 2. Supuestos de diseño y objetivos no funcionales

### 2.1 Supuestos de capacidad inicial

Estos números no son límites rígidos; sirven para diseñar índices y pruebas realistas:

- hasta 100.000 oportunidades históricas;
- hasta 10.000 oportunidades abiertas simultáneas;
- hasta 10.000 organizaciones y 50.000 usuarios durante la primera etapa comercial;
- hasta 100 fuentes configuradas y 20.000 ítems brutos diarios;
- hasta varios millones de matches históricos, evitando calcular el producto cartesiano completo;
- documentos administrativos de hasta 25 MB en MVP;
- carga predominante de lectura; 9A calcula bajo demanda y sincrónicamente un TOP 200 acotado,
  mientras importaciones y futuros recálculos masivos permanecen asíncronos.

9A materializa bajo demanda un máximo de 200 oportunidades abiertas por ejecución y conserva el
historial relevante. Los recálculos masivos futuros precomputarán solo oportunidades activas para
proyectos aptos; no se materializará `proyectos × todos los fondos`.

### 2.2 Objetivos operativos iniciales

- Disponibilidad mensual de API: 99,5% para el piloto.
- Latencia p95 con volumen representativo: detalle menor a 400 ms; búsqueda menor a 800 ms.
- Cero accesos cruzados entre organizaciones.
- 99% de webhooks procesados en menos de dos minutos.
- Recomendaciones prioritarias de onboarding/cambio manual en 1–5 minutos; refrescos masivos de catálogo dentro de 24 horas. Mientras tanto, el sistema indica que está recalculando.
- Alertas diarias enviadas dentro de la ventana programada +15 minutos.
- Todo dato crítico extraído por IA tendrá evidencia o será `null/unknown`.
- Las funciones principales cumplirán WCAG 2.2 AA en el frontend.

## 3. Alcance funcional del MVP

### 3.1 Incluido

#### Identidad y tenancy

- Registro, verificación de email, login, logout, cierre de todas las sesiones, recuperación y cambio de contraseña.
- JWT de corta duración y refresh token rotativo almacenado solo como hash.
- Roles globales `SuperAdmin` y `Admin`.
- Roles por organización `OrganizationAdmin` y `OrganizationMember`.
- Una organización activa en la UX inicial; modelo N:N y autorización real por `organizationId`.

#### Perfil institucional

- país sede y países/regiones de operación;
- áreas de trabajo, beneficiarios, palabras clave e idiomas;
- tipo y personalidad jurídica;
- tamaño, año de fundación y experiencia previa;
- presupuesto institucional aproximado;
- rango y moneda del financiamiento buscado;
- resumen institucional y tipos de proyectos;
- porcentaje de completitud con campos críticos identificados.

#### Proyectos

- proyectos separados del perfil institucional, con versiones y estado editorial;
- problema, solución, objetivos, actividades, resultados e impacto esperado;
- geografía, beneficiarios, temática/ODS, duración y necesidades adicionales;
- presupuesto total, financiamiento confirmado, funding gap y moneda;
- perfil público moderado y vínculo con postulaciones y matches.

#### Fondos y adquisición de contenido

- creación/edición manual por administrador;
- importación CSV y, si el formato es controlado, Excel;
- una integración real API o RSS para validar el pipeline;
- carga administrativa de PDF con extracción de texto y revisión humana;
- arquitectura `IFundingSourceProvider` lista para nuevos proveedores;
- flujo `Draft → PendingReview → Published / Rejected / Archived`;
- deduplicación exacta y cola de posibles duplicados;
- URL original, fecha de recuperación, hash de contenido y evidencia por campo;
- revisión humana antes de publicar contenido generado o normalizado por IA.

No se promete un crawler universal. Un proveedor web concreto solo se habilitará tras documentar términos, `robots.txt`, frecuencia, User-Agent y responsable.

#### Descubrimiento y engagement

- búsqueda server-side con texto, taxonomías, monto, fechas y estado abierto;
- orden global por relevancia, cierre próximo, reciente y monto; compatibilidad solo en el flujo
  project-aware posterior;
- paginación server-side con tamaño máximo;
- detalle con fuente y enlace original;
- recomendaciones con score, confianza, razones, advertencias y desglose;
- favoritos y seguimiento básico de postulaciones;
- calendario interno de cierres para oportunidades guardadas/recomendadas y postulaciones; sincronización externa queda V2;
- búsquedas guardadas y alerta diaria por email.

FASE 8A materializa el catálogo organizacional protegido, su detalle completo y favoritos privados.
FASE 8B agrega un marketplace público de proyectos/organizaciones, seguimiento privado de
postulaciones y un calendario básico derivado. Un filtro describe datos declarados; no evalúa
elegibilidad, no genera score y no constituye recomendación. FASE 9A agrega compatibilidad
project-aware determinística, versionada y explicable; no usa IA o embeddings y tampoco confirma
elegibilidad ni se presenta como recomendación. FASE 9B-A agrega infraestructura de embeddings y
una evaluación corpus-level sólo en sombra, sin writeback a 9A. FASE 9B-B agrega adapters reales
gobernados y explicación administrativa shadow; su activación, evaluación real y cualquier
ampliación visible permanecen sujetas a aprobación explícita.

#### IA y matching

- extracción estructurada y resumen a través de `IAiService`;
- embeddings a través de una abstracción separada `IEmbeddingService`;
- reglas determinísticas versionadas más similitud semántica acotada;
- explicación determinística como fallback y explicación IA solo a partir del desglose calculado;
- trazabilidad de modelo, prompt/esquema, contenido de entrada y evidencia;
- caché por hash para no pagar dos veces por el mismo contenido.

El primer corte 9A implementa sólo el motor determinístico: nueve reglas, hard gates
`Pass`/`Fail`/`Unknown`, score conservador y cobertura sin renormalización. 9B-A materializa la
abstracción de embeddings, un fake local y la comparación shadow. 9B-B materializa adapters OpenAI
apagados por defecto y explicaciones estructuradas administrativas; extracción generativa,
activación y promoción no forman parte del cierre local.

#### Monetización y administración

- planes Free y Professional, mensual y anual;
- plan Organization visible con `IsPurchasable=false` y CTA “Contactar ventas”; no se cobra hasta implementar miembros/asientos/invitaciones en V2;
- entitlements y límites configurables, no comparaciones de nombres de planes en Controllers;
- un gateway real: Mercado Pago para la entidad comercial chilena;
- checkout alojado, webhook idempotente y reconciliación;
- panel administrativo mínimo para fondos, fuentes, importaciones, revisión, usuarios, organizaciones, suscripciones y errores;
- auditoría de acciones sensibles.

#### Operación

- Swagger/OpenAPI, `ProblemDetails`, Serilog, CorrelationId, Application Insights;
- `/health` y `/health/ready`;
- configuración local con `.env` ignorado por Git y placeholders en `.env.example`;
- Managed Identity y Key Vault en Azure;
- despliegue reproducible en ambientes development, staging y production.

### 3.2 Fuera del MVP y reservado para V2

- selector visible de múltiples organizaciones, invitaciones, asientos y colaboración avanzada;
- SAML, SCIM, passkeys, proveedores sociales adicionales y MFA para todos los usuarios;
  Microsoft Entra OIDC para cuentas organizacionales/personales ya se incorporó al MVP;
- permisos personalizados por equipo;
- crawling general, browser automation, OCR avanzado y conectores de alto mantenimiento;
- intento de eludir CAPTCHA, Cloudflare o cualquier control anti-bot, ahora o en V2;
- contenido totalmente multilingüe y traducción automática; el MVP prepara i18n pero publica español;
- push, WhatsApp, SMS, tiempo real y sincronización avanzada de calendarios;
- generación de postulaciones, chat/RAG con convocatorias y copiloto documental;
- segundo gateway, conciliación contable completa, facturación tributaria, cupones y prorrateos complejos;
- ranking aprendido de comportamiento, pesos personalizados por cliente y experimentos A/B;
- Azure AI Search, embeddings por fragmento y reranking avanzado;
- exportaciones masivas, BI avanzado, API pública y marketplace transaccional corporativo/donaciones;
- Redis, Service Bus, API Management, Front Door, Kubernetes, microservicios y multi-región;
- aplicaciones móviles nativas.

## 4. Arquitectura

### 4.1 Estilo

- **Monolito modular:** una aplicación lógica, módulos con límites claros y una transacción SQL disponible cuando el caso de uso lo necesita.
- **Dos hosts:** API síncrona y Functions asíncronas. Ambos reutilizan `Application`, `Core` e `Infrastructure`.
- **Sin CQRS framework ni generic repository:** Commands/queries pueden existir como modelos simples; se crean repositorios orientados a agregados y consultas reales.
- **Dapper como acceso principal:** todos los repositorios de negocio usan Dapper. SQL complejo vive en stored procedures, nunca en Controllers.
- **Azure SQL como sistema de registro:** Blob contiene binarios y snapshots grandes; índices externos, si llegan en V2, son reconstruibles.
- **Procesos idempotentes:** timers y mensajes pueden ejecutarse más de una vez sin duplicar pagos, fondos, matches ni notificaciones.

Flujo obligatorio de una petición:

```text
Controller
  → IApplicationService
    → ApplicationService
      → IRepository / gateway port
        → DapperRepository / adapter
          → Stored Procedure o SQL parametrizado
```

### 4.2 Diagrama de contexto

```text
[Usuario / Administrador]
          |
          v
[React + TypeScript + Vite]
[Azure Static Web Apps]
          |
          | HTTPS, JSON, JWT
          v
[ASP.NET Core API · Azure Container Apps Consumption]
          |
          +----------> [Azure SQL]
          |              datos transaccionales,
          |              búsqueda y vectores MVP
          |
          +----------> [Azure Blob Storage]
          |              PDF, Excel/CSV, HTML y raw grandes
          |
          +----------> [Proveedor IA gobernado 9B-B · apagado por defecto]
          |
          +----------> [Mercado Pago mediante IPaymentGateway]
          |
          +----------> [Proveedor email]
          |
          +----------> [ImportRuns + futuros recálculos masivos en Azure Queue Storage]
                             |
                             v
                [Azure Functions .NET 10 isolated]
                  timers + procesamiento asíncrono
                             |
               +-------------+-------------+
               |             |             |
             ingesta        IA          matching/alertas

[API + Functions] ──> [Serilog + Application Insights + Azure Monitor]
[Key Vault + Managed Identity] ──> secretos y acceso entre servicios
```

### 4.3 Pipeline de ingesta

```text
Fuente aprobada
  → ImportRun creado (Queued)
  → RawFundingOpportunity + snapshot/archivo
  → parseo y normalización
  → deduplicación exacta
  → detección de candidato duplicado
  → extracción IA estructurada
  → validación sintáctica y reglas de calidad
  → revisión humana si corresponde
  → FundingOpportunity canónico en revisión
  → aprobación humana y publicación
  → embedding versionado de la versión publicada
  → recálculo de matches afectados
  → alertas idempotentes
```

Cada flecha actualiza un estado persistido. Un reinicio continúa desde la última etapa confirmada; no reinicia silenciosamente todo el lote.

### 4.4 Arquitectura de frontend

```text
src/
  api/            cliente HTTP, refresh, ProblemDetails
  app/            router, providers y layout raíz
  components/     componentes compartidos y shadcn/ui
  features/       auth, organizations, funding, matching, billing, admin
  hooks/          hooks transversales pequeños
  i18n/           configuración y catálogos de traducción
  pages/          composición de rutas; poca lógica
  types/          tipos generados/compartidos desde OpenAPI
  utils/          fecha, moneda, texto y guards puros
```

TanStack Query controla server state y sus claves siempre incluyen `organizationId` cuando corresponde. React Hook Form + Zod controlan formularios. Context se limita a sesión, organización activa, tema y locale; no se agrega Redux. El access token vive en memoria y las renovaciones concurrentes se coordinan dentro de la pestaña y entre pestañas con Web Locks/BroadcastChannel.

## 5. Estructura de solución propuesta

```text
FundingPlatform.sln

src/
  FundingPlatform.Api/
  FundingPlatform.Application/       # ajuste recomendado
  FundingPlatform.Core/
  FundingPlatform.Infrastructure/
  FundingPlatform.Workers/
  FundingPlatform.ExtractionWorkers/
  FundingPlatform.Contracts/

frontend/
  funding-platform-web/

tests/
  FundingPlatform.UnitTests/
  FundingPlatform.IntegrationTests/

tools/
  FundingPlatform.DatabaseMigrator/
  FundingPlatform.AdminCli/

database/
  Tables/
  Types/
  StoredProcedures/
  Views/
  Seed/
  Migrations/

docs/
  decisions/
```

### 5.1 Responsabilidades

| Proyecto | Responsabilidad | No debe contener |
|---|---|---|
| `Core` | entidades, value objects, enums, reglas puras e interfaces de repositorio | ASP.NET, Dapper, Azure, DTO HTTP |
| `Application` | casos de uso, services, autorización de aplicación, validadores y mapping | SQL, SDK de proveedor, Controllers |
| `Contracts` | requests/responses públicos, paginación y errores versionados | entidades persistentes, lógica de negocio |
| `Infrastructure` | Dapper, connection factory, stores Identity, Blob, IA, email, pago y fuentes | decisiones de HTTP o UI |
| `Api` | Controllers/endpoints, middleware, JWT, policies, OpenAPI, rate limiting y DI | SQL y reglas de negocio |
| `Workers` | Functions isolated, timers/triggers y composición del host | reglas duplicadas de Application |
| `ExtractionWorkers` | cola/watchdog de extracción PDF con dependencias y permisos mínimos | imports, administración, cuarentena o publicación |
| `UnitTests` | dominio, services, validadores, autorización y parsers aislados | infraestructura real |
| `IntegrationTests` | repositorios/SP, API, seguridad tenant y adaptadores fake | secretos o dependencias compartidas de producción |
| `DatabaseMigrator` | aplica scripts forward-only y registra `FundingPlatform_SchemaVersions` | arrancar la API o lógica de producto |
| `AdminCli` | bootstrap controlado del primer SuperAdmin, sin password por argumento | administración cotidiana |

Dependencias permitidas:

```text
Core                    → ninguna
Contracts               → ninguna
Application             → Core + Contracts
Infrastructure          → Core + Application
Api                      → Application + Infrastructure + Contracts
Workers                  → Application + Infrastructure
ExtractionWorkers        → Application + Infrastructure
DatabaseMigrator         → Infrastructure mínimo de SQL
AdminCli                 → Application + Infrastructure
```

`Api`, `Workers` y `ExtractionWorkers` referencian `Infrastructure` únicamente como composition
roots para registrar implementaciones. No se exponen tipos de infraestructura a los casos de uso.

### 5.2 Interfaces principales

- Repositorios: `IUserRepository`, `IOrganizationRepository`, `IProjectRepository`,
  `IFunderRepository`, `IFundingOpportunityRepository`, `IMatchingRepository`,
  `IImportRepository`, `ISubscriptionRepository`, `IAlertRepository`.
- Casos de uso: `IAuthService`, `IOrganizationService`, `IProjectApplicationService`,
  `IFunderApplicationService`, `IFundingOpportunityService`, `IMatchingService`,
  `IImportService`, `ISubscriptionService`, `IAlertService`.
- Fronteras externas: `IAiService`, `IEmbeddingService`, `IBlobStorageService`, `IEmailService`, `IPaymentGateway`, `IFundingSourceProvider`.
- Datos: `ISqlConnectionFactory.CreateConnection()` y `CreateConnectionLog()`.

`CreateConnectionLog()` se conserva por el requisito, pero los logs técnicos irán a Application Insights. En MVP ambas conexiones pueden apuntar a Azure SQL; una segunda connection string será opcional y se usará solo si en producción se separan datos operativos. `ImportRuns`, auditoría y webhooks son registros de negocio y siempre se guardan de forma transaccional, no mediante el sink de logging.

La factory devuelve conexiones cerradas `SqlConnection`; cada repositorio las abre y elimina con `await using`. No mantiene una conexión singleton. Patrón del repositorio:

```csharp
public interface IFundingOpportunityRepository
{
    Task<FundingOpportunity?> GetByIdAsync(long id, CancellationToken cancellationToken);
    Task<PagedResult<FundingOpportunitySummary>> SearchAsync(
        FundingSearchCriteria criteria,
        CancellationToken cancellationToken);
    Task<long> CreateAsync(FundingOpportunity entity, CancellationToken cancellationToken);
    Task UpdateAsync(FundingOpportunity entity, byte[] rowVersion, CancellationToken cancellationToken);
    Task DeactivateAsync(long id, byte[] rowVersion, CancellationToken cancellationToken);
}
```

`FundingSearchCriteria` es un modelo interno, no el DTO HTTP; `Application` realiza el mapping. La implementación usa `QueryAsync`, `QueryFirstOrDefaultAsync`, `ExecuteAsync`, `ExecuteScalarAsync` y `QueryMultipleAsync` según la forma real del resultado.

Una conexión por operación no impide transacciones: cada cambio atómico de un agregado se concentra en un único método de repositorio y stored procedure (`Organization + membership + outbox`, `FundingOpportunity + junctions + version + outbox`, `Payment + subscription + outbox`). No se coordinan dos repositorios con conexiones independientes dentro de una supuesta transacción y no se usa `TransactionScope` alrededor de llamadas externas. Si aparece un caso legítimo que no cabe en un SP agregado, se introducirá un `ISqlSession` explícito que comparte `SqlConnection/SqlTransaction`; no se crea un Unit of Work genérico anticipadamente.

## 6. Decisiones técnicas registradas

### ADR-001 — ASP.NET Core Identity sin Entity Framework

**Decisión:** usar ASP.NET Core Identity Core con stores Dapper propios y solo las interfaces necesarias; no referenciar `Microsoft.AspNetCore.Identity.EntityFrameworkCore`.

Identity aporta hashing versionado, rehash, lockout, validadores, security stamps y una superficie de autenticación probada. Implementar esas reglas desde cero añade riesgo; usar EF únicamente para Identity introduciría dos estrategias de persistencia y migración. Los stores Dapper mapearán las tablas `Users`, `Roles` y `UserRoles`. Los tokens de verificación/reset serán opacos, de un solo uso y persistidos como SHA-256 en `UserSecurityTokens`.

Roles globales y organizacionales no se mezclan: Identity resuelve `SuperAdmin/Admin`; `OrganizationUsers` resuelve `OrganizationAdmin/OrganizationMember`.

### ADR-002 — Azure Functions en lugar de BackgroundService/Hangfire

**Decisión:** `FundingPlatform.Workers` y `FundingPlatform.ExtractionWorkers` serán Azure Functions
v4 isolated worker sobre .NET 10, preferentemente Flex Consumption, en Function Apps separadas.

Funciones iniciales: scheduler de fuentes, procesador de importación, enriquecimiento IA, embedding, matching, scheduler de alertas y despacho de email. Se evita ejecutar trabajos largos en el proceso API. Functions aporta timers, queue triggers, reintentos, escalado y aislamiento; los estados y la idempotencia permanecen en SQL. Hangfire no aporta suficiente valor adicional en MVP y `BackgroundService` dentro de la API duplica tareas al escalar.

Azure Queue Storage será el transporte desde el MVP. Se separan colas `imports`,
`document-extractions`, `ai-enrichment`, `embeddings`, `matching` y `notifications`, cada una con
poison queue y concurrencia acotada. Los mensajes solo llevan IDs/versiones, nunca documentos ni
secretos. Host storage, colas de datos y Blob documental son scopes lógicos independientes; el
aislamiento se garantiza por configuración y RBAC al recurso exacto, no obligatoriamente por una
cuenta distinta para cada scope.

Toda transacción que deba provocar trabajo inserta además un `OutboxMessage`. `OutboxDispatcherFunction` lo publica en Queue Storage y luego marca `DispatchedAtUtc`; si cae entre ambas acciones, habrá un mensaje duplicado, que el consumidor debe aceptar idempotentemente. El endpoint administrativo crea `ImportRun + OutboxMessage` y responde `202 Accepted`; no espera la importación. Como Queue Storage entrega al menos una vez, las claves de idempotencia y transiciones atómicas en SQL son obligatorias. No se introduce Service Bus ni una tabla genérica que replique Hangfire: el outbox solo garantiza entrega, no ejecuta/scheduleriza lógica de negocio.

FASE 7A materializa esta decisión para la cola `imports`: el scheduler crea runs programados, el
dispatcher publica mensajes mínimos `{runId, version}`, el consumidor reclama y renueva un lease
SQL y el watchdog repara entregas abandonadas/poison sin reencolar mientras exista un mensaje
pendiente. SQL conserva el estado durable; Queue Storage solo transporta. El worker general conserva
su host y `imports` bajo su conexión `AzureWebJobsStorage`.

FASE 7B separa tres scopes adicionales: el extractor tiene su propia conexión
`AzureWebJobsStorage` de host;
la cola de datos `document-extractions` usa `DocumentExtractionQueueStorage`; y los documentos usan
containers Blob privados. El host storage del extractor debe estar en una cuenta distinta de ambos
data planes. La cola y Blob sí pueden compartir GPv2 si los roles se asignan a la cola/container
exactos. Hay cuatro UAMI distintas: host general `H_general` y sender `S` solo se adjuntan a
`Workers`; host extractor `H_extractor` y consumer `C` solo a `ExtractionWorkers`. El mismo setting
`AzureWebJobsStorage__clientId` contiene `H_general` en una app y `H_extractor` en la otra; todos los
IDs son distintos. `S` y `C` se fijan respectivamente con
`DocumentExtractionQueueStorage__senderClientId` y `DocumentExtractionQueueStorage__clientId`.
Los IDs S/C pueden declararse en ambos hosts para validar la topología, sin adjuntar la identidad al
host que no la usa. `C` recibe solo lectura/proceso de la cola,
lectura del container confiable y el rol SQL `FundingPlatform_ExtractionWorkerRole`; no accede a
incoming/cuarentena, administración, importación ni publicación. Referencia:
[conexiones identity-based de Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/manage-connections?pivots=functions-auth-identity&tabs=bindings#define-connections).

### ADR-003 — Embeddings en Azure SQL nativo

**Decisión:** almacenar embeddings en tablas separadas mediante `VECTOR(n)`, nunca como JSON, `NVARCHAR(MAX)` ni dentro de `FundingOpportunities`.

Azure SQL y SQL Server 2025 disponen del tipo vectorial nativo y `Microsoft.Data.SqlClient` 6.1+ expone transporte binario. Para el volumen MVP se hace primero un prefiltro determinístico y luego distancia coseno exacta sobre pocos candidatos. La dimensión, modelo, versión de plantilla y hash del contenido se guardan con cada vector. Dapper utilizará un type handler acotado para `SqlVector<float>`.

No se depende inicialmente de un índice ANN/DiskANN: esa capacidad sigue en preview y no es base productiva del MVP. Microsoft recomienda búsqueda exacta cuando los predicados reducen el conjunto a menos de unos 50.000 vectores; aquí el prefiltro determinístico lo reduce mucho más. Azure AI Search se reserva para V2, cuando existan chunks, búsqueda híbrida avanzada, cientos de miles de candidatos o métricas que justifiquen otro servicio. Si el ambiente local no puede usar SQL Server 2025, se usará Azure SQL de desarrollo; la alternativa compatible con SQL Server 2022 sería Azure AI Search con solo la referencia en SQL.

Documentación oficial: [tipo `VECTOR` de SQL Server/Azure SQL](https://learn.microsoft.com/en-us/sql/t-sql/data-types/vector-data-type?view=sql-server-ver17), [búsqueda exacta y estado preview de ANN](https://learn.microsoft.com/en-us/sql/sql-server/ai/vectors?view=sql-server-ver17) y [soporte vectorial de SqlClient](https://learn.microsoft.com/en-us/sql/connect/ado-net/sql/vector-data-sql-server?view=sql-server-ver17).

### ADR-004 — Matching híbrido, versionado y explicable

**Decisión:** la IA generativa no calcula el porcentaje. Un perfil de pesos activo define reglas
determinísticas. FASE 9A implementa `deterministic-project-v1`, 100% determinístico; solo después de
backfill y evaluación con un proveedor real podría proponerse en 9B-B un perfil híbrido `v2`, donde
la similitud semántica aportaría como máximo 5%. 9B-A no crea ese perfil: calcula métricas shadow y
un flag informativo no promovible para el fake, sin cambiar 9A.

Pesos implementados en `v1`:

| Regla | Peso | Condición excluyente |
|---|---:|:---:|
| Geografía | 20% | Sí |
| Tipo de organización | 15% | Sí |
| Figura jurídica | 15% | Sí |
| Años de operación | 10% | Sí |
| Experiencia previa | 10% | Sí |
| Áreas temáticas | 10% | No |
| Beneficiarios | 5% | No |
| Tipo de proyecto | 5% | No |
| Monto | 10% | No |

Pesos del perfil híbrido `v2`:

| Regla | Peso |
|---|---:|
| Geografía | 20% |
| Tipo de organización | 20% |
| Área temática | 20% |
| Beneficiarios | 15% |
| Monto | 10% |
| Elegibilidad | 10% |
| Semántica | 5% |

En `v1`, las cinco condiciones institucionales excluyentes agregan estado `Pass`, `Fail` o
`Unknown`. Un `Fail` genera `Incompatible`, deja `CompatibilityScore` en `NULL`/“No aplica” y no
puede ser compensado por reglas blandas. Sin fallos, un hard gate desconocido genera `Datos
insuficientes`; con todos aprobados, el resultado es `Compatible`. Una convocatoria cerrada no es
“organización inelegible”: 9A la excluye del conjunto de candidatos abiertos.

Cada regla devuelve `Match`, `Partial`, `NoMatch` o `Unknown`, score 0–100, reason code, parámetros y evidencia. En `v1` y un eventual `v2`, `Unknown` no suma y reduce `EvidenceCoverage`; no se renormaliza el resto porque eso podría inflar artificialmente una ficha incompleta. Por eso se muestran dos valores:

- **CompatibilityScore:** suma ponderada conservadora sobre el 100% de criterios.
- **EvidenceCoverage:** porcentaje de peso respaldado por datos conocidos.

La UI no esconde la incertidumbre. Cada ejecución 9A fija `ProjectVersion`,
`OrganizationProfileVersion`, versiones de contenido de los fondos, versión de motor, perfil/ruleset,
año de cálculo y huella del catálogo. Conserva el desglose completo y marca `isCurrent=false` si
cambia cualquiera de esas entradas relevantes. El procesamiento es sincrónico y materializa TOP 200
en orden determinístico; una huella considera todo el catálogo abierto elegible para detectar
cambios aun cuando quede truncado.

### ADR-005 — Mercado Pago como gateway inicial

**Decisión:** implementar primero `MercadoPagoPaymentGateway`, condicionado a que la entidad que facture esté constituida en Chile y a revalidar disponibilidad/condiciones en FASE 11.

Mercado Pago Chile documenta API de suscripciones recurrentes mensuales/anuales. La lista oficial actual de países para abrir una cuenta Stripe no incluye Chile. `IPaymentGateway` mantiene aislado el proveedor para incorporar Stripe si la entidad comercial o expansión internacional lo justifica.

Fuentes oficiales: [Mercado Pago Suscripciones](https://www.mercadopago.cl/developers/es/docs/subscriptions/overview) y [disponibilidad global de Stripe](https://stripe.com/global).

### ADR-006 — Migraciones SQL forward-only

**Decisión:** scripts numerados, inmutables y forward-only; la API no migra la base al iniciar. Un migrador de consola/CI mantiene `FundingPlatform_SchemaVersions`, aplica cada script una sola vez y falla de forma visible. Los scripts de stored procedures usan `CREATE OR ALTER` en su propia entrega. No se usa EF Migrations.

Cada lote verifica antes de aplicar que apunta a la base compartida `res`, muestra las migraciones pendientes y confirma que solo administra objetos `FundingPlatform_`. Antes de un cambio de esquema se registra la ventana recuperable de los backups automáticos/PITR de Azure SQL y la versión de aplicación desplegada. Cuando una migration permite transacción, el fallo revierte esa transacción; una migration ya publicada o confirmada nunca se deshace con un script `down`, sino con una nueva migration correctiva forward-only.

Si se necesita recuperar datos, el punto en el tiempo se restaura primero en una base temporal separada para validar y extraer únicamente datos/objetos `FundingPlatform_`; nunca se sobrescribe automáticamente `res`, porque contiene objetos de otros productos. Cualquier restauración completa o cambio de destino exige coordinación explícita con el propietario de la base y sus demás consumidores. La versión anterior de la aplicación solo se redespliega cuando su contrato sigue siendo compatible con el esquema vigente.

### ADR-007 — Fechas, monedas e internacionalización

- Datos técnicos se guardan en UTC con `DATETIME2(3)`.
- Apertura/cierre que solo traen fecha se guardan como `DATE`, sin inventar hora.
- Si existe deadline exacto, además se guarda UTC, zona IANA original y precisión.
- Montos usan `DECIMAL(19,4)` y moneda ISO 4217 `CHAR(3)`; no se usa `MONEY`.
- No se convierte moneda sin tasa, fecha y proveedor trazables.
- UI inicial `es-CL`; textos usan claves de traducción, `Intl` y `Accept-Language`.

### ADR-008 — `.env` solo en desarrollo

**Decisión:** Vite mantiene su soporte nativo de `.env`; el backend usa un loader pequeño y fijado en versión para el bootstrap local. Antes de buscar el archivo, inspecciona las señales externas no vacías `ASPNETCORE_ENVIRONMENT`, `DOTNET_ENVIRONMENT` y `AZURE_FUNCTIONS_ENVIRONMENT`: puede cargar `.env` cuando no existe ninguna señal externa —caso local en que el propio archivo declara `Development`— o cuando todas las señales presentes son exactamente `Development`, sin distinguir mayúsculas. Si aparece al menos una señal `Production`, `Staging`, `Testing` o cualquier valor desconocido, omite el archivo sin cargarlo. Esta excepción para “ninguna señal” resuelve el orden de bootstrap sin convertir la ausencia de configuración de un despliegue en autorización general para usar dotenv.

La carga no sobrescribe variables existentes del proceso. `.env` no forma parte de los artefactos publicados ni de la imagen/despliegue; staging y producción fijan explícitamente el entorno antes de iniciar el proceso y suministran configuración mediante App Settings/Key Vault y Managed Identity. Así, esos ambientes toman la rama de omisión antes de inspeccionar el archivo.

`.env` y variantes locales entran a `.gitignore`; solo `.env.example` se versiona. El pipeline verifica que no se empaquete ningún `.env`. Al faltar `JWT_SECRET`, SQL u otra opción obligatoria, el host falla al arrancar con el **nombre** de la opción, nunca con su valor. No existen claves de desarrollo por defecto dentro del código.

### ADR-009 — Separar IA generativa, embeddings y score

`IAiService` expone extracción, resumen y redacción de explicación. `IEmbeddingService` genera vectores. `IMatchingService.CalculateCompatibilityAsync` calcula el score. El método tentativo `IAiService.CalculateCompatibilityAsync` se descarta deliberadamente porque colocaría una regla de negocio determinística detrás de un proveedor generativo.

```text
IAiService
  SummarizeFundingAsync(...)
  ExtractFundingDataAsync(...)
  GenerateExplanationAsync(matchBreakdown, ...)

IEmbeddingService
  GenerateAsync(SemanticEmbeddingRequest, ...)

IMatchingService
  CalculateCompatibilityAsync(organizationId, fundingOpportunityId, ...)
```

Los adapters viven en `Infrastructure`; ninguna entidad del dominio conoce modelos, SDKs o API keys.
La implementación 9B-A materializa `IEmbeddingService` con un fake léxico determinístico restringido
a `Development`/`Testing` y una evaluación shadow. 9B-B agrega el adapter HTTP gobernado de
embeddings y `IStructuredExplanationService` sobre Responses/Structured Outputs. Ambos permanecen
deshabilitados hasta que coincidan la política SQL y el fingerprint operativo; no se entrenan modelos
ni se necesita Azure ML.

### ADR-010 — Topología de sesión y cookie

Producción usará custom domains del mismo sitio, por ejemplo `app.<dominio>` y `api.<dominio>`. La cookie host-only `__Secure-fp_refresh` será `Secure`, `HttpOnly`, `SameSite=Lax`, `Path=/api/v1/auth` y con expiración igual o menor al token. Refresh/logout validan `Origin` contra allowlist incluso con Lax; CORS permite credenciales solo desde la app.

Los dominios predeterminados inconexos de Static Web Apps/Container Apps no son una topología de producción aceptable para esta sesión. Si el negocio no dispone del dominio antes de FASE 3, se debe elegir un proxy/BFF same-origin o diseñar `SameSite=None` + antiforgery y probar bloqueo de third-party cookies; no se improvisa después de implementar auth.

---

## 7. Modelo de datos inicial

### 7.1 Convenciones SQL

- esquema `dbo` en MVP para reducir complejidad operativa;
- PK interna `BIGINT IDENTITY(1,1)` en tablas de crecimiento y `INT/SMALLINT` en catálogos;
- `PublicId UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID()` en usuarios y organizaciones expuestos;
- nombres `PascalCase`, FKs explícitas y acciones de borrado restrictivas;
- `DATETIME2(3)` UTC, default `SYSUTCDATETIME()`;
- `CreatedAtUtc` y `UpdatedAtUtc` en agregados mutables;
- `ROWVERSION` para concurrencia en organización, fondo, fuente y suscripción;
- soft delete/estado solo donde existe una necesidad de historial; no un `IsDeleted` universal;
- `NVARCHAR`, URLs hasta 2048 caracteres, hashes SHA-256 como `BINARY(32)`;
- cada código monetario `CHAR(3)` referencia `Currencies(Code)`; no se aceptan strings ISO sin FK;
- `CHECK` para rangos/estados estables y FK para taxonomías configurables;
- SQL dinámico solo con columnas de orden provenientes de una allowlist; valores siempre parametrizados;
- `ON DELETE CASCADE` únicamente en tablas puente o tokens dependientes, nunca en fondos, pagos, auditoría o runs.

La primera migración de FASE 2 incluye catálogos, identidad base, organizaciones,
fondos/fuentes canónicos, entitlements Free y outbox. Matching, autenticación completa,
billing y alertas se agregan en migraciones de su fase para no congelar prematuramente detalles;
matching y alertas ya tienen artefactos locales, mientras billing continúa pendiente. FASE 6 incorporó evidence
editorial y el límite seguro de documentos. FASE 7A incorporó runs, raw inmutable y adquisición
durable desde Grants.gov; FASE 7B agregó extracción PDF, recepción Defender/Event Grid fail-closed,
RSS gobernado, retención y revisión humana de duplicados. Proyectos/funders se agregaron en FASE 5/6;
9A agrega compatibilidad project-first determinística; 9B-A prepara embeddings y evals sólo en
sombra, y 9B-B prepara adapters reales gobernados y explicaciones administrativas shadow sin
activar ni promover resultados. FASE 10A prepara búsquedas guardadas y alertas diarias apagadas por
defecto mediante `024`.

### 7.2 Catálogos normalizados

| Tabla | Clave y columnas relevantes | Restricciones/índices |
|---|---|---|
| `Countries` | `Id SMALLINT`; `Iso2 CHAR(2)`; `Iso3 CHAR(3)`; `Name NVARCHAR(120)`; `IsActive BIT` | UQ `Iso2`, UQ `Iso3` |
| `Currencies` | `Code CHAR(3)` PK; `Name NVARCHAR(120)`; `MinorUnits TINYINT`; `IsActive BIT` | ISO 4217 seed; FK desde todo monto con moneda |
| `Regions` | `Id INT`; `CountryId SMALLINT`; `Code NVARCHAR(20)`; `Name NVARCHAR(150)`; `IsActive` | UQ `(CountryId, Code)`; IX `(CountryId, IsActive, Name)` |
| `FundingCategories` | `Id INT`; `ParentId INT NULL`; `Code NVARCHAR(50)`; `Name NVARCHAR(150)`; `IsActive` | UQ `Code`; FK autorreferente restrictiva |
| `OrganizationTypes` | `Id SMALLINT`; `Code`; `Name`; `IsActive` | UQ `Code` |
| `LegalEntityTypes` | `Id SMALLINT`; `CountryId NULL`; `Code`; `Name`; `IsActive` | UQ `(CountryId, Code)`; permite conceptos globales y locales |
| `OrganizationSizes` | `Id SMALLINT`; `Code`; `Name`; `MinEmployees NULL`; `MaxEmployees NULL` | UQ `Code`; checks de rango |
| `BeneficiaryTypes` | `Id INT`; `ParentId NULL`; `Code`; `Name`; `IsActive` | UQ `Code` |
| `FundingTypes` | `Id SMALLINT`; `Code`; `Name`; `IsActive` | UQ `Code` |
| `ProjectTypes` | `Id INT`; `Code`; `Name`; `IsActive` | UQ `Code`; tipos de proyecto del onboarding |
| `Tags` | `Id BIGINT`; `Name`; `NormalizedName`; `IsApproved`; `IsActive` | UQ `NormalizedName`; moderación evita sinónimos descontrolados |
| `Languages` | `Id SMALLINT`; `IsoCode NVARCHAR(10)`; `Name`; `IsActive` | UQ `IsoCode` |

Los catálogos llevan `CreatedAtUtc` y, si son editables, `UpdatedAtUtc`. Chile y sus regiones se entregarán como seed versionado. País/región se modelan con códigos ISO; los IDs nunca se fijan en C#.

### 7.3 Identidad y seguridad

#### `Users`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID()
Email NVARCHAR(320) NOT NULL
NormalizedEmail NVARCHAR(320) NOT NULL
DisplayName NVARCHAR(150) NOT NULL
PasswordHash NVARCHAR(1000) NULL
SecurityStamp NVARCHAR(100) NOT NULL
SecurityVersion INT NOT NULL DEFAULT 1
EmailConfirmed BIT NOT NULL DEFAULT 0
TwoFactorEnabled BIT NOT NULL DEFAULT 0
Status TINYINT NOT NULL                 -- PendingActivation/PendingVerification/Active/Blocked/Disabled
AccessFailedCount INT NOT NULL DEFAULT 0
LockoutEndUtc DATETIME2(3) NULL
PreferredLocale NVARCHAR(10) NOT NULL DEFAULT 'es-CL'
LastLoginAtUtc DATETIME2(3) NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

Índices: UQ `PublicId`; UQ `NormalizedEmail`; IX `(Status, CreatedAtUtc)`. Un check solo admite `PasswordHash IS NULL` en `PendingActivation`; cualquier estado que pueda autenticar exige hash. El email original sirve para mostrar/enviar; el normalizado para identidad. Nunca se indexa ni registra la contraseña.

#### `Roles` y `UserRoles`

- `Roles`: `Id SMALLINT`, `Name`, `NormalizedName`, timestamps; UQ `NormalizedName`.
- `UserRoles`: `(UserId BIGINT, RoleId SMALLINT)` como PK compuesta; `CreatedAtUtc`, `GrantedByUserId NULL`; FKs restrictivas.
- Solo contiene roles globales. Las funciones organizacionales viven en `OrganizationUsers`.

#### `UserSecurityTokens`

```text
Id BIGINT IDENTITY PK
UserId BIGINT NOT NULL
Purpose TINYINT NOT NULL                -- VerifyEmail/ResetPassword/ChangeEmail/AdminActivation
TokenHash BINARY(32) NOT NULL
ExpiresAtUtc DATETIME2(3) NOT NULL
ConsumedAtUtc DATETIME2(3) NULL
CreatedAtUtc DATETIME2(3) NOT NULL
RequestedIpHash BINARY(32) NULL
```

UQ `TokenHash`; IX `(UserId, Purpose, ExpiresAtUtc)`. El token crudo de 256 bits solo viaja en el email y nunca se guarda.

#### MFA administrativo

- `UserAuthenticatorKeys(UserId BIGINT PK, EncryptedKey VARBINARY(1000), ConfirmedAtUtc, UpdatedAtUtc)`. La semilla TOTP debe recuperarse para validar, por lo que se cifra con Data Protection/Key Vault; no se hashea.
- `UserRecoveryCodes(Id BIGINT, UserId BIGINT, CodeHash BINARY(32), HashKeyVersion NVARCHAR(50), ConsumedAtUtc NULL, CreatedAtUtc)`; UQ `(HashKeyVersion, CodeHash)`. Cada código contiene al menos 128 bits aleatorios y se verifica con HMAC-SHA-256 usando una versión de pepper de Key Vault; no se usan códigos humanos cortos hasheados sin clave.
- `UserMfaChallenges(Id BIGINT, UserId BIGINT, SecurityVersion INT, Purpose TINYINT, TokenHash BINARY(32), ExpiresAtUtc, AttemptCount SMALLINT, MaxAttempts SMALLINT, ConsumedAtUtc NULL, CreatedIpHash BINARY(32) NULL, CreatedAtUtc)`; UQ `TokenHash`, expiración de pocos minutos y consumo único. El token opaco liga la verificación a usuario, versión de seguridad y propósito `Login/StepUp`; un challenge vencido, consumido o agotado no puede emitir sesión.
- Los stores Identity implementan las interfaces de 2FA necesarias. `Admin/SuperAdmin` no obtiene un JWT administrativo hasta completar challenge; operaciones sensibles exigen `amr=mfa` y `auth_time` reciente. La familia refresh conserva `MfaAuthenticatedAtUtc` del challenge original y nunca reemplaza ese instante por la hora de una rotación, de modo que renovar un token no rejuvenece artificialmente la MFA.

El primer SuperAdmin se crea una sola vez con `FundingPlatform.AdminCli bootstrap-superadmin --email ... --display-name ...`. La herramienta exige entrada interactiva, solicita la contraseña dos veces sin eco y no la acepta por argumentos ni por pipe. El procedimiento usa application lock, se niega si ya existe un SuperAdmin y tampoco toma control de una cuenta que ya use ese email. El primer login solo emite una sesión limitada a configurar TOTP; únicamente después del challenge se habilita `/admin`. Todo queda auditado.

`usp_User_InvalidateSessions` centraliza el incremento de `SecurityVersion`, cambio de `SecurityStamp` cuando corresponda y revocación de familias refresh. Se invoca al cambiar/resetear password, cambiar email, bloquear/deshabilitar cuenta, otorgar o retirar un rol global, resetear MFA/recovery y ejecutar una recuperación administrativa. Los cambios de membresía tenant se validan contra SQL en cada request y no dependen de claims cacheados.

#### `RefreshTokens`

```text
Id BIGINT IDENTITY PK
UserId BIGINT NOT NULL
FamilyId UNIQUEIDENTIFIER NOT NULL
TokenHash BINARY(32) NOT NULL
JwtId UNIQUEIDENTIFIER NOT NULL
ExpiresAtUtc DATETIME2(3) NOT NULL
CreatedAtUtc DATETIME2(3) NOT NULL
RevokedAtUtc DATETIME2(3) NULL
ReplacedByTokenId BIGINT NULL
RevocationReason TINYINT NULL
CreatedIpHash BINARY(32) NULL
UserAgent NVARCHAR(300) NULL
```

UQ `TokenHash`; IX `(UserId, FamilyId)`; IX de tokens vivos `(UserId, ExpiresAtUtc) WHERE RevokedAtUtc IS NULL`. La rotación bloquea el token actual, lo revoca e inserta el reemplazo en una sola transacción. Reutilizar un token revocado invalida la familia.

### 7.4 Organizaciones y perfil

#### `Organizations`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID()
CreatedByUserId BIGINT NOT NULL
Name NVARCHAR(250) NOT NULL
LegalName NVARCHAR(300) NULL
TaxIdentifier NVARCHAR(50) NULL
HomeCountryId SMALLINT NOT NULL
OrganizationTypeId SMALLINT NOT NULL
LegalEntityTypeId SMALLINT NULL
OrganizationSizeId SMALLINT NULL
EstablishedYear SMALLINT NULL
WebsiteUrl NVARCHAR(2048) NULL
Description NVARCHAR(2000) NULL
PreviousFundingExperience TINYINT NOT NULL DEFAULT 0  -- Unknown/None/HasExperience
ExperienceSummary NVARCHAR(2000) NULL
AnnualBudgetMin DECIMAL(19,4) NULL
AnnualBudgetMax DECIMAL(19,4) NULL
AnnualBudgetCurrency CHAR(3) NULL
DesiredFundingMin DECIMAL(19,4) NULL
DesiredFundingMax DECIMAL(19,4) NULL
DesiredFundingCurrency CHAR(3) NULL
ProfileStatus TINYINT NOT NULL DEFAULT 0
ProfileCompleteness DECIMAL(5,2) NOT NULL DEFAULT 0
ProfileVersion INT NOT NULL DEFAULT 1
IsActive BIT NOT NULL DEFAULT 1
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

Checks: años razonables; mínimos no negativos; `Max >= Min`; moneda requerida cuando existe monto; completitud entre 0 y 100. Los años de funcionamiento se **derivan** de `EstablishedYear`, no se almacenan y envejecen incorrectamente. `TaxIdentifier` requiere política explícita de retención, acceso y redacción; no aparecerá en logs.

#### `OrganizationUsers`

```text
OrganizationId BIGINT
UserId BIGINT
Role TINYINT NOT NULL                   -- OrganizationAdmin/OrganizationMember
MembershipStatus TINYINT NOT NULL       -- Invited/Active/Suspended/Removed
JoinedAtUtc DATETIME2(3) NULL
InvitedByUserId BIGINT NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
PK (OrganizationId, UserId)
```

Índices: `(UserId, MembershipStatus) INCLUDE (OrganizationId, Role)` para resolver tenants del usuario; `(OrganizationId, MembershipStatus, Role)` para miembros. Al menos un administrador activo se garantiza en el service/SP transaccional, no con un check fila a fila.

#### Relaciones del perfil

Todas tienen PK compuesta, FKs y `CreatedAtUtc`:

- `OrganizationCountries(OrganizationId BIGINT, CountryId SMALLINT)`;
- `OrganizationRegions(OrganizationId BIGINT, RegionId INT)`;
- `OrganizationCategories(OrganizationId BIGINT, FundingCategoryId INT)`;
- `OrganizationBeneficiaryTypes(OrganizationId BIGINT, BeneficiaryTypeId INT)`;
- `OrganizationProjectTypes(OrganizationId BIGINT, ProjectTypeId INT)`;
- `OrganizationTags(OrganizationId BIGINT, TagId BIGINT)`;
- `OrganizationLanguages(OrganizationId BIGINT, LanguageId SMALLINT, Proficiency TINYINT NULL)`.

`HomeCountryId` representa domicilio/sede. `OrganizationCountries/Regions` representa dónde trabaja. No son datos duplicados. El SP de perfil valida que cada región pertenezca a uno de los países seleccionados, o agrega su país de forma explícita según la regla acordada.

#### `OrganizationProfileVersions`

`OrganizationId`, `ProfileVersion`, `SnapshotJson`, `ContentHash BINARY(32)`, `CreatedByUserId` y `CreatedAtUtc`; PK `(OrganizationId, ProfileVersion)` y check JSON. El snapshot inmutable contiene solo los campos normalizados usados por matching. `usp_Organization_UpdateProfile` guarda la versión y actualiza el agregado en la misma transacción.

### 7.5 Fuentes, contenido bruto y oportunidades canónicas

#### `FundingSources`

```text
Id INT IDENTITY PK
Name NVARCHAR(150) NOT NULL
ProviderType TINYINT NOT NULL            -- Manual/Api/Rss/Web/File
BaseUrl NVARCHAR(2048) NULL
IsEnabled BIT NOT NULL DEFAULT 1
ScheduleCron NVARCHAR(100) NULL
MinimumDelaySeconds INT NULL
UserAgent NVARCHAR(300) NULL
TermsUrl NVARCHAR(2048) NULL
TermsReviewedAtUtc DATETIME2(3) NULL
RobotsReviewedAtUtc DATETIME2(3) NULL
LastSuccessfulRunAtUtc DATETIME2(3) NULL
ConfigurationJson NVARCHAR(MAX) NULL
SecretReference NVARCHAR(300) NULL
ProviderCode NVARCHAR(100) NULL
ScheduleIntervalSeconds INT NULL
NextRunAtUtc DATETIME2(3) NULL
ComplianceStatus TINYINT NOT NULL          -- Pending/Approved/Rejected
ComplianceApprovedAtUtc DATETIME2(3) NULL
MaxRunAttempts SMALLINT NOT NULL
RetryBaseDelaySeconds INT NOT NULL
ConsecutiveFailureCount INT NOT NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

UQ `Name` y UQ filtrado `ProviderCode`; check `ISJSON(ConfigurationJson)=1`. Configuración no
contiene secretos: `SecretReference` identifica un secreto de Key Vault o variable de entorno.
Solo una fuente habilitada, con compliance aprobado, provider registrado y ventana vencida puede
ser programada. FASE 7A usa intervalo fijo para operación reproducible; un cron arbitrario no forma
parte del scheduler implementado.

#### `FundingSourceComplianceReviews`

```text
Id BIGINT IDENTITY PK
FundingSourceId INT NOT NULL
Decision TINYINT NOT NULL                -- Pending/Approved/Rejected/Suspended
TermsResult TINYINT NOT NULL
RobotsResult TINYINT NOT NULL
EvidenceUrl NVARCHAR(2048) NULL
Notes NVARCHAR(2000) NULL
ReviewedByUserId BIGINT NOT NULL
ReviewedAtUtc DATETIME2(3) NOT NULL
ValidUntilUtc DATETIME2(3) NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

IX `(FundingSourceId, ReviewedAtUtc DESC)`. Un provider Web solo corre si su última revisión está aprobada y vigente; `FundingSources` conserva fechas resumidas para operación.

#### `FundingSourceStates`

`FundingSourceId INT PK`, `Cursor NVARCHAR(1000) NULL`, `ContinuationTokenEncrypted VARBINARY(MAX) NULL`, `FeedETag NVARCHAR(500) NULL`, `FeedLastModifiedAtUtc NULL`, `NextRunAtUtc`, `ConsecutiveFailures`, `PausedUntilUtc NULL`, `LastErrorCode NULL`, `UpdatedAtUtc` y `RowVersion`. Separa checkpoints mutables de `ConfigurationJson`; tokens sensibles se cifran o se referencian desde Key Vault.

#### `SourceDocuments`

`SourceDocumentUploadIntents` existe antes del blob:

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID()
FundingSourceId INT NOT NULL
BlobContainer NVARCHAR(100) NOT NULL
BlobObjectName NVARCHAR(1024) NOT NULL
CompletionTokenHash BINARY(32) NOT NULL
DeclaredMimeType NVARCHAR(100) NOT NULL
ExpectedContentLength BIGINT NOT NULL
MaxContentLength BIGINT NOT NULL
Status TINYINT NOT NULL                  -- Pending/Finalizing/Completed/Expired/Rejected
ExpiresAtUtc DATETIME2(3) NOT NULL
UploadedByUserId BIGINT NOT NULL
CompletedSourceDocumentId BIGINT NULL
CompletedAtUtc DATETIME2(3) NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

UQ `PublicId`, UQ `(BlobContainer, BlobObjectName)` y UQ `CompletionTokenHash`; checks exigen longitudes positivas, `ExpectedContentLength <= MaxContentLength` y timestamps/estado coherentes. El intent contiene declaraciones/límites, no hechos confiables, y solo puede completarse una vez; reintentar la misma finalización devuelve su estado ya persistido sin crear otro documento.

`SourceDocuments` se crea recién cuando la finalización server-side verificó existencia, object name, tamaño, MIME/magic bytes y hash; por eso sus metadatos siguientes sí son `NOT NULL`:

```text
Id BIGINT IDENTITY PK
FundingSourceId INT NOT NULL
OriginalFileName NVARCHAR(260) NULL
MimeType NVARCHAR(100) NOT NULL
ContentLength BIGINT NOT NULL
ContentHash BINARY(32) NOT NULL
BlobContainer NVARCHAR(100) NOT NULL
BlobObjectName NVARCHAR(1024) NOT NULL
ExtractedTextBlobObjectName NVARCHAR(1024) NULL
ScanStatus TINYINT NOT NULL
ExtractionStatus TINYINT NOT NULL
UploadedByUserId BIGINT NULL
CreatedAtUtc DATETIME2(3) NOT NULL
UpdatedAtUtc DATETIME2(3) NOT NULL
```

UQ `(BlobContainer, BlobObjectName)`, UQ auxiliar `(Id, FundingSourceId)` e IX `ContentHash`. Se guarda el nombre estable del blob, nunca una SAS URL expirable. Un documento puede originar varias oportunidades raw y reprocesarse en más de un run.

Al completar, el intent enlaza `(CompletedSourceDocumentId, FundingSourceId)` mediante FK compuesta y UQ filtrado para que un documento no provenga de dos intents ni otra fuente. `ImportRunSourceDocuments(ImportRunId BIGINT, SourceDocumentId BIGINT, FundingSourceId INT, CreatedAtUtc)` usa PK `(ImportRunId, SourceDocumentId)`. FKs compuestas a `(ImportRuns.Id, FundingSourceId)` y `(SourceDocuments.Id, FundingSourceId)` impiden mezclar fuentes; la junction permite retry/reproceso sin mutar el documento. Los `ImportRunItems` originados en archivo referencian además `(ImportRunId, SourceDocumentId)` para demostrar que el archivo participó en ese run.

#### `RawFundingOpportunities`

```text
Id BIGINT IDENTITY PK
FundingSourceId INT NOT NULL
SourceDocumentId BIGINT NULL
ExternalId NVARCHAR(250) NULL
SourceItemKeyHash BINARY(32) NOT NULL
SourceUrl NVARCHAR(2048) NULL
CanonicalUrlHash BINARY(32) NULL
RetrievedAtUtc DATETIME2(3) NOT NULL
HttpStatus SMALLINT NULL
HttpETag NVARCHAR(500) NULL
HttpLastModifiedAtUtc DATETIME2(3) NULL
SourcePublishedAtUtc DATETIME2(3) NULL
SourceUpdatedAtUtc DATETIME2(3) NULL
MimeType NVARCHAR(100) NULL
ContentHash BINARY(32) NOT NULL
RawContent NVARCHAR(MAX) NULL
RawBlobContainer NVARCHAR(100) NULL
RawBlobObjectName NVARCHAR(1024) NULL
OriginalFileName NVARCHAR(260) NULL
ContentLength BIGINT NULL
ParseStatus TINYINT NOT NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

UQ `(FundingSourceId, SourceItemKeyHash, ContentHash)`, UQ auxiliares `(Id, FundingSourceId)` y `(Id, FundingSourceId, SourceDocumentId)`; IX `(FundingSourceId, ExternalId)` filtrado cuando `ExternalId` no es null; IX `(FundingSourceId, RetrievedAtUtc DESC)`; IX `CanonicalUrlHash`; IX `ContentHash`. FK compuesta `(SourceDocumentId, FundingSourceId)` impide cruzar un archivo con otra fuente. El raw es una observación inmutable de fuente y **no pertenece a un run**: distintos reintentos lo reutilizan mediante `ImportRunItems`. Estas claves permiten además FKs compuestas desde source links/run items. Payload/documentos grandes se guardan en Blob y SQL conserva container/object name, hash, MIME y tamaño. `RawContent` solo admite texto razonablemente pequeño y jamás se renderiza directamente.

El corte físico de FASE 7A implementa el subconjunto API: `PublicId`, fuente, external/source key,
URL, MIME, `RawContent` JSON acotado, hashes y timestamps; un trigger impide `UPDATE/DELETE`. Las
columnas de documento/Blob y `ImportRunSourceDocuments` de este modelo objetivo se agregan en FASE
7B, sin reinterpretar el raw ya almacenado.

#### `FundingOpportunities`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID()
Slug NVARCHAR(320) NOT NULL
Title NVARCHAR(350) NOT NULL
Description NVARCHAR(MAX) NULL
Summary NVARCHAR(2000) NULL
SponsorName NVARCHAR(300) NOT NULL
SponsorUrl NVARCHAR(2048) NULL
ApplicationUrl NVARCHAR(2048) NULL
IssuerCountryId SMALLINT NULL
FundingTypeId SMALLINT NULL
Currency CHAR(3) NULL
MinAmount DECIMAL(19,4) NULL
MaxAmount DECIMAL(19,4) NULL
AmountStatus TINYINT NOT NULL DEFAULT 0  -- Unknown/Specified/NotDisclosed
OpenDate DATE NULL
CloseDate DATE NULL
CloseAtUtc DATETIME2(3) NULL
DeadlineTimeZoneId NVARCHAR(100) NULL
DeadlineType TINYINT NOT NULL DEFAULT 0  -- Unknown/Fixed/Rolling
DeadlinePrecision TINYINT NOT NULL DEFAULT 0 -- Unknown/Date/DateTime
EligibilityDescription NVARCHAR(MAX) NULL
Requirements NVARCHAR(MAX) NULL
Objectives NVARCHAR(MAX) NULL
AllowedActivities NVARCHAR(MAX) NULL
ExcludedActivities NVARCHAR(MAX) NULL
Restrictions NVARCHAR(MAX) NULL
TargetOrganizationsDescription NVARCHAR(2000) NULL
TargetPopulationsDescription NVARCHAR(2000) NULL
MinimumOperatingYears SMALLINT NULL
RequiresLegalEntity BIT NULL
RequiresPriorExperience BIT NULL
RequiresCofunding BIT NULL
CofundingPercentage DECIMAL(5,2) NULL
GeographicScope TINYINT NOT NULL DEFAULT 0 -- Unknown/Specified/Global
RemoteApplication TINYINT NOT NULL DEFAULT 0 -- Unknown/No/Yes
PublicationStatus TINYINT NOT NULL DEFAULT 0 -- Draft/PendingReview/Published/Rejected/Archived
PublishedAtUtc DATETIME2(3) NULL
LastVerifiedAtUtc DATETIME2(3) NULL
DataQualityScore DECIMAL(5,2) NOT NULL DEFAULT 0
ContentVersion INT NOT NULL DEFAULT 1
ContentFingerprint BINARY(32) NULL
IsActive BIT NOT NULL DEFAULT 1
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

Restricciones: UQ `PublicId`, UQ `Slug`; FK de moneda a `Currencies`; `MaxAmount >= MinAmount`; montos no negativos; `AmountStatus=Specified` exige moneda y monto, mientras `Unknown/NotDisclosed` exige ambos montos null; `RequiresCofunding=0` exige porcentaje null/0 y un porcentaje positivo exige `RequiresCofunding=1`; `CofundingPercentage` 0–100; calidad 0–100. Un índice filtrado cubre publicaciones activas. El estado “abierto” se deriva de tipo de deadline, fecha, precisión y hora actual; no se mezcla con `PublicationStatus`.

Invariantes de deadline:

- `Unknown`: no se exige fecha y genera advertencia;
- `Rolling`: `CloseDate/CloseAtUtc` son null;
- `Fixed + Date`: `CloseDate` es obligatoria y `CloseAtUtc` es null;
- `Fixed + DateTime`: `CloseDate`, `CloseAtUtc` y `DeadlineTimeZoneId` son obligatorios; `CloseDate` conserva el día local informado;
- cuando existen ambas fechas, `OpenDate <= CloseDate`; la coherencia zona/UTC se valida en Application/SP porque un `CHECK` no interpreta IANA.

Una fecha sin hora es inclusiva hasta el final de ese día en `DeadlineTimeZoneId` cuando la fuente/convocante lo determina. Si la zona es desconocida, la regla MVP mantiene abierta hasta el final del día UTC y muestra “hora exacta no informada; verifica la fuente”. `FundingPlatform_usp_FundingOpportunity_OrganizationSearch` recibe `@NowUtc`; no depende del reloj local del servidor.

`IssuerCountryId` informa el país del convocante. La elegibilidad geográfica real vive en relaciones N:N. En MVP, `Global` significa todos los países y exige no tener filas geográficas; `Specified` exige al menos un país y permite regiones; `Unknown` no tiene filas y reduce cobertura. Exclusiones del tipo “global excepto X” quedan para V2 o se mantienen como restricción textual bloqueante hasta modelarlas.

`PublicationStatus` representa workflow editorial. `IsActive` es un kill switch operativo/soft deactivation: solo `Published + IsActive` es visible. `Rejected/Archived` nunca son visibles aunque `IsActive` conserve el valor histórico; el SP de transición mantiene la matriz válida y `usp_FundingOpportunity_Deactivate` pone `IsActive=0` sin borrar.

#### `FundingOpportunityVersions`

`FundingOpportunityId`, `ContentVersion`, `SnapshotJson`, `ContentHash BINARY(32)`, `CreatedByUserId NULL`, `AiProcessingRunId NULL` y `CreatedAtUtc`; PK `(FundingOpportunityId, ContentVersion)` y check JSON. Conserva los campos y relaciones normalizados usados por búsqueda/matching. Una edición canónica o merge incrementa versión y snapshot; una transición editorial sin cambio de contenido (por ejemplo publicar) no incrementa `ContentVersion`.

#### Relaciones de oportunidad

- `FundingOpportunityCategories(FundingOpportunityId BIGINT, FundingCategoryId INT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityCountries(FundingOpportunityId BIGINT, CountryId SMALLINT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityRegions(FundingOpportunityId BIGINT, RegionId INT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityOrganizationTypes(FundingOpportunityId BIGINT, OrganizationTypeId SMALLINT, EligibilityMode TINYINT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityLegalEntityTypes(FundingOpportunityId BIGINT, LegalEntityTypeId SMALLINT, EligibilityMode TINYINT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityBeneficiaryTypes(FundingOpportunityId BIGINT, BeneficiaryTypeId INT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityProjectTypes(FundingOpportunityId BIGINT, ProjectTypeId INT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityTags(FundingOpportunityId BIGINT, TagId BIGINT, ProvenanceId BIGINT NULL)`;
- `FundingOpportunityLanguages(FundingOpportunityId BIGINT, LanguageId SMALLINT, LanguagePurpose TINYINT, ProvenanceId BIGINT NULL)`.

Cada tabla usa PK compuesta e índice inverso iniciado por el catálogo para filtros. `EligibilityMode` permite distinguir permitido/excluido cuando la fuente lo expresa. El SP valida que las regiones pertenezcan a países elegibles salvo `GeographicScope=Global`. Las descripciones textuales se conservan para matices; las relaciones alimentan filtros y reglas.

#### `FundingOpportunityRequiredDocuments`

```text
Id BIGINT IDENTITY PK
FundingOpportunityId BIGINT NOT NULL
Name NVARCHAR(300) NOT NULL
Description NVARCHAR(1000) NULL
IsMandatory BIT NULL
ProvenanceId BIGINT NULL
SortOrder SMALLINT NOT NULL DEFAULT 0
CreatedAtUtc DATETIME2(3) NOT NULL
```

#### `FundingOpportunitySourceLinks`

```text
Id BIGINT IDENTITY PK
FundingOpportunityId BIGINT NOT NULL
FundingSourceId INT NOT NULL
ExternalId NVARCHAR(250) NULL
SourceItemKeyHash BINARY(32) NOT NULL
SourceUrl NVARCHAR(2048) NULL
CanonicalUrlHash BINARY(32) NULL
LatestRawFundingOpportunityId BIGINT NULL
FirstSeenAtUtc DATETIME2(3) NOT NULL
LastSeenAtUtc DATETIME2(3) NOT NULL
IsPrimary BIT NOT NULL DEFAULT 0
IsActive BIT NOT NULL DEFAULT 1
```

UQ `(FundingSourceId, SourceItemKeyHash)`; UQ `(FundingSourceId, ExternalId)` filtrado; IX no único `(FundingSourceId, CanonicalUrlHash)`; UQ filtrado `(FundingOpportunityId) WHERE IsPrimary=1 AND IsActive=1`. FK compuesta `(LatestRawFundingOpportunityId, FundingSourceId) → RawFundingOpportunities(Id, FundingSourceId)` impide cruzar fuentes. Una convocatoria puede venir de varias fuentes sin duplicar su entidad canónica. Manual/File pueden no tener URL y una página o archivo puede contener varias convocatorias.

#### `DuplicateCandidates`

```text
Id BIGINT IDENTITY PK
RawFundingOpportunityId BIGINT NOT NULL
CandidateFundingOpportunityId BIGINT NOT NULL
DetectionMethod TINYINT NOT NULL         -- Fingerprint/Text/Semantic
SimilarityScore DECIMAL(5,2) NOT NULL
SignalsJson NVARCHAR(MAX) NULL
Decision TINYINT NOT NULL DEFAULT 0      -- Pending/Merge/Distinct/Rejected
ReviewedByUserId BIGINT NULL
ReviewedAtUtc DATETIME2(3) NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

UQ `(RawFundingOpportunityId, CandidateFundingOpportunityId)`; IX `(Decision, SimilarityScore DESC)`. Solo IDs/fingerprints exactos actualizan automáticamente; una similitud difusa espera decisión humana.

#### `FundingFieldEvidence`

```text
Id BIGINT IDENTITY PK
FundingOpportunityId BIGINT NOT NULL
FieldPath NVARCHAR(200) NOT NULL
ValueJson NVARCHAR(MAX) NULL
RawFundingOpportunityId BIGINT NULL
AiProcessingRunId BIGINT NULL
ExtractionMethod TINYINT NOT NULL       -- Manual/Parser/Ai/Derived
EvidenceText NVARCHAR(2000) NULL
SourceLocator NVARCHAR(500) NULL         -- página, selector, JSON path, celda
Confidence DECIMAL(5,2) NULL
IsSelected BIT NOT NULL DEFAULT 1
IsManualLock BIT NOT NULL DEFAULT 0
CreatedByUserId BIGINT NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

Check `ISJSON(ValueJson)` y confianza 0–100. IX `(FundingOpportunityId, FieldPath, IsSelected)`. Una corrección manual seleccionada y bloqueada no se sobrescribe en la siguiente importación. Para relaciones N:N, `ProvenanceId` apunta a esta evidencia.

`ValueJson` usa siempre un envelope JSON (`{"value": ..., "status": "known|unknown"}`), de modo que `ISJSON(ValueJson)=1` acepta también valores escalares dentro del objeto. `IsSelected=1` exige `ValueJson` no null. Se crea UQ filtrado `(FundingOpportunityId, FieldPath) WHERE IsSelected=1` para campos escalares; las colecciones usan paths estables por elemento, por ejemplo `/eligibleCountries/CL`. También se crea UQ auxiliar `(FundingOpportunityId, Id)` y las junctions referencian `(FundingOpportunityId, ProvenanceId)` para impedir evidencia cruzada entre oportunidades.

#### `FundingOpportunityValidationIssues`

```text
Id BIGINT IDENTITY PK
FundingOpportunityId BIGINT NOT NULL
FieldPath NVARCHAR(200) NULL
IssueCode NVARCHAR(100) NOT NULL
Severity TINYINT NOT NULL                -- Info/Warning/Error/Blocking
Message NVARCHAR(1000) NOT NULL
Source TINYINT NOT NULL                  -- Parser/Ai/Rule/Reviewer
Status TINYINT NOT NULL                  -- Open/Resolved/Dismissed
ResolvedByUserId BIGINT NULL
ResolvedAtUtc DATETIME2(3) NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

IX `(FundingOpportunityId, Status, Severity)` y UQ filtrado `(FundingOpportunityId, FieldPath, IssueCode) WHERE Status=Open` para que retries no dupliquen issues. `usp_FundingOpportunity_Publish` rechaza la transición si existe un issue `Blocking/Open`.

### 7.6 Ingesta e IA

#### `ImportRuns`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER NOT NULL
FundingSourceId INT NOT NULL
TriggerType TINYINT NOT NULL             -- Manual/Scheduled/Retry
Status TINYINT NOT NULL                  -- Queued/Running/Completed/Partial/Failed/Canceled
Keyword NVARCHAR(100) NOT NULL
MaximumResults INT NOT NULL              -- 1..25
CorrelationId NVARCHAR(100) NOT NULL
RequestedByUserId BIGINT NULL
ScheduleSlotUtc DATETIME2(3) NULL
IdempotencyKeyHash BINARY(32) NULL
RequestHash BINARY(32) NULL
AttemptCount SMALLINT NOT NULL
MaxAttempts SMALLINT NOT NULL
RetryBaseDelaySeconds INT NOT NULL
NextAttemptAtUtc DATETIME2(3) NOT NULL
LeaseId UNIQUEIDENTIFIER NULL
LeaseUntilUtc DATETIME2(3) NULL
RetrievedCount INT NOT NULL DEFAULT 0
CreatedCount INT NOT NULL DEFAULT 0
UpdatedCount INT NOT NULL DEFAULT 0
UnchangedCount INT NOT NULL DEFAULT 0
StagedForReviewCount INT NOT NULL DEFAULT 0
FailedCount INT NOT NULL DEFAULT 0
LastErrorCode NVARCHAR(100) NULL
LastErrorMessage NVARCHAR(1000) NULL
StartedAtUtc DATETIME2(3) NULL
CompletedAtUtc DATETIME2(3) NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3) NOT NULL
RowVersion ROWVERSION
```

IX de claim por `(Status, NextAttemptAtUtc, CreatedAtUtc, Id)`, IX de consola por fecha y UQ
auxiliar `(Id, FundingSourceId)`. Manual usa `Idempotency-Key` obligatorio y UQ por
`(RequestedByUserId, FundingSourceId, IdempotencyKeyHash)`; schedule usa UQ por fuente/slot. La misma
clave manual con otro `RequestHash` produce conflicto. `Running` exige lease vigente y comienzo;
los estados terminales exigen `CompletedAtUtc` y no conservan lease. Los cinco outcomes son
mutuamente excluyentes y su suma nunca supera `RetrievedCount`.

#### `ImportRunItems`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER NOT NULL
ImportRunId BIGINT NOT NULL
FundingSourceId INT NOT NULL
RawFundingOpportunityId BIGINT NOT NULL
FundingOpportunityId BIGINT NULL
ExternalId NVARCHAR(250) NOT NULL
SourceItemKeyHash BINARY(32) NOT NULL
NormalizedSnapshotVersion SMALLINT NOT NULL
NormalizedSnapshotJson NVARCHAR(MAX) NOT NULL
NormalizedSnapshotHash BINARY(32) NOT NULL
Status TINYINT NOT NULL                  -- Pending/Processing/Completed/Failed
OutcomeCode NVARCHAR(50) NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3) NOT NULL
CompletedAtUtc DATETIME2(3) NULL
RowVersion ROWVERSION
```

UQ `(ImportRunId, SourceItemKeyHash)` y FKs compuestas a run/raw preservan la fuente. El snapshot
normalizado versionado y hasheado se persiste junto al raw antes de staging: si el proceso cae, el
retry rehidrata los items pendientes aun cuando el proveedor ya no los devuelva. Un raw puede ser
referenciado por runs distintos, pero una sola vez por clave de fuente dentro del mismo run.

#### `ImportErrors`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER NOT NULL
ImportRunId BIGINT NOT NULL
FundingSourceId INT NOT NULL
ImportRunItemId BIGINT NULL
Stage NVARCHAR(50) NOT NULL
ErrorCode NVARCHAR(100) NOT NULL
SanitizedMessage NVARCHAR(1000) NOT NULL
IsRetryable BIT NOT NULL
OccurredAtUtc DATETIME2(3) NOT NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

FK compuesta `(ImportRunItemId, ImportRunId, FundingSourceId)` impide asociar un error a otro
run/fuente. La consola recibe códigos y mensajes sanitizados: no se guardan stack traces, tokens,
payloads raw ni secretos. El detalle técnico se correlaciona con Application Insights.

#### `AiProcessingRuns` — propuesta genérica histórica, no adoptada por 9B-B

> **Revisión 2026-08-25:** `021` usa tablas semánticas específicas y `023` usa tablas específicas
> `AiExplanation*`; ninguna materializa esta tabla genérica. El modelo siguiente se conserva sólo
> como registro de la propuesta inicial para una eventual extracción/summarization V2. No describe
> la persistencia vigente de embeddings ni explicaciones.

```text
Id BIGINT IDENTITY PK
Operation TINYINT NOT NULL               -- Extract/Summarize/Explain; embeddings usan tablas 9B-A
Provider NVARCHAR(50) NOT NULL
Model NVARCHAR(150) NOT NULL
PromptVersion NVARCHAR(50) NULL
SchemaVersion NVARCHAR(50) NULL
TemplateVersion NVARCHAR(50) NULL
InputContentHash BINARY(32) NOT NULL
CacheScopeType TINYINT NOT NULL           -- Global/Organization
SubjectType TINYINT NOT NULL              -- Raw/FundingContent/OrganizationProfile/Match
CacheKey BINARY(32) NOT NULL
ImportRunItemId BIGINT NULL
RawFundingOpportunityId BIGINT NULL
FundingOpportunityId BIGINT NULL
FundingContentVersion INT NULL
OrganizationId BIGINT NULL
OrganizationProfileVersion INT NULL
ProjectFundingMatchId BIGINT NULL
ProviderResponseId NVARCHAR(200) NULL
StructuredOutputJson NVARCHAR(MAX) NULL
OutputBlobContainer NVARCHAR(100) NULL
OutputBlobObjectName NVARCHAR(1024) NULL
Status TINYINT NOT NULL
AttemptCount SMALLINT NOT NULL DEFAULT 0
LeaseOwner NVARCHAR(100) NULL
LeaseUntilUtc DATETIME2(3) NULL
InputTokens INT NULL
OutputTokens INT NULL
EstimatedCost DECIMAL(19,6) NULL
StartedAtUtc, FinishedAtUtc DATETIME2(3) NULL
ErrorCode NVARCHAR(100) NULL
CorrelationId NVARCHAR(100) NOT NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

Si una fase posterior recupera este modelo para extracción, UQ `CacheKey` y un claim atómico deberán
evitar ejecuciones concurrentes conocidas. Scope, sujeto, versión, operación, hash, proveedor,
modelo y versiones de prompt/schema/template formarían la clave calculada en servidor. Las salidas
estructuradas requerirían allowlists, límites e aislamiento tenant; los estados terminales exigirían
`FinishedAtUtc`.

Los futuros SP de persistencia deberán validar el sujeto, no sólo el ID de run. Evidence aceptará
runs `Extract/Summarize` ligados al raw/fondo correcto, y una explicación exigirá el mismo
`ProjectFundingMatchId`, organización, proyecto, fondo y fingerprint de desglose. Ningún
`AiProcessingRunId` de otro tenant, versión o modelo podrá pasar por el solo hecho de tener una FK
formalmente válida.

La explicación 9B-B no usa Blob ni guarda una respuesta grande: persiste únicamente campos
allowlisted, hashes y uso/costo. Un crash después de que el proveedor cobre pero antes de persistir
puede exigir retry; `023` consume la reserva de forma conservadora cuando el cobro es incierto y
reproduce el mismo output si sólo se perdió el ACK.

#### Persistencia semántica 9B-A

> **Revisión 2026-08-25:** el sujeto privado es project-first. El diseño anterior de
> `OrganizationProfileEmbeddings` queda descartado para 9B-A.

La migración local `021` separa configuración, trabajo durable, vectores, presupuesto y evaluación:

- `SemanticConfigurations`: proveedor/modelo, 1536 dimensiones, purpose `matching`, templates
  `project-semantic-v1`/`opportunity-semantic-v1`, normalización `semantic-text-v1`, distancia
  coseno y calibración `cosine-linear-shadow-v1`; la configuración publicada es inmutable y sólo
  puede desactivarse one-way después de drenar jobs, evaluaciones y reservas activas;
- `SemanticEvaluationSets` y `SemanticEvaluationCases`: manifiesto humano inmutable, labels
  `0/1/2`, split `Development`/`Test` y coordenadas exactas de un match histórico 9A;
- `SemanticEmbeddingJobs`: dirección de contenido, generaciones, hasta tres intentos, claim/lease,
  retry y estados terminales, sin guardar el input;
- `SemanticEmbeddings`: un `VECTOR(1536)` nativo ligado uno-a-uno al job que lo produjo, junto con
  subject/content/input/vector hashes, proveedor/modelo/template efectivos, versión y vigencia;
- `SemanticBudgetReservations` y `SemanticUsageLedger`: reserva dura antes de invocar al proveedor,
  consumo/liberación y costo/tokens/latencia/outcome append-only, incluyendo cobro incierto;
- `SemanticEvaluationRuns`, `SemanticEvaluationRunCases`, `SemanticEvaluationItems` y
  `SemanticEvaluationRunRequests`: snapshot corpus-level, idempotencia, leases, resultados de ranking
  y reporte agregado.

La migración define ese contrato, pero no siembra una configuración activa o un corpus humano real.
Los fixtures del smoke son transaccionales y se revierten. Incorporar un manifiesto etiquetado exige
revisión experta, provenance/hashes y un cambio controlado posterior; la API no permite subir labels.

Un embedding de proyecto exige `OrganizationId + ProjectId + ProjectVersion` y es tenant-private.
Un embedding de oportunidad exige `FundingOpportunityId + FundingContentVersion` y es global porque
su entrada contiene sólo contenido editorial público. El JSON canónico se construye en el SP al
resolver el lease, usa allowlists y como máximo 8192 bytes UTF-8, y nunca se persiste. Para proyectos
se excluyen título/nombre, slugs, URLs, IDs de organización/usuario, RUT, emails, notas y billing; los
patrones riesgosos, hashes que no coinciden e inputs stale se rechazan fail-closed.

Vectores, ledger y resultados shadow son inmutables para reproducibilidad; sólo la vigencia del
vector puede transicionar de actual a retirado bajo guardas. 9B-A no implementa un procedimiento de
purga porque tampoco persiste raw, prompt, respuesta o input canónico. `022`/`023` ya modelan una
política explícita de DPA, ZDR, residencia, expiración y precios; el operador todavía debe aprobarla
para el proyecto real y acordar el ciclo de vida antes de enviar contenido.

El contrato fija 1536 dimensiones. Un cambio de dimensión, modelo, template, normalización o
calibración exige otra configuración versionada y nuevos evals. El vector sólo es utilizable cuando
coinciden el sujeto, su versión, hashes y toda la configuración. La búsqueda 9B-A usa distancia coseno
exacta; no introduce un índice aproximado ni altera los resultados 9A. La documentación oficial de
SQL Server describe el tipo [`VECTOR`](https://learn.microsoft.com/en-us/sql/sql-server/ai/vectors?view=sql-server-ver17),
y la API de embeddings admite fijar sus
[`dimensions`](https://developers.openai.com/api/reference/ruby/resources/embeddings/methods/create).
9B-B implementa adapters OpenAI exactos, pero su aprobación/promoción continúa pendiente de evals
reales.

### 7.7 Matching

> **Revisión 2026-08-24:** FASE 9A materializa en la migración local `020` el sujeto project-first.
> El esquema siguiente reemplaza el diseño original basado en matches de organización. La migración
> aún no fue aplicada ni probada contra SQL Server/Azure SQL.

#### Configuración

- `MatchingProfiles`: código, versión, versión de motor, política de desconocidos, estado y
  publicación; UQ `(Code, Version)` y un único perfil activo.
- `MatchingRules`: código/nombre, `HandlerVersion`, `IsHardGate` y estado; UQ
  `(Code, HandlerVersion)`.
- `MatchingRuleWeights`: PK `(MatchingProfileId, MatchingRuleId)`, peso 0–100 y parámetros JSON.

9A siembra un único perfil publicado `deterministic-project-v1`, motor `deterministic-sql-v1`, con
nueve reglas que suman exactamente 100%. La política fija `Unknown = 0 puntos + menor cobertura`,
sin renormalización. El procedimiento de cálculo valida en cada ejecución códigos, pesos y hard gates
exactos; la configuración publicada es inmutable y cualquier cambio exige una nueva versión.
Solo `MatchingProfiles.IsActive` puede alternarse para seleccionar/desactivar la versión operativa;
código, versión, motor, reglas, pesos y parámetros publicados no se pueden editar.

Los bordes son conservadores. Como el perfil solo conserva `EstablishedYear`, los años garantizados
son `año actual - año de constitución - 1` y el máximo posible es uno más; si el mínimo exigido cae
justo entre ambos, la regla queda `Unknown`. En figura jurídica, exclusiones y allowlists explícitas
prevalecen sobre un indicador general de “no requerida”. El conjunto abierto también es fail-closed:
acepta rolling, timestamp de cierre futuro o fecha de cierre igual/posterior a la fecha UTC actual;
una vigencia desconocida no entra al cálculo.

#### `ProjectMatchingRuns`

Cada ejecución pertenece a `OrganizationId + ProjectId` y referencia las versiones inmutables del
proyecto y perfil institucional. Además guarda snapshots de slug/título del proyecto,
código/versión del perfil y motor, `RuleSetFingerprint`, `InputFingerprint`,
`CandidateSetFingerprint`, año de cálculo, instante del catálogo, conteos y `IsTruncated`. Un índice
no único por `(ProjectId, InputFingerprint, Id DESC)` permite comparar la entrada con el run más
reciente: solo ese run se reutiliza si sigue siendo equivalente. Una secuencia A→B→A crea un run
nuevo y no revive matches ya reemplazados. 9A es sincrónica: solo persiste el estado terminal
`Completed` y limita `ProcessedCandidateCount` a 200.

Triggers bloquean `UPDATE/DELETE` de runs, resultados de reglas y requests. Los matches solo admiten
la transición controlada de vigente a reemplazado (`IsCurrent 1→0` con `SupersededAtUtc`); ningún
resultado histórico puede volver a activarse o cambiar score, clasificación, versiones o evidencia.

Para una clave nueva, la entrada se resuelve exclusivamente en servidor a partir de proyecto/perfil
vigentes, perfil de matching/ruleset, año calendario y el conjunto ordenado completo de oportunidades
abiertas y `PublicReady`. La huella del catálogo incluye también candidatos posteriores al TOP 200;
si cambian durante la transacción, la ejecución falla para que el cliente reintente de forma limpia.
Un replay de la misma clave sigue exigiendo usuario/membresía/tenant actuales, pero devuelve el
historial antes de reevaluar readiness; por eso sigue funcionando si el proyecto luego se archiva o
queda stale. La lectura calcula `isCurrent` sin reescribir ese historial.

#### `ProjectFundingMatches`

Una fila enlaza obligatoriamente run, tenant, proyecto, perfil, versiones de proyecto/perfil y
`FundingOpportunityId + FundingContentVersion`. Conserva una proyección histórica segura del fondo
(slug, título, sponsor, monto/moneda y cierre), `Classification`, `HardGateStatus`, score, rule score,
cobertura, huella, vigencia y fecha de reemplazo.

Los valores son `Compatible/Pass`, `Incompatible/Fail` y `InsufficientData/Unknown`. Un hard `Fail`
exige `CompatibilityScore = NULL`; `Compatible` o `InsufficientData` conservan un score 0–100. La UQ
filtrada `(ProjectId, FundingOpportunityId) WHERE IsCurrent=1` garantiza un solo match vigente y una
nueva ejecución reemplaza de forma atómica los anteriores.

#### `ProjectFundingMatchRuleResults`

PK `(MatchId, MatchingRuleId)`. Cada una de las nueve filas almacena `Outcome`
(`Match/Partial/NoMatch/Unknown`), `DataState`, raw/effective score, peso, puntos, `ReasonCode`,
parámetros, evidencia JSON allowlisted e `IsWarning`. Un resultado `Unknown` exige raw score nulo,
effective score cero y dato desconocido. La UI traduce el código y parámetros; no depende de texto
generado para explicar el cálculo y nunca muestra los value codes internos como texto libre.

#### `ProjectMatchingRunRequests`

La PK `(UserId, OrganizationId, ProjectId, IdempotencyKeyHash)` hace durable la idempotencia por
usuario/tenant/proyecto. `RequestHash` impide reutilizar la misma clave para otra solicitud y la FK
compuesta garantiza que el run pertenece al mismo tenant/proyecto. La clave se recibe por header,
pero sus hashes y el fingerprint de entrada se calculan en servidor.

Las funciones `ifn_ProjectMatchingOpenCandidates`, `ifn_ProjectMatchingCatalogState`,
`ifn_MatchingProfileRuleSetFingerprint` e `ifn_ProjectMatchingRunSummaries` concentran conjuntos y
vigencia. Los procedimientos `usp_ProjectMatchingRun_Create`, `List` y `Get` son la única superficie
Dapper de 9A. Todos los nombres físicos llevan el prefijo obligatorio `FundingPlatform_`.

### 7.8 Favoritos y postulaciones

#### `UserFundingFavorites`

```text
OrganizationId BIGINT
UserId BIGINT
FundingOpportunityId BIGINT
CreatedAtUtc DATETIME2(3)
PK (OrganizationId, UserId, FundingOpportunityId)
```

Existe FK compuesta real `(OrganizationId, UserId) → OrganizationUsers`, además de la policy de autorización. Índice `(OrganizationId, UserId, CreatedAtUtc DESC)`.

#### `FundingApplications`

```text
Id BIGINT IDENTITY PK
OrganizationId BIGINT NOT NULL
FundingOpportunityId BIGINT NOT NULL
OwnerUserId BIGINT NULL
Status TINYINT NOT NULL                 -- Interested/Applying/Submitted/Won/Rejected/Discarded
Notes NVARCHAR(MAX) NULL
ApplicationDate DATE NULL
RequestedAmount DECIMAL(19,4) NULL
Currency CHAR(3) NULL
ResultDate DATE NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

UQ `(OrganizationId, FundingOpportunityId)` para una postulación activa por convocatoria en MVP; FK compuesta nullable `(OrganizationId, OwnerUserId) → OrganizationUsers`; IX `(OrganizationId, Status, UpdatedAtUtc DESC)`. Historial de estados, múltiples propuestas y comentarios se difieren a V2.

### 7.9 Suscripciones, precios y pagos

#### Catálogo comercial

- `SubscriptionPlans(Id SMALLINT, Code, Name, Description, IsActive, IsPublic, IsPurchasable, SortOrder, timestamps)`; UQ `Code`.
- `SubscriptionPlanPrices(Id INT, SubscriptionPlanId, BillingInterval TINYINT, Currency CHAR(3), Amount DECIMAL(19,4), CountryId SMALLINT NULL, Provider NVARCHAR(50) NULL, ProviderPriceId NVARCHAR(200) NULL, IsActive, timestamps)`; UQ `(SubscriptionPlanId, BillingInterval, Currency, CountryId)` filtrado activo y UQ filtrado `(Provider, ProviderPriceId)` cuando el ID externo existe. Free usa precio cero y proveedor null.
- `SubscriptionPlanFeatures(SubscriptionPlanId, FeatureCode NVARCHAR(100), IsEnabled BIT, LimitValue DECIMAL(19,4) NULL, Unit NVARCHAR(30) NULL, PK compuesta)`.

Features iniciales: `funding.visible_limit`, `search.advanced`, `recommendations.enabled`, `alerts.max`, `ai.explanations_monthly`, `applications.enabled`, `calendar.enabled`, `organization.members_max`, `organizations.max_owned`, `export.enabled`.

#### `Subscriptions`

```text
Id BIGINT IDENTITY PK
OrganizationId BIGINT NOT NULL
SubscriptionPlanPriceId INT NOT NULL
Provider NVARCHAR(50) NOT NULL
ProviderCustomerId NVARCHAR(200) NULL
ProviderSubscriptionId NVARCHAR(200) NULL
ProviderUpdatedAtUtc DATETIME2(3) NULL
Status TINYINT NOT NULL                 -- Pending/Trialing/Active/PastDue/Canceled/Expired
CurrentPeriodStartUtc DATETIME2(3) NULL
CurrentPeriodEndUtc DATETIME2(3) NULL
CancelAtPeriodEnd BIT NOT NULL DEFAULT 0
CanceledAtUtc DATETIME2(3) NULL
GraceUntilUtc DATETIME2(3) NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

UQ filtrado `(Provider, ProviderSubscriptionId)`; un índice filtrado garantiza una suscripción pagada vigente por organización según los estados definidos. **Ausencia de una suscripción pagada efectiva significa Free**; no se crea una fila Free que compita con el upgrade. `SubscriptionPlans/Features` se siembran antes de búsqueda, mientras precios, subscriptions y pagos llegan en FASE 11.

#### `SubscriptionCheckoutSessions`

`Id BIGINT`, `OrganizationId`, `SubscriptionPlanPriceId`, `RequestedByUserId`, `IdempotencyKeyHash BINARY(32)`, `RequestHash BINARY(32)`, `Provider`, `ExternalReference UNIQUEIDENTIFIER`, `ProviderCheckoutId NULL`, `Status` (`Creating/Pending/Completed/Failed/Expired`), `ExpiresAtUtc`, `ClosedAtUtc NULL`, `CreatedAtUtc` y `UpdatedAtUtc`. UQ `(OrganizationId, IdempotencyKeyHash)` evita reintentos, UQ `(Provider, ExternalReference)` resuelve recuperación y UQ filtrado `(Provider, ProviderCheckoutId)` identifica el recurso remoto; UQ filtrado `(OrganizationId) WHERE ClosedAtUtc IS NULL` evita dos checkouts abiertos con claves distintas. Un check exige `ClosedAtUtc IS NULL` solo en `Creating/Pending` y no null en estados terminales. El SP bloquea la organización, cierra la sesión vencida, persiste primero una `ExternalReference` impredecible y valida transición antes de cualquier llamada externa; FK compuesta `(OrganizationId, RequestedByUserId) → OrganizationUsers`; reutilizar una clave con otro request produce `409`.

La llamada al gateway usa la referencia/idempotency key estable cuando el proveedor la soporte. Si el proveedor aceptó y el proceso cae antes de guardar `ProviderCheckoutId`, el retry **no crea otra suscripción**: deja la sesión `Creating`, consulta/reconcilia por `ExternalReference` y solo vuelve a crear tras demostrar que no existe recurso remoto. No se mantiene una transacción SQL abierta durante la llamada de red.

#### `SubscriptionPayments`

```text
Id BIGINT IDENTITY PK
SubscriptionId BIGINT NOT NULL
Provider NVARCHAR(50) NOT NULL
ProviderPaymentId NVARCHAR(200) NOT NULL
ProviderInvoiceId NVARCHAR(200) NULL
Status TINYINT NOT NULL
Amount DECIMAL(19,4) NOT NULL
Currency CHAR(3) NOT NULL
PaidAtUtc DATETIME2(3) NULL
FailureCode NVARCHAR(100) NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
```

UQ `(Provider, ProviderPaymentId)`. Nunca se marca pagado desde el redirect del navegador.

#### `PaymentWebhookEvents`

```text
Id BIGINT IDENTITY PK
Provider NVARCHAR(50) NOT NULL
ProviderEventId NVARCHAR(200) NOT NULL
ProviderRequestId NVARCHAR(200) NULL
EventType NVARCHAR(150) NOT NULL
ResourceType NVARCHAR(100) NULL
ProviderResourceId NVARCHAR(200) NULL
ProviderAction NVARCHAR(100) NULL
ProviderOccurredAtUtc DATETIME2(3) NULL
ProviderResourceVersion NVARCHAR(100) NULL
PayloadHash BINARY(32) NOT NULL
PayloadBlobContainer NVARCHAR(100) NULL
PayloadBlobObjectName NVARCHAR(1024) NULL
ReceivedAtUtc DATETIME2(3) NOT NULL
ProcessedAtUtc DATETIME2(3) NULL
Status TINYINT NOT NULL
AttemptCount SMALLINT NOT NULL DEFAULT 0
LastError NVARCHAR(2000) NULL
```

UQ `(Provider, ProviderEventId)` es la barrera idempotente. El adapter construye ese ID estable a partir del identificador de entrega/request documentado; nunca confunde el ID reutilizable del recurso con una entrega. `ProviderOccurredAtUtc`/versión ayudan a detectar eventos fuera de orden, pero el estado autoritativo se vuelve a consultar antes de una transición. El SP persiste evento + outbox antes del ACK.

#### `SubscriptionUsageCounters`

`OrganizationId`, `FeatureCode`, `PeriodStartUtc`, `PeriodEndUtc`, `UsageValue`, timestamps; PK `(OrganizationId, FeatureCode, PeriodStartUtc)`. Incrementos se hacen atómicamente. Al bajar de plan no se borra información: se bloquea crear más recursos por encima del límite.

### 7.10 Búsquedas guardadas, alertas y operación

#### `SavedSearches`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER UQ
OrganizationId BIGINT NOT NULL
UserId BIGINT NOT NULL
Name NVARCHAR(150) NOT NULL
QueryText NVARCHAR(300) NULL
SponsorText NVARCHAR(300) NULL
MinAmount DECIMAL(19,4) NULL
MaxAmount DECIMAL(19,4) NULL
Currency CHAR(3) NULL
ClosingFrom DATE NULL
ClosingTo DATE NULL
OnlyOpen BIT NOT NULL
SortCode TINYINT NOT NULL                -- cinco órdenes allowlisted de 8A
DeletedAtUtc DATETIME2(3) NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

Las selecciones múltiples se normalizan en `SavedSearchCountries`, `SavedSearchRegions`,
`SavedSearchCategories`, `SavedSearchTags`, `SavedSearchFundingTypes`,
`SavedSearchOrganizationTypes`, `SavedSearchBeneficiaryTypes`, `SavedSearchProjectTypes` y
`SavedSearchFunders`, todas con PK compuesta. La búsqueda reproduce los predicados de 8A sin CSV;
la alerta reevalúa esos filtros server-side y no usa score, matching ni una lista enviada por React.
Checks exigen `MaxAmount >= MinAmount`, moneda cuando hay monto, `ClosingTo >= ClosingFrom` y un
orden allowlisted. Una FK compuesta exige membresía usuario+organización; `DELETE` es lógico,
desactiva la alerta en la misma transacción y conserva el lineage de los logs. Un ledger separado
de create requests hace durable `Idempotency-Key + request hash`.

#### `AlertSubscriptions`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER UQ
SavedSearchId BIGINT NOT NULL
OrganizationId BIGINT NOT NULL
UserId BIGINT NOT NULL
Channel TINYINT NOT NULL                -- Email en MVP
Frequency TINYINT NOT NULL              -- Daily en MVP
PreferredHourLocal TINYINT NOT NULL
TimeZoneId NVARCHAR(100) NOT NULL
NextRunAtUtc DATETIME2(3) NOT NULL
LastRunAtUtc DATETIME2(3) NULL
IsActive BIT NOT NULL DEFAULT 1
DisabledReasonCode NVARCHAR(100) NULL
DisabledAtUtc DATETIME2(3) NULL
UnsubscribeNonce UNIQUEIDENTIFIER NOT NULL
LeaseOwner, LeaseId UNIQUEIDENTIFIER NULL
LeaseUntilUtc DATETIME2(3) NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3)
RowVersion ROWVERSION
```

UQ `(SavedSearchId, Channel)` hace que `PUT` cree, actualice o reactive una sola suscripción por
búsqueda/canal. El scheduler reclama con lease, desactiva si ya no existe usuario/membresía/tenant o
la búsqueda se eliminó, y calcula el próximo envío desde hora local + zona IANA respetando DST. Una
caída superior a 24 horas se colapsa en un único digest de recuperación, no en un correo por día
perdido.

La FK compuesta `(SavedSearchId, OrganizationId, UserId)` impide suscribir a otro tenant/usuario.
El token público de baja se firma HMAC-SHA256 sobre IDs+nonce; SQL sólo persiste el nonce, nunca el
bearer ni la clave.

#### `NotificationLogs`

```text
Id BIGINT IDENTITY PK
PublicId UNIQUEIDENTIFIER UQ
AlertSubscriptionId BIGINT NOT NULL
OrganizationId BIGINT NOT NULL
UserId BIGINT NOT NULL
ScheduledForUtc DATETIME2(3) NOT NULL
Channel TINYINT NOT NULL
TemplateCode NVARCHAR(100) NOT NULL
Locale NVARCHAR(10) NOT NULL
IdempotencyKey BINARY(32) NOT NULL
Status TINYINT NOT NULL
AttemptCount SMALLINT NOT NULL DEFAULT 0
AvailableAtUtc DATETIME2(3) NOT NULL
LeaseOwner, LeaseId UNIQUEIDENTIFIER NULL
LeaseUntilUtc DATETIME2(3) NULL
ProviderMessageId NVARCHAR(200) NULL
SentAtUtc DATETIME2(3) NULL
ErrorCode NVARCHAR(100) NULL
ItemCount SMALLINT NOT NULL
WasTruncated BIT NOT NULL
CreatedAtUtc, UpdatedAtUtc DATETIME2(3) NOT NULL
```

UQ `IdempotencyKey` y `(AlertSubscriptionId, ScheduledForUtc)` garantizan un digest por
alerta+ventana. La entrega usa claim/renew/complete/fail; un fallo confirmado antes del envío puede
reintentarse hasta el máximo y un ACK/resultado incierto termina `Unknown`, sin reenvío automático.
No se afirma reconciliación hasta que exista un adapter con consulta idempotente por referencia.
Email y body se leen/crean de forma efímera y nunca se guardan.

`NotificationLogItems(NotificationLogId BIGINT, FundingOpportunityId BIGINT, PublishedAtUtc
DATETIME2(3), PK compuesta)` conserva hasta 50 publicaciones nuevas de la ventana. No almacena
match score porque 10A no calcula compatibilidad ni elegibilidad.

#### `OutboxMessages`

```text
Id BIGINT IDENTITY PK
MessageId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID()
MessageType NVARCHAR(100) NOT NULL
AggregateType NVARCHAR(100) NOT NULL
AggregateId NVARCHAR(100) NOT NULL
PayloadJson NVARCHAR(MAX) NOT NULL       -- IDs/versiones; no documento/PII/secreto
OccurredAtUtc DATETIME2(3) NOT NULL
AvailableAtUtc DATETIME2(3) NOT NULL
DispatchedAtUtc DATETIME2(3) NULL
AttemptCount SMALLINT NOT NULL DEFAULT 0
LeaseOwner NVARCHAR(100) NULL
LeaseUntilUtc DATETIME2(3) NULL
LastError NVARCHAR(2000) NULL
```

UQ `MessageId`; IX filtrado `(AvailableAtUtc, Id) WHERE DispatchedAtUtc IS NULL`; check JSON. Cada SP de dominio relevante inserta el outbox en la misma transacción. El dispatcher reclama lotes con `UPDLOCK/READPAST`; marcar después del envío admite duplicados pero nunca pierde silenciosamente un cambio confirmado.

#### `AuditEvents`

```text
Id BIGINT IDENTITY PK
ActorUserId BIGINT NULL
OrganizationId BIGINT NULL
Action NVARCHAR(100) NOT NULL
EntityType NVARCHAR(100) NOT NULL
EntityId NVARCHAR(100) NULL
BeforeJson NVARCHAR(MAX) NULL
AfterJson NVARCHAR(MAX) NULL
CorrelationId NVARCHAR(100) NOT NULL
IpHash BINARY(32) NULL
CreatedAtUtc DATETIME2(3) NOT NULL
```

Append-only, con IX `(EntityType, EntityId, CreatedAtUtc DESC)`, `(ActorUserId, CreatedAtUtc DESC)` y `(OrganizationId, CreatedAtUtc DESC)`. Contraseñas, tokens, credenciales, cuerpos completos y URLs firmadas se redactan antes de auditar.

### 7.11 Correcciones deliberadas a la entidad original

El listado inicial mezcla responsabilidades. Se preserva toda la información, pero no necesariamente en una sola fila:

| Campo solicitado | Diseño propuesto | Motivo |
|---|---|---|
| `CountryId`, `RegionId` | `IssuerCountryId` + tablas N:N de elegibilidad | una convocatoria puede admitir varios países/regiones |
| `ExternalId`, `SourceName`, `SourceType`, `SourceUrl` | `FundingSources` + `FundingOpportunitySourceLinks` | una oportunidad canónica puede aparecer en varias fuentes |
| `RawContent` | `RawFundingOpportunities`/Blob | evita inflar y sobrescribir la entidad canónica |
| `AiSummary`, `AiEligibility` | campos canónicos + `FundingFieldEvidence`/`AiProcessingRuns` | IA es origen/provenance, no una verdad paralela permanente |
| `AiEmbeddingReference` | tabla de embeddings versionada | modelo/dimensión/cambio de contenido quedan trazables |
| `Status` | `PublicationStatus` + apertura derivada de fechas | revisión editorial y vigencia son conceptos distintos |
| `IsInternational` | `GeographicScope` | distingue global, especificado y desconocido |
| `IsRemoteApplication` | estado ternario | `false` no debe significar “no informado” |
| `TargetOrganizations/Populations` | texto descriptivo + junctions normalizados | conserva matiz y permite filtrar/matchear |

### 7.12 Relaciones principales

```text
Users ──< OrganizationUsers >── Organizations ──< Subscriptions
                                   |
                                   +──< OrganizationCountries/Categories/...
                                   +──< Projects ──< ProjectFundingMatches >── FundingOpportunities
                                   |       |
                                   |       +──< FundingApplications >───────── FundingOpportunities
                                   +──< SavedSearches ──< AlertSubscriptions

FundingSources ──< ImportRuns ──< ImportRunItems ──> RawFundingOpportunities
       |              |                                |
       |              +──< ImportRunSourceDocuments >── SourceDocuments
       +──< FundingOpportunitySourceLinks >──────────── FundingOpportunities
                                                  |
                                                  +──< Categories/Countries/Regions/...
                                                  +──< FundingFieldEvidence
                                                  +──< SemanticEmbeddings (content version)

MatchingProfiles ──< MatchingRuleWeights >── MatchingRules
       |
       +──< ProjectMatchingRuns ──< ProjectFundingMatches
                                             |
                                             +──< ProjectFundingMatchRuleResults

Projects ──< SemanticEmbeddings (project version)
SemanticConfigurations ──< SemanticEmbeddingJobs ── SemanticBudgetReservations
          |                         |                           |
          |                         +── SemanticEmbeddings         +── SemanticUsageLedger
          +──< SemanticEvaluationRuns ──< SemanticEvaluationRunCases/Items
SemanticEvaluationSets ──< SemanticEvaluationCases
```

### 7.13 Índices guiados por consultas

Además de PK/UQ/FK:

1. **Fondos publicados:** índice filtrado por `(PublicationStatus, IsActive, CloseDate, Id)` incluyendo título, sponsor, montos, moneda y tipo.
2. **Filtros N:N:** índice inverso `(CategoryId, FundingOpportunityId)`, equivalente para país, región, organización, beneficiario y tag.
3. **Texto:** catálogo Full-Text dedicado sobre `Title`, `Summary`, `Description`, `SponsorName`,
   `EligibilityDescription` y `Requirements`, con ranking primario cuando está listo y respaldo
   literal determinístico cuando falta o falla.
4. **Compatibilidad 9A:** historial `(OrganizationId, ProjectId, CreatedAtUtc DESC, Id DESC)`, UQ
   vigente `(ProjectId, FundingOpportunityId) WHERE IsCurrent=1` y detalle por
   `(MatchRunId, Classification, CompatibilityScore DESC, FundingOpportunityId)`.
5. **Semántica 9B-A:** jobs por `(Status, NextAttemptAtUtc, Id)`; vectores exactos por
   sujeto/versión/configuración; una evaluación activa global; historial de corridas por fecha y
   reservas/uso por configuración+mes. Los índices no habilitan ANN ni cambian el TOP 200 de 9A.
6. **Deadline worker:** índice filtrado `(CloseDate, Id)` para publicados activos con fecha.
7. **Importación:** `(FundingSourceId, Status, CreatedAtUtc DESC)` y runs/items por estado.
8. **Alertas/runs/outbox:** índice por `NextRunAtUtc` para alertas activas, `(Status, CreatedAtUtc)`/fuente para runs pendientes y `AvailableAtUtc` solo en outbox no despachado; las colas administran visibilidad/reintentos de ejecución.
9. **Billing:** UQ de IDs externos e índice `(OrganizationId, Status, CurrentPeriodEndUtc DESC)`.
10. **Tenancy:** todo recurso organizacional inicia sus índices de acceso por `OrganizationId`.

Los `INCLUDE` finales se decidirán con planes reales de búsqueda y pruebas de volumen. No se crean
índices especulativos para cada columna. El híbrido de 8A calcula además el complemento literal aun
cuando Full-Text está listo para no omitir coincidencias; este scan sobre seis columnas es una deuda
P2 explícita que se evaluará con planes/Query Store antes de crecer al volumen objetivo. El cierre no
afirma haber demostrado todavía el p95 con 100.000 oportunidades.

### 7.14 Stored procedures iniciales

| Procedimiento | Responsabilidad y forma de resultado |
|---|---|
| `usp_FundingOpportunity_GetById` | cabecera y result sets de categorías, geografías, beneficiarios, tags, documentos y fuentes; `QueryMultipleAsync` |
| `FundingPlatform_usp_FundingOpportunity_OrganizationSearch` | Full-Text híbrido/fallback literal, filtros por `EXISTS`/TVP, orden allowlisted, página, total y modo de búsqueda |
| `FundingPlatform_usp_FundingOpportunity_OrganizationGet` | detalle publicado completo y relaciones normalizadas, tenant-safe |
| `FundingPlatform_usp_FundingOpportunity_Favorite_List` | favoritos privados del usuario dentro de la organización, paginados |
| `FundingPlatform_usp_FundingOpportunity_Favorite_Put` | alta idempotente del favorito sin acceso cruzado |
| `FundingPlatform_usp_FundingOpportunity_Favorite_Delete` | baja idempotente del favorito sin acceso cruzado |
| `usp_FundingOpportunity_Insert` | inserta agregado y relaciones dentro de transacción; devuelve `Id`, `PublicId`, `RowVersion` |
| `usp_FundingOpportunity_Update` | optimistic concurrency por `RowVersion`, reemplazo atómico de relaciones |
| `usp_FundingOpportunity_Deactivate` | desactiva/audita sin borrar; idempotente |
| `usp_Organization_GetProfile` | perfil y relaciones en múltiples result sets |
| `usp_Organization_UpdateProfile` | valida, reemplaza relaciones, versiona y escribe `OrganizationProfileChanged` en outbox; 9B-A no genera embeddings institucionales ni recalcula 9A |
| `usp_Project_GetById` | proyecto, relaciones y versión vigente autorizados por tenant; `QueryMultipleAsync` |
| `usp_Project_Upsert` | crea/actualiza agregado, incrementa versión y escribe `ProjectChanged` en outbox |
| `FundingPlatform_usp_ProjectMatchingRun_Create` | resuelve versiones/configuración/catálogo, calcula TOP 200 sincrónico y persiste run, matches, reglas e idempotencia atómicamente |
| `FundingPlatform_usp_ProjectMatchingRun_List` | historial tenant-safe paginado con contadores, versiones y vigencia calculada |
| `FundingPlatform_usp_ProjectMatchingRun_Get` | cabecera, resultados y nueve reglas explicables de una ejecución tenant-safe |
| `FundingPlatform_usp_SemanticEmbeddingJob_BackfillEnqueue` | encola versiones vigentes allowlisted de proyecto/oportunidad para la configuración activa |
| `FundingPlatform_usp_SemanticEmbeddingJob_Claim/GetInput/RenewLease/Complete/Fail` | ciclo durable JIT, input canónico runtime-only, presupuesto y persistencia exacta del vector |
| `FundingPlatform_usp_SemanticEvaluationRun_Create/Claim/GetWork/RenewLease/Complete/Wait/Fail` | snapshot corpus-level, procesamiento shadow e idempotencia sin writeback a 9A |
| `FundingPlatform_usp_SemanticEvaluationRun_List/Get/Report` | proyección agregada para Admin/SuperAdmin con MFA, sin vectores ni input canónico |
| `usp_Subscription_GetCurrent` | suscripción efectiva + plan, precio, features y uso |
| `usp_ImportRun_Insert` | crea run `Queued` con idempotency key y correlation ID |
| `usp_ImportRun_Complete` | valida transición y consolida contadores desde items |
| `usp_RefreshToken_Rotate` | rota con bloqueo; detecta replay y revoca familia |
| `usp_User_InvalidateSessions` | incrementa versión/stamp según causa y revoca familias al cambiar credenciales, MFA, estado o rol global |
| `usp_ImportRun_Claim` | cambia atómicamente un run Queued a Running y evita dos consumidores efectivos |
| `usp_Outbox_Claim` | arrienda un lote no despachado con `UPDLOCK/READPAST` |
| `usp_Outbox_Complete` | marca despacho o libera con backoff/error sanitizado |

Todos se invocan con `commandType: CommandType.StoredProcedure`. `SqlException` se captura únicamente para agregar operación/identificadores seguros y se relanza conservando la excepción original.

### 7.15 TVP propuestos

Los TVP sí aportan valor al reemplazar listas N:N en una transacción:

```sql
CREATE TYPE dbo.SmallIntIdList AS TABLE (Id SMALLINT NOT NULL PRIMARY KEY);
CREATE TYPE dbo.IntIdList      AS TABLE (Id INT      NOT NULL PRIMARY KEY);
CREATE TYPE dbo.BigIntIdList   AS TABLE (Id BIGINT   NOT NULL PRIMARY KEY);

CREATE TYPE dbo.SmallIntEvidenceList AS TABLE
(
    Id SMALLINT NOT NULL PRIMARY KEY,
    ProvenanceId BIGINT NULL
);

CREATE TYPE dbo.IntEvidenceList AS TABLE
(
    Id INT NOT NULL PRIMARY KEY,
    ProvenanceId BIGINT NULL
);

CREATE TYPE dbo.BigIntEvidenceList AS TABLE
(
    Id BIGINT NOT NULL PRIMARY KEY,
    ProvenanceId BIGINT NULL
);

CREATE TYPE dbo.FundingOpportunityOrganizationTypeList AS TABLE
(
    OrganizationTypeId SMALLINT NOT NULL,
    EligibilityMode TINYINT NOT NULL,
    ProvenanceId BIGINT NULL,
    PRIMARY KEY (OrganizationTypeId)
);

CREATE TYPE dbo.FundingOpportunityLegalEntityTypeList AS TABLE
(
    LegalEntityTypeId SMALLINT NOT NULL PRIMARY KEY,
    EligibilityMode TINYINT NOT NULL,
    ProvenanceId BIGINT NULL
);

CREATE TYPE dbo.FundingOpportunityLanguageList AS TABLE
(
    LanguageId SMALLINT NOT NULL,
    LanguagePurpose TINYINT NOT NULL,
    ProvenanceId BIGINT NULL,
    PRIMARY KEY (LanguageId, LanguagePurpose)
);

CREATE TYPE dbo.OrganizationLanguageList AS TABLE
(
    LanguageId SMALLINT NOT NULL PRIMARY KEY,
    Proficiency TINYINT NULL
);

CREATE TYPE dbo.MatchRuleResultList AS TABLE
(
    MatchingRuleId     INT            NOT NULL,
    Outcome            TINYINT        NOT NULL,
    RawScore           DECIMAL(5,2)   NULL,
    DataState          TINYINT        NOT NULL,
    EffectiveScore     DECIMAL(5,2)   NOT NULL,
    AppliedWeight      DECIMAL(5,2)   NOT NULL,
    WeightedPoints     DECIMAL(7,4)   NOT NULL,
    ReasonCode         NVARCHAR(100)  NOT NULL,
    ReasonParametersJson NVARCHAR(MAX) NULL,
    EvidenceJson       NVARCHAR(MAX)  NULL,
    IsWarning          BIT            NOT NULL,
    PRIMARY KEY (MatchingRuleId)
);
```

Los ID-list simples sirven al perfil; las listas `*EvidenceList` conservan provenance en fondos y los TVP especializados conservan `EligibilityMode`, `LanguagePurpose` y `Proficiency`. El `DataTable` C# usará exactamente el orden y tipos CLR `Int16`, `Int32`, `Int64`, `Byte`, `Decimal`, `String`, `Boolean`; para columnas nullable enviará `DBNull.Value`, nunca `null`. Los ID-list no aceptan null. Cada definición y builder C# tendrá una prueba de integración que detecte desalineación.

---

## 8. Diseño de API

### 8.1 Convenciones

- Base: `/api/v1` desde el comienzo.
- JSON `camelCase`; fechas ISO-8601; montos siempre acompañados de moneda.
- IDs públicos de organización/usuario como UUID; fondos aceptan `PublicId` o slug según endpoint.
- Contexto tenant visible en la ruta: `/organizations/{organizationId}/...`.
- `page >= 1`, `pageSize` default 20 y máximo 50 en búsquedas de usuario; máximo 100 en admin.
- Respuesta paginada: `items`, `page`, `pageSize`, `totalItems`, `totalPages`, `hasNextPage`.
- `Idempotency-Key` en checkout, importación manual y comandos externos repetibles.
- `ETag`/`If-Match` derivado de `ROWVERSION` en edición de perfil, fondo y suscripción administrativa.
- `201 Created` + `Location` al crear; `202 Accepted` + URL de estado para trabajos; `204 No Content` para comandos idempotentes sin cuerpo.
- `401` sin identidad, `404` para recurso ajeno/inexistente, `403` para rol o entitlement insuficiente, `409` para conflicto, `412` para ETag obsoleto y `429` con `Retry-After`.
- Para plan insuficiente usar `403` y código `subscription_required`; no usar `402` como mecanismo principal.

`ProblemDetails` global:

```json
{
  "type": "https://fundingplatform.example/errors/validation",
  "title": "Validation error",
  "status": 400,
  "code": "validation_failed",
  "traceId": "00-...",
  "errors": {
    "email": ["El email no es válido."]
  }
}
```

FluentValidation genera errores de dominio/entrada previsibles; las excepciones inesperadas nunca exponen stack trace, SQL o payloads.

### 8.2 Identidad y cuenta

| Método | Endpoint | Semántica |
|---|---|---|
| `POST` | `/api/v1/auth/register` | `202`; respuesta genérica para reducir enumeración |
| `POST` | `/api/v1/auth/verify-email` | consume token de un solo uso |
| `POST` | `/api/v1/auth/resend-verification` | `202` genérico |
| `POST` | `/api/v1/auth/login` | access JWT + refresh cookie |
| `POST` | `/api/v1/auth/mfa/challenge` | consume challenge opaco + TOTP/recovery antes de emitir sesión administrativa |
| `POST` | `/api/v1/auth/refresh` | rota refresh token |
| `POST` | `/api/v1/auth/logout` | revoca sesión actual |
| `POST` | `/api/v1/auth/logout-all` | revoca todas las familias del usuario |
| `POST` | `/api/v1/auth/forgot-password` | siempre `202` |
| `POST` | `/api/v1/auth/reset-password` | consume token, cambia stamp y revoca sesiones |
| `POST` | `/api/v1/auth/change-password` | exige contraseña actual |
| `GET` | `/api/v1/me` | identidad, roles globales y membresías accesibles |
| `PATCH` | `/api/v1/me` | nombre, locale y preferencias no sensibles |
| `POST` | `/api/v1/me/change-email` | inicia cambio con token de un solo uso |
| `POST` | `/api/v1/me/change-email/confirm` | confirma y revoca sesiones |
| `POST` | `/api/v1/me/mfa/setup` | devuelve secreto/QR tras reautenticación o sesión limitada de activación admin |
| `POST` | `/api/v1/me/mfa/confirm` | activa TOTP y entrega recovery codes una vez |
| `POST` | `/api/v1/me/mfa/recovery-codes` | regenera con step-up |
| `DELETE` | `/api/v1/me/mfa` | desactiva solo si la policy del rol lo permite |

### 8.3 Catálogos y organizaciones

| Método | Endpoint | Policy |
|---|---|---|
| `GET` | `/api/v1/catalogs?types=countries,regions,...` | autenticado; cacheable |
| `GET` | `/api/v1/organizations` | solo membresías del usuario |
| `POST` | `/api/v1/organizations` | crea organización + admin; máximo una propia por usuario en MVP |
| `GET` | `/api/v1/organizations/{organizationId}` | miembro activo |
| `GET` | `/api/v1/organizations/{organizationId}/profile` | miembro activo |
| `PUT` | `/api/v1/organizations/{organizationId}/profile` | `OrganizationAdmin`; reemplazo atómico de N:N |
| `GET` | `/api/v1/organizations/{organizationId}/profile-completeness` | miembro activo |

Un solo `PUT profile` evita una docena de endpoints chatty durante onboarding. Es reemplazo de snapshot completo: el cliente carga primero el perfil entero, conserva colecciones no editadas, envía `If-Match` y una colección omitida es error, no “vaciar”. El request no contiene un segundo `organizationId`; el ID de ruta es el único candidato y debe ser autorizado en servidor. `organizations.max_owned=1` y rate limit impiden crear workspaces Free para reiniciar cuotas; una excepción de soporte es explícita y auditada.

### 8.4 Fondos, búsqueda y actividad

| Método | Endpoint | Notas |
|---|---|---|
| `GET` | `/api/v1/funding-opportunities` | preview público con proyección/límite fijo, sin datos premium |
| `GET` | `/api/v1/funding-opportunities/{idOrSlug}` | preview público limitado y fuente original |
| `GET` | `/api/v1/marketplace/catalogs` | catálogos públicos allowlisted para filtros de proyectos |
| `GET` | `/api/v1/marketplace/projects` | marketplace público 8B con filtros, orden y paginación server-side |
| `GET` | `/api/v1/marketplace/projects/{slug}` | detalle seguro de un proyecto actualmente publicado |
| `GET` | `/api/v1/marketplace/organizations/{organizationId}` | perfil público seguro y sus proyectos visibles |
| `GET` | `/api/v1/projects/{slug}` | alias compatible del detalle público de proyecto |
| `GET` | `/api/v1/organizations/{organizationId}/funding-opportunities` | catálogo autenticado 8A, filtros/orden/paginación sin contexto de proyecto |
| `GET` | `/api/v1/organizations/{organizationId}/funding-opportunities/{idOrSlug}` | detalle completo 8A para un miembro activo |
| `POST` | `/api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs` | cálculo 9A sincrónico, acotado, rate limited e idempotente |
| `GET` | `/api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs` | historial 9A paginado con versiones y vigencia |
| `GET` | `/api/v1/organizations/{organizationId}/projects/{projectId}/matching-runs/{matchingRunId}` | resultado 9A y desglose explicable por fondo/regla |
| `GET` | `/api/v1/organizations/{organizationId}/favorites` | favoritos del usuario dentro del tenant |
| `PUT` | `/api/v1/organizations/{organizationId}/favorites/{fundingOpportunityId}` | guardar idempotentemente |
| `DELETE` | `/api/v1/organizations/{organizationId}/favorites/{fundingOpportunityId}` | quitar idempotentemente |
| `GET/POST` | `/api/v1/organizations/{organizationId}/applications` | lista/crea seguimiento |
| `GET/PATCH` | `/api/v1/organizations/{organizationId}/applications/{applicationId}` | ownership y ETag; descartar es un estado, no un borrado |
| `GET` | `/api/v1/organizations/{organizationId}/calendar` | rango acotado; cierres de favoritos/recomendaciones y fechas de postulaciones |
| `POST` | `/api/v1/admin/semantic-evaluation-runs` | 9B-A: Admin/SuperAdmin + MFA reciente, rate limit, `Idempotency-Key`, versiones exactas de corpus/configuración; `202` |
| `GET` | `/api/v1/admin/semantic-evaluation-runs` | 9B-A: historial agregado paginado; Admin/SuperAdmin + MFA reciente |
| `GET` | `/api/v1/admin/semantic-evaluation-runs/{runId}` | 9B-A: estado y contadores sanitizados de jobs; Admin/SuperAdmin + MFA reciente |
| `GET` | `/api/v1/admin/semantic-evaluation-runs/{runId}/report` | 9B-A: métricas agregadas por split, sin input canónico ni vectores |
| `POST` | `/api/v1/admin/semantic-explanation-runs` | 9B-B: crea run de explicación shadow desde una evaluación semántica completada; MFA, rate limit e `Idempotency-Key`; `202` |
| `GET` | `/api/v1/admin/semantic-explanation-runs/{runId}` | 9B-B: estado y resultados estructurados paginados, sanitizados y `no-store`; sin canonical input/raw |

La ruta organizacional implementada en 8A acepta `q`, `countryIds`, `regionIds`, `categoryIds`,
`tagIds`, `beneficiaryTypeIds`, `projectTypeIds`, `funderIds`, `sponsor`, `minAmount`, `maxAmount`,
`currency`, `closingFrom`, `closingTo`, `fundingTypeIds`, `organizationTypeIds`, `onlyOpen`, `sort`,
`page` y `pageSize`. Admite `relevance`, `closing-soon`, `newest`, `amount-asc` y `amount-desc`; la
relevancia exige texto y monto exige una moneda. `eligibility`, score y `sort=compatibility` no
forman parte del contrato 8A; 9A expone el score en ejecuciones separadas de `/matching-runs` y no
agrega ese orden al catálogo general.

De las rutas project-aware y de actividad mostradas en la tabla, 8A materializa el catálogo
organizacional, su detalle y los tres endpoints de favoritos. 8B materializa las cuatro rutas
`/marketplace`, el alias público de proyecto, los endpoints de postulaciones y el calendario. 9A
materializa las tres rutas `/matching-runs`: todas exigen sesión completa, membresía activa,
aislamiento tenant mediante `404`, `no-store` y rate limit. El alta exige `Idempotency-Key` de
16–128 caracteres; responde `201` para una ejecución nueva y `200` para su replay seguro. No acepta
pesos, versiones ni reglas desde el cliente.

9B-A materializa las cuatro rutas administrativas de evaluación semántica. No son tenant/client,
no permiten cargar labels ni cambiar configuraciones desde HTTP y no tienen UI. Autorización y
rate limit se evalúan antes de consultar SQL; las respuestas de detalle y reporte incluyen el aviso
de que la evaluación es interna, shadow, no recomienda fondos y no confirma elegibilidad.

9B-B agrega dos rutas administrativas para explicación y tampoco expone UI o contratos cliente.
Las políticas DPA/ZDR/precios y configuraciones sólo se publican mediante Admin CLI interactivo;
ningún request HTTP suministra provider, model, prompt, esquema, precios o API key. Los resultados no
se escriben sobre matching ni ranking y mantienen el mismo aviso de uso interno/orientativo.

La búsqueda textual 8A combina Full-Text rank con un complemento literal y cae completamente a este
último si el índice no está listo. `sort` se mapea por allowlist a expresiones SQL; nunca se concatena
una columna arbitraria enviada por el cliente. Todas las rutas de organización exigen sesión completa,
membresía activa, `no-store` y rate limit. Una organización ajena responde `404` sin confirmar su
existencia; el detalle y el alta de un favorito también usan `404` si la oportunidad no está
disponible. El borrado de favoritos es idempotente y devuelve `204` con membresía válida aunque la
relación ya no exista. Ordenar globalmente por monto exige una única moneda porque comparar CLP, USD
y EUR sin conversión sería falso.

El marketplace 8B acepta `q`, `countryIds`, `categoryIds`, `projectTypeIds`, `projectStatus`,
`currency`, `sort`, `page` y `pageSize`. Los órdenes son `newest`, `title` y `funding-gap-desc`; la
brecha exige una moneda única. Solo aparecen proyectos activos y `Published` de organizaciones
activas con perfil apto; las proyecciones no incluyen miembros, emails, teléfonos, identificadores
tributarios ni drafts. Las respuestas públicas tienen cache corta y rate limit. Los perfiles no se
presentan como verificación legal realizada por FundingPlatform.

Las postulaciones exigen sesión completa y membresía activa. Todos los miembros pueden leer; el
owner de la postulación o un Admin organizacional puede editar. `POST` enlaza obligatoriamente
organización, proyecto propio activo y fondo `PublicReady`, crea estado `Interested` y exige una
`Idempotency-Key` durable. `PATCH` reemplaza el snapshot mutable y exige el ETag vigente mediante
`If-Match`; ausencia/formato inválido usa `428`, precondición obsoleta `412` y duplicados/conflictos
de idempotencia `409`. El aislamiento cross-tenant devuelve `404` indistinguible. Las rutas privadas
usan `no-store` y rate limit.

El calendario 8B acepta un rango máximo de 366 días y deriva cierres del fondo, envío planificado,
resultado, inicio/término del proyecto y cierres de favoritos sin duplicar los ya cubiertos por una
postulación activa. No persiste una tabla calendario y excluye postulaciones `Discarded`.

### 8.5 Búsquedas guardadas y alertas

- `GET/POST /api/v1/organizations/{organizationId}/saved-searches`
- `GET/PATCH/DELETE /api/v1/organizations/{organizationId}/saved-searches/{id}`
- `PUT /api/v1/organizations/{organizationId}/saved-searches/{id}/alert`
- `DELETE /api/v1/organizations/{organizationId}/saved-searches/{id}/alert`
- `GET /api/v1/organizations/{organizationId}/notification-logs`
- `POST /api/v1/alerts/unsubscribe` con token opaco de un solo propósito desde email

El servidor vuelve a ejecutar la búsqueda guardada; no acepta que React envíe una lista de fondos para alertar.
Las rutas organizacionales exigen sesión completa, membresía activa y aislamiento user+tenant;
usan `no-store`, rate limit, `Idempotency-Key` al crear y ETag/`If-Match` al modificar o eliminar.
La baja pública es `POST`, no enumera suscripciones y valida un bearer HMAC de un solo propósito.
La página exige confirmación explícita antes del `POST`; abrir o previsualizar la URL no modifica
estado. El bearer se ubica en el fragmento `#token`, fuera del request HTTP del hosting.
`Alerts:Enabled=false` mantiene scheduler, activación y proveedor apagados por defecto.

### 8.6 Suscripciones

- `GET /api/v1/subscription-plans`
- `GET /api/v1/organizations/{organizationId}/subscription`
- `POST /api/v1/organizations/{organizationId}/subscription-checkouts`
- `GET /api/v1/organizations/{organizationId}/subscription-checkouts/{checkoutId}`
- `POST /api/v1/organizations/{organizationId}/subscription/cancel`
- `POST /api/v1/organizations/{organizationId}/subscription/resume`
- `GET /api/v1/organizations/{organizationId}/subscription/usage`
- `POST /api/v1/webhooks/payments/mercado-pago`

El webhook es anónimo a nivel JWT, pero autenticado criptográficamente según el proveedor, limitado por tamaño y procesado con el cuerpo raw necesario para verificar firma.

### 8.7 Administración

- `GET /api/v1/admin/dashboard` con métricas operativas agregadas, sin PII ni consultas analíticas sin límite.
- `GET/POST /api/v1/admin/funders` y `GET/PUT /api/v1/admin/funders/{id}`.
- `POST /api/v1/admin/funders/{id}/submit-review`, `/reviews`, `/start-correction` y `/deactivate`.
- `GET/POST /api/v1/admin/funding-opportunities` y `GET/PUT /api/v1/admin/funding-opportunities/{id}`.
- `POST /api/v1/admin/funding-opportunities/{id}/submit-review`, `/reviews`, `/start-correction` y `/deactivate`.
- `GET/POST /api/v1/admin/sources`
- `GET/PATCH /api/v1/admin/sources/{id}`
- `POST /api/v1/admin/source-document-upload-intents` crea intent + SAS corta; todavía no crea `SourceDocument`.
- `POST /api/v1/admin/source-document-upload-intents/{intentId}/complete` consume el token; devuelve `202` mientras procesa y `200` al alcanzar un estado terminal.
- `GET /api/v1/admin/source-document-upload-intents/{intentId}` devuelve estado y, al completar, `sourceDocumentId`.
- `GET /api/v1/admin/source-documents/{id}` devuelve estado de scan/extracción del documento ya verificado.
- `POST /api/v1/admin/source-documents/{id}/scan/retry` exige `If-Match` e `Idempotency-Key`; un ETag obsoleto devuelve `412`.
- `POST /api/v1/admin/source-documents/{id}/extractions` inicia extracción solo para un blob
  `Clean` y confiable; exige `If-Match` e `Idempotency-Key`.
- `GET /api/v1/admin/source-documents/{id}/extractions/latest` y `/evidence` exponen únicamente
  estado, métricas y evidencia sanitizada, nunca texto bruto, hash, ETag o ruta privada.
- `POST /api/v1/admin/funding-sources/{sourceId}/import-runs` exige `Idempotency-Key` y
  responde `202` con `statusUrl`; keyword 2–100 y `maximumResults` 1–25.
- `GET /api/v1/admin/import-runs` pagina y filtra por fuente/estado.
- `GET /api/v1/admin/import-runs/{id}` incluye contadores, items y errores sanitizados, nunca raw.
- `GET /api/v1/admin/funding-duplicate-candidates` y `/{candidateId}`.
- `POST /api/v1/admin/funding-duplicate-candidates/{candidateId}/decisions` registra
  `keep-separate`, `mark-duplicate` o `ignored` con ETag, motivo e idempotencia.
- `GET /api/v1/admin/import-errors`
- `GET /api/v1/admin/users` y `/users/{id}`, inicialmente solo lectura.
- `GET /api/v1/admin/organizations` y `/organizations/{id}`, inicialmente solo lectura.
- `GET /api/v1/admin/subscriptions` y `/subscriptions/{id}`, inicialmente solo lectura.
- `GET /api/v1/admin/audit-events` paginado y redactado por policy.

Todas las acciones de publicación, roles, fuentes, importación manual y soporte quedan auditadas.
Los tres endpoints de importación implementados en FASE 7A exigen Admin/SuperAdmin con MFA reciente
y emiten `Cache-Control: no-store`. FASE 7B agregó el detalle documental/extracción y la comparación
de candidatos en `/admin/imports/:id`; una decisión de duplicado nunca fusiona ni publica contenido
automáticamente. La revisión editorial final permanece en `/admin/funding`.
Las mutaciones editoriales exigen `Idempotency-Key`; un ETag obsoleto responde `412`, mientras
conflictos de estado o reutilización de clave responden `409`. Una corrección de contenido
publicado comienza con una transición auditada `Published → Draft`, motivo explícito y nueva
revisión humana. El catálogo muestra un interstitial con el hostname antes de abrir la URL de
postulación y el editor advierte si los hosts de fuente y postulación difieren.

El upload intent genera server-side un object name impredecible, token de finalización y una SAS blob-level de minutos, HTTPS y permiso `Create` únicamente. La SAS no puede imponer tamaño, MIME ni magic bytes: esos límites se comprueban server-side al finalizar. El navegador carga una sola vez al container `incoming`; `/complete` no acepta `ScanStatus`, hash ni MIME como verdad del cliente, hace `HEAD`, transmite como máximo el límite configurado, valida tamaño, tipo y magic bytes y calcula SHA-256. Solo entonces crea `SourceDocument` y reanuda de forma idempotente la copia condicional a cuarentena. FASE 7B implementó el receptor Event Grid autenticado con Entra: valida la política exacta, relee ETag/SHA y el recibo oficial de Defender antes de promover únicamente un resultado `Clean` al container confiable. Cualquier estado inválido, desconocido, tardío o no verificable bloquea el documento; un resultado malicioso posterior revoca su confianza. Producción permanece deshabilitada hasta que el operador configure Defender/Event Grid y valide un E2E real; `DevelopmentFake` sigue siendo solo local.

### 8.8 Salud

- `/health`: liveness; no consulta terceros.
- `/health/ready`: SQL y configuración esencial. OpenAI, correo o pago caídos se reportan como dependencias degradadas en telemetría, pero no deben sacar toda la API del balanceador.

---

## 9. Flujos críticos

### 9.1 Registro, login y renovación

1. Registro normaliza email, valida contraseña, crea usuario pendiente y token opaco hashado.
2. La respuesta siempre evita confirmar si una dirección ya existe; el email entrega la acción correcta.
3. La verificación consume el token una sola vez y activa la cuenta.
4. Login usa Identity/UserManager con lockout. Si el rol requiere MFA, crea un challenge opaco de un solo uso ligado a `UserId + SecurityVersion + propósito`, expira en pocos minutos, limita intentos/rate y solo después de TOTP/recovery produce JWT de 15 minutos y refresh aleatorio de 30 días. La vigencia administrativa de MFA está acotada a 60 minutos y las rotaciones no rejuvenecen su `auth_time`.
5. El access token permanece en memoria del frontend, nunca en `localStorage`.
6. Refresh token viaja en cookie `HttpOnly`, `Secure`, restringida a `/api/v1/auth` y con `SameSite` coherente con los dominios.
7. Renovaciones concurrentes se serializan con Web Locks/BroadcastChannel. El SP rota atómicamente y enlaza el reemplazo.
8. Una carrera legítima muy próxima, mismo contexto y token revocado por rotación devuelve `409 refresh_conflict` sin entregar token; la pestaña espera la cookie actualizada y reintenta. Un replay fuera de esa ventana revoca toda la familia y registra evento de seguridad.
9. Password/email, bloqueo de cuenta, rol global, MFA/recovery y recuperación administrativa pasan por `usp_User_InvalidateSessions`; según la causa cambia stamp, siempre incrementa `SecurityVersion` y revoca todas las familias refresh.
10. El JWT contiene `sub`, `jti`, `iss`, `aud`, expiración, `sv`, `amr` y roles globales; no contiene perfil ni lista completa de tenants. Policies administrativas comparan `sv` con servidor para revocación inmediata; usuarios normales conservan como máximo la ventana de 15 minutos del access token.

La topología aprobada es `app.<dominio>` + `api.<dominio>` bajo el mismo sitio, con cookie host-only Lax y validación de `Origin`, conforme ADR-010.

### 9.2 Autorización por organización

1. JWT autentica al usuario, no al tenant.
2. Una policy toma `organizationId` de la ruta.
3. `IOrganizationAccessService` consulta la membresía activa en SQL en MVP; no se cachea autorización hasta diseñar invalidación/versionado seguro.
4. Crea un `TenantContext` interno con organización, usuario y rol verificados.
5. Service y repositorio reciben ese contexto; toda consulta tenant incluye `OrganizationId`.
6. Un ID de otro tenant responde `404`, evitando confirmar su existencia.
7. El bypass global de Admin usa otra policy y siempre genera auditoría.
8. Workers llevan `OrganizationId` explícito; no existe un tenant implícito global.

No se implementa Row-Level Security de SQL en MVP: con pooling exige administrar `SESSION_CONTEXT` impecablemente y duplica complejidad. Se reconsidera para clientes enterprise; las pruebas de aislamiento A/B son obligatorias desde FASE 4.

Matriz de ownership MVP:

- favoritos, búsquedas guardadas, alertas y sus logs son privados del usuario dentro de la organización;
- postulaciones y sus notas son recursos compartidos de la organización y visibles a miembros activos;
- `OrganizationAdmin` edita perfil/miembros futuros/billing, pero no obtiene por ese rol acceso a logs privados de alertas;
- `Admin` publica contenido y observa soporte no sensible; `SuperAdmin` gestiona roles/plataforma. Cualquier lectura cross-tenant de soporte usa una policy explícita y `AuditEvent`.

### 9.3 Ingesta y deduplicación

Contrato conceptual:

```text
IFundingSourceProvider
  FetchAsync(context, cancellationToken)
  ParseAsync(rawItem, cancellationToken)
  NormalizeAsync(parsedItem, cancellationToken)
```

FASE 7A implementó `GrantsGovFundingSourceProvider` contra la API pública oficial, HTTPS, origen
fijo, sin redirects y con límites de tiempo/tamaño/retry. FASE 7B agregó un proveedor
`official-rss` para un único feed HTTPS fijo. Antes de cada solicitud autoriza en SQL la versión
inmutable y exige coincidencia exacta de endpoint/hosts, licencia vigente, `robots.txt` en modo
`enforce`, rate limit global, tamaño y retención. Rechaza redirects, DTD y resolución a destinos
privados, loopback, link-local o metadata. Está deshabilitado hasta que un SuperAdmin ejecute
interactivamente `configure-funding-source-policy` y el preflight coincida con `OFFICIAL_RSS_*`.
No existe proveedor web genérico ni bypass de robots/CAPTCHA.

El procesamiento 7A usa dos pasadas. Primero persiste de forma atómica cada raw, su hash, snapshot
normalizado versionado e item, hasta el límite durable del run; recién después ejecuta staging
editorial. Antes de consultar al proveedor, un retry rehidrata items pendientes bajo el lease. Así,
un corte entre raw y staging no depende de que Grants.gov repita la misma respuesta. El fingerprint
editorial excluye el instante de recuperación para que observar el mismo contenido más tarde no cree
una versión falsa.

Controles web:

- allowlist de dominios y protocolos HTTP/HTTPS;
- revisión y fecha de términos/robots;
- User-Agent identificable y contacto;
- rate limit por host, jitter, caché, timeout y reintentos limitados;
- conditional requests (`ETag`, `If-Modified-Since`) cuando existan;
- límites de redirección, tamaño y descompresión;
- bloqueo SSRF de localhost, metadata endpoints, redes privadas/link-local y cambios de destino tras redirect;
- prohibición explícita de CAPTCHA/anti-bot bypass.

Orden de deduplicación:

1. `(SourceId, ExternalId)` o source item key exacto: actualizar vínculo existente.
2. hash de URL canónica + fuente.
3. hash de contenido: `NoChange`.
4. fingerprint normalizado de título + sponsor + fecha límite + rango de monto.
5. similitud textual/semántica: solo genera candidato de revisión; no fusiona automáticamente.

FASE 7B materializa la revisión candidata-céntrica en API y `/admin/imports/:id`. Un Admin o
SuperAdmin con MFA reciente compara ambas oportunidades y decide conservar separadas, marcar la
duplicada contra una canónica o ignorar la sugerencia. ETag, motivo e idempotencia evitan decisiones
silenciosas sobre datos cambiados; todas mantienen el candidato fuera del catálogo hasta la revisión
editorial normal.

Una reimportación no sobrescribe campos con `IsManualLock=1`. Cada transición terminal de item
incrementa su outcome una sola vez dentro del SP y el cierre valida la suma contra
`RetrievedCount`; no se aceptan contadores agregados enviados por el worker. El resultado de staging
es siempre `Draft`/`StagedForReview`: ninguna ruta de adquisición puede publicar.

### 9.4 Extracción mediante IA

FASE 7B materializa únicamente la extracción determinística y acotada de texto PDF más evidencia
segura. No llama a OpenAI, no interpreta campos ni modifica contenido editorial. 9B-B implementa el
adapter y el gobierno para explicaciones shadow, pero el esquema y workflow de extracción
estructurada siguientes siguen diferidos; no forman parte del worker semántico 9B-A ni de `023`.

1. Se extrae texto de una fuente no confiable en un proceso aislado y con límites.
2. El prompt establece que el documento es datos, no instrucciones; el modelo no tiene herramientas ni credenciales.
3. El adapter OpenAI usa Responses API + Structured Outputs estricto con un JSON Schema versionado. Cada dato incluye `value`, `status`, `evidence`, `sourceLocator` y `confidence`. Se diseña dentro del subconjunto soportado y maneja refusal, límite de tokens o respuesta incompleta; schema adherence no reemplaza validación de dominio. [Documentación oficial de Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs).
4. Un campo ausente usa `null` y estado `unknown`; no se infiere país, fecha o monto por conveniencia.
5. FluentValidation y reglas de consistencia rechazan fechas imposibles, rangos invertidos, monedas inválidas y taxonomías desconocidas.
6. Los campos críticos sin evidencia crean un issue y bloquean publicación automática.
7. Un administrador compara valor y evidencia, corrige y aprueba.
8. El valor canónico y su provenance se actualizan en la misma transacción.
9. Si cambió contenido canónico, se incrementa `ContentVersion`, se crea el snapshot y los resultados
   9A dejan de ser vigentes por fingerprint/versionado. Mientras siga en revisión no entra al conjunto
   `PublicReady`. 9B-A puede detectar y encolar por polling/backfill el embedding de esa versión para
   evals; no emite un recálculo masivo ni altera 9A. Publicar por sí solo no vuelve a incrementar la
   versión.
10. Costos, tokens, latencia, modelo, prompt y hashes quedan registrados sin guardar secretos.

La calidad de datos se calcula con reglas determinísticas: completitud de campos críticos, evidencia, validez, conflictos, reputación de fuente y antigüedad de verificación. No se pide al LLM que se autocalifique.

`022`/`023` fijan modelos exactos y nunca aceptan un alias `latest`: embeddings
`text-embedding-3-small`/`text-embedding-3-large` y explicación `gpt-5.6-sol`. Aún deben evaluarse
con el proyecto real; un cambio de modelo exige nueva versión de configuración/evals antes de
cualquier promoción. [Catálogo oficial de modelos OpenAI](https://developers.openai.com/api/docs/models).

9B-A usa allowlists distintas para proyecto y oportunidad. El proyecto admite resumen/descripción,
estado, fechas, presupuesto/financiamiento, moneda y taxonomías; excluye título/nombre, slugs, IDs de
organización/usuario, RUT/Tax ID, emails, URLs, nombres de miembros, notas y billing. La oportunidad
admite únicamente sus campos editoriales públicos y taxonomías. El input canónico es runtime-only,
lleva hash y límite de 8192 bytes UTF-8. Antes de conectar el proveedor se deben aprobar en operación
el DPA/ZDR, residencia y ciclo de vida modelados por `022`; el fake local no envía datos por red.

### 9.5 Matching

El flujo visible vigente es exclusivamente 9A:

1. seleccionar oportunidades `PublicReady` abiertas y acotar cada corrida a su TOP 200;
2. ejecutar hard gates y reglas atómicas versionadas;
3. aplicar la política conservadora: desconocido no suma y reduce cobertura, sin renormalizar;
4. persistir score, clasificación, razones, evidencia, versiones y fingerprint determinísticos.

9B-A ejecuta un flujo separado sobre un corpus humano congelado. Genera los embeddings exactos de
`ProjectVersion` y `FundingContentVersion`, calcula distancia coseno y un score calibrado sólo para
ordenar el snapshot de evaluación, y compara por cada corrida 9A el ranking semántico con el baseline.
`Compatible` siempre precede a `InsufficientData`; un `Incompatible` puede medirse para detectar una
promoción indebida, pero nunca modifica sus hard gates. No se actualizan `RuleScore`,
`CompatibilityScore`, `Classification`, `IsCurrent` ni el orden visible.

Sólo si un proveedor real supera los gates de 9B-B podría diseñarse otro perfil versionado que
combine reglas y semántica. `023` ya puede producir una explicación estructurada administrativa,
separada y en sombra, pero no la usa como ponderación ni la muestra a clientes. 9B-A/9B-B no
implementan `SemanticPoints`, writeback ni promoción.

Ejemplo de salida:

```text
Compatibilidad: 91%
Cobertura de evidencia: 95% · Confianza alta

Coincide
- ONG chilena admitida explícitamente.
- Educación y adolescencia son áreas prioritarias.
- El rango solicitado está dentro del monto financiable.

Advertencias
- Exige dos años de antigüedad.
- Requiere 10% de cofinanciamiento.
```

Un match deja de ser vigente si no coinciden `Project.ProjectVersion`,
`Organization.ProfileVersion`, `FundingOpportunity.ContentVersion` y `MatchingProfileId`. Mientras
se recalcula, la API rotula el resultado previo como desactualizado o lo omite según antigüedad;
nunca lo presenta silenciosamente como actual.

9B-A no encadena `ProjectChanged` con recálculo de matching ni genera embeddings institucionales. El
timer consulta SQL, reclama un job justo antes de procesarlo, revalida sujeto/versión/hash y sólo
persiste el vector si todo sigue coincidiendo. Un input stale termina separado; nunca se reutiliza un
vector obsoleto. Una falla terminal permite cerrar un reporte parcial con menor cobertura/éxito y
`MeetsPromotionGate=false`, sin degradar silenciosamente el score 9A.

### 9.6 Suscripción y webhook

1. `OrganizationAdmin` solicita checkout con `planPriceId`, intervalo e `Idempotency-Key`.
2. El server valida plan, moneda, estado actual y entitlement; en una transacción persiste la sesión `Creating` y su `ExternalReference` estable antes de tocar el proveedor.
3. El gateway recibe esa referencia y una idempotency key cuando su contrato la admita; crea o recupera la suscripción y devuelve URL alojada. FundingPlatform no recibe tarjeta.
4. Solo después se guarda `ProviderCheckoutId` y se pasa a `Pending`. Si la respuesta queda incierta, un retry/reconciliador consulta por referencia antes de intentar crear; nunca asume que el recurso remoto no existe.
5. El redirect del navegador solo muestra “pago en verificación”.
6. El webhook valida el mecanismo exacto documentado por Mercado Pago con fixtures oficiales, límites temporal/tamaño y normaliza un delivery ID idempotente.
7. Un SP persiste `PaymentWebhookEvent + OutboxMessage`; duplicado auténtico responde `2xx`, autenticidad inválida `4xx` y fallo de persistencia `5xx`. El procesamiento pesado ocurre después del ACK y consulta el recurso autoritativo.
8. Una transacción actualiza suscripción, pago y auditoría; eventos antiguos no revierten estados más nuevos.
9. `ISubscriptionService` resuelve features/limits; Controllers no comparan `Professional` como string.
10. Un job cada 5–15 minutos reconcilia checkouts/suscripciones `Pending`; otro diario revisa `Active/PastDue`.

Cancelación al fin de período conserva acceso hasta `CurrentPeriodEndUtc`. `resume` solo retira una cancelación todavía programada; una suscripción ya cancelada exige nuevo checkout salvo capacidad confirmada del adapter. `PastDue` admite gracia configurable y luego cae a Free sin borrar datos. Los webhooks duplicados, falsos y fuera de orden, dos checkouts concurrentes y el crash “proveedor aceptó / SQL aún no confirmó” forman parte de las pruebas de FASE 11.

### 9.7 Alertas

1. Scheduler reclama alertas cuyo `NextRunAtUtc` venció.
2. Antes de materializar, revalida usuario activo, membresía, organización, búsqueda no eliminada y
   suscripción activa; una FK por sí sola no autoriza.
3. Ejecuta server-side los predicados literales y filtros de 8A sobre `PublicReady`, sin matching ni
   score, y selecciona sólo publicaciones nuevas de `LastRunAtUtc..ScheduledForUtc`.
4. Materializa como máximo 50 ítems y el ledger `NotificationLog` en la misma transacción que avanza
   `LastRunAtUtc/NextRunAtUtc`; la clave SHA-256 alerta+ventana vuelve el paso idempotente.
5. Delivery vuelve a comprobar destinatario y disponibilidad pública, reclama con lease y construye
   email/token únicamente en memoria.
6. Registra receipt/estado acotados sin guardar email ni body. Un fallo confirmadamente pre-envío
   puede reintentarse; un timeout o ACK incierto queda terminal `Unknown` y no se reenvía a ciegas.
7. Un run sin novedades queda `Skipped`; una caída extensa produce un solo digest de recuperación.

---

## 10. Seguridad y privacidad

### 10.1 Controles obligatorios

- TLS, HSTS y redirección HTTPS.
- CORS con orígenes, métodos, headers y credenciales explícitos; nunca `AllowAnyOrigin` con cookies.
- CSP estricta en frontend; `frame-ancestors`, `X-Content-Type-Options`, `Referrer-Policy` y `Permissions-Policy`.
- JWT de 15 minutos, issuer/audience/algoritmo estrictos y clock skew bajo.
- clave JWT de al menos 256 bits en desarrollo; clave rotatable con `kid`/Key Vault en producción.
- key ring de ASP.NET Core Data Protection persistido en Blob y protegido con una clave de Key Vault para MFA/tokens cifrados en múltiples instancias.
- PasswordHasher de Identity, lockout progresivo y rehash al iniciar sesión cuando cambien parámetros.
- rate limiting por IP y cuenta en login, registro, reset, refresh, IA, importación y recálculo.
- respuestas genéricas contra enumeración de cuentas.
- MFA obligatorio para `Admin/SuperAdmin` antes del piloto público; MFA de usuarios puede quedar V2.
- autorización por policy y ownership en cada recurso tenant.
- DTO específicos y allowlists para prevenir mass assignment.
- parámetros Dapper siempre enlazados; filtros/orden dinámicos por allowlist.
- Swagger deshabilitado o protegido en producción.
- límites de request, upload, páginas PDF, filas Excel/CSV, tiempo, redirecciones y contenido descomprimido.
- validación de extensión, MIME y magic bytes; Blob de cuarentena y análisis antimalware antes de procesar.
- HTML sanitizado; nunca `dangerouslySetInnerHTML` con raw importado.
- webhook verificado, idempotente y reconciliado.
- Managed Identity para SQL/Blob/Queue/Key Vault cuando el servicio lo soporte.
- secretos de terceros solo en Key Vault; `.env` exclusivamente local e ignorado.
- redacción de `Authorization`, cookies, tokens, passwords, SAS URLs, Tax ID y bodies sensibles.
- auditoría append-only para publicación, roles, fuentes, billing y acciones administrativas.

### 10.2 Amenazas específicas del producto

| Amenaza | Control principal |
|---|---|
| IDOR entre ONG | tenant policy + `OrganizationId` en repositorio + tests A/B |
| Prompt injection en convocatoria | contenido tratado como datos, Structured Outputs, sin tools/secretos |
| SSRF en URLs fuente | allowlist, resolución IP, bloqueo de rangos internos antes/después de redirects |
| ZIP/PDF bomb o malware | límites comprimido/descomprimido, timeout, cuarentena y scanner |
| SQL injection | Dapper parametrizado, SP, allowlist de sort |
| XSS persistente | sanitización de contenido canónico y render seguro |
| Refresh replay | hash, rotación/familia y revocación atómica |
| Pago falso | nunca confiar en frontend; webhook + GET autoritativo al gateway |
| Scraping indebido | revisión de términos/robots, rate limit y kill switch por fuente |
| Filtración en logs | redaction policy, log de metadata y correlation ID, no payloads |
| Abuso de IA/costos | entitlement, cuotas, cache por hash, límites y budget alerts |

Policies administrativas mínimas:

| Acción | Admin | SuperAdmin |
|---|---:|---:|
| revisar/publicar fondos, fuentes, documentos e imports | sí + MFA reciente | sí + MFA reciente |
| ver usuarios/organizaciones (proyección redactada) | sí + MFA reciente, soporte auditado | sí + MFA reciente, auditado |
| ver estados de suscripción sin instrumento de pago | sí + MFA reciente, soporte auditado | sí + MFA reciente |
| otorgar/revocar roles globales | no | sí + MFA reciente |
| cambiar configuración crítica/gateway | no | sí + MFA reciente |
| acceder a Tax ID u otro PII excepcional | no por defecto | policy break-glass + motivo/auditoría |

El código de archivos de producción integra **Microsoft Defender for Storage on-upload malware
scanning**. El upload va a cuarentena; el handler autentica Event Grid con Entra contra tenant,
audience, aplicación/principal, topic, suscripción y cuenta exactos. Persiste un recibo mínimo y
relee ETag/SHA/estado oficial antes de que solo `Clean` promueva el blob exacto al container
confiable. `Malicious`, `Failed`, timeout, metadatos no disponibles o cualquier divergencia bloquean;
el watchdog terminaliza pendientes abandonados y un resultado malicioso tardío revoca confianza.
Producción continúa deshabilitada hasta la configuración del operador y un E2E limpio/malicioso; la
fase no activó servicios pagados. Desarrollo usa un fake explícito y jamás se presenta como scan
real. Referencias: [Defender for Storage](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-storage-configure-malware-scan) y
[entrega segura de Event Grid](https://learn.microsoft.com/en-us/azure/event-grid/secure-webhook-delivery).

`FundingPlatform.ExtractionWorkers` solo lee blobs `Clean` del container confiable. El parser PDF
aplica límites de 10 MiB, 250 páginas, caracteres, bytes UTF-8 y profundidad; solicita cancelación a
los 120 segundos y el host Functions tiene un límite exterior de 5 minutos. Esta separación reduce
superficie y blast radius, pero no equivale a una sandbox de SO ni a preempción dura del código
nativo/administrado. Si el threat model futuro exige hard memory/CPU kill, se moverá a un runtime
desechable con límites de proceso/contenedor.

El limiter ASP.NET en memoria solo es global mientras la API tenga una instancia. El piloto mantiene una instancia/scale-up; Identity lockout y cuotas sensibles persisten en SQL. Antes de scale-out se incorpora un limiter distribuido/gateway o un contador durable para endpoints críticos; no se asume que dos instancias comparten memoria.

### 10.3 Datos y retención

- Definir responsable y finalidad de cada PII antes de FASE 3.
- Atender exportación y eliminación/anonimización mediante solicitud de soporte auditada en MVP, preservando registros financieros/auditoría cuando corresponda; autoservicio queda V2.
- Retención propuesta: tokens vencidos 90 días; ImportErrors detallados 180 días; raw de fuentes según licencia y necesidad; matches históricos 12–24 meses; webhooks/pagos según obligación contable.
- FASE 7B hace ejecutable la retención de adquisición: al vencer, SQL redacta raw, items, resultados
  y evidencia, terminaliza pendientes y evita rehidratación. Para documentos, el worker reclama un
  lease y solicita borrado solo si coinciden nombre, ETag, largo y SHA; recorre snapshots/versiones y
  verifica que no quede contenido activo antes de marcar `ContentDeletionRequestedAtUtc`.
- Soft delete de Blob se mantiene siete días: la indisponibilidad lógica es inmediata al confirmar
  la solicitud, pero los bytes permanecen recuperables durante esa ventana y la purga física ocurre
  después por expiración/lifecycle. Referencias: [versionado de Blob](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-overview) y
  [soft delete de blobs](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-overview).
- Backups cifrados y restore probado antes de producción.
- No usar IDs difíciles de adivinar como reemplazo de autorización.
- Una revisión legal local debe validar privacidad, términos de fuentes, emails transaccionales/comerciales y tratamiento tributario antes del lanzamiento; este documento no sustituye asesoría jurídica.

---

## 11. UX y diseño frontend del MVP

### 11.1 Rutas

```text
Públicas
  /
  /pricing
  /login
  /register
  /verify-email
  /forgot-password
  /reset-password

Autenticadas
  /onboarding
  /dashboard
  /funding
  /funding/:slug
  /recommended
  /favorites
  /applications
  /calendar
  /alerts
  /organization/profile
  /account
  /subscription

Administración
  /admin
  /admin/funding
  /admin/funding/:id
  /admin/imports
  /admin/imports/:id
  /admin/sources
  /admin/users
  /admin/organizations
  /admin/subscriptions
  /admin/errors
```

`ProtectedRoute`, `OrganizationRoute`, `EntitlementRoute` y `AdminRoute` mejoran UX, pero no sustituyen autorización de API.

### 11.2 Experiencia principal

- Onboarding por pasos con guardado parcial, validación accesible y barra de completitud.
- Dashboard: “Encontramos N oportunidades para tu organización”, calidad del perfil, próximos cierres y estado de postulaciones.
- Card de oportunidad: porcentaje, cobertura/confianza, título, sponsor, cierre relativo y absoluto, monto, moneda y top 2 razones.
- Detalle: resumen, objetivos, elegibilidad, requisitos, documentos, razones, advertencias, provenance visible, fuente y enlace original. Antes de abrir `ApplicationUrl`, la UI muestra dominio de destino y aviso de salida; URLs nuevas o cuyo dominio no coincide con una fuente aprobada requieren revisión administrativa.
- Score nunca se comunica con color solamente; incluye texto y desglose.
- Fechas muestran zona/precisión y no inventan una hora cuando la fuente solo informó un día.
- Modo claro/oscuro respeta `prefers-color-scheme` y la selección del usuario.
- Skeletons y estados vacíos específicos; un error de IA no bloquea búsqueda o datos canónicos.
- La capa `api` normaliza `ProblemDetails`, serializa refresh y cancela requests obsoletos.
- Zod valida formularios en cliente por UX; FluentValidation vuelve a validar en servidor por seguridad.
- Los tipos TypeScript se generan desde OpenAPI cuando el contrato se estabilice; no se mantienen duplicados manualmente.

### 11.3 Límites por plan

React puede mostrar paywalls y llamados a upgrade, pero el backend aplica siempre:

- cantidad de resultados/detalles visibles;
- filtros avanzados;
- acceso a recomendaciones y explicaciones IA;
- máximo de alertas y miembros;
- exportaciones y cuotas de IA.

Una respuesta limitada nunca incluye el contenido premium oculto en JSON.

## 12. Observabilidad y soporte

### 12.1 Logging y trazas

- Serilog en JSON estructurado a consola; Application Insights/OpenTelemetry en Azure.
- W3C Trace Context/`Activity` conecta browser, API, SQL, Functions, Blob, IA, email y pagos.
- `CorrelationId` entrante válido se conserva o se genera; aparece en logs, runs y `ProblemDetails`.
- Request logging registra método, plantilla de ruta, status, duración, usuario/organización pseudonimizados y tamaño; no body por defecto.
- Logs usan códigos estables de evento, no mensajes como única dimensión.

### 12.2 Métricas

| Dominio | Métricas mínimas |
|---|---|
| API | throughput, p50/p95/p99, 4xx/5xx, 429 y tamaño por ruta normalizada |
| SQL | duración por SP, timeouts, deadlocks, pool y queries lentas |
| Auth | fallos, lockouts, refresh replay y revocaciones |
| Ingesta | lag, duración, creados, actualizados, sin cambio, duplicados, rechazados y errores por fuente |
| IA | latencia, tokens, costo estimado, cache hit, output inválido y campos críticos sin evidencia |
| Matching | duración, antigüedad, distribución de score/cobertura y organizaciones sin resultados |
| Semántica shadow | jobs por estado/error seguro, cobertura/éxito, Recall/nDCG/MRR/rank, costo incremental, p95 y hard-fail promotions |
| Search | latencia, cero resultados, filtros/orden y páginas profundas |
| Billing | webhook pendiente más antiguo, duplicados, fallos y divergencias de reconciliación |
| Alertas | jobs pendientes, entregas, rebotes y retraso sobre horario |

Alertas operativas: readiness fallida, 5xx sostenido >5%, p95 fuera de SLO, dos runs seguidos fallidos para una fuente, webhook pendiente >10 minutos, dead letters, costo IA fuera de presupuesto y refresh replay.

### 12.3 Runbooks mínimos

- fuente bloqueada o cambió formato;
- importación atascada/reintento seguro;
- webhook atrasado/reconciliación;
- proveedor IA o email caído;
- secreto rotado;
- restauración Azure SQL/Blob;
- revocación masiva de sesiones;
- despublicación urgente de una oportunidad;
- respuesta a incidente de acceso cruzado.

## 13. Despliegue Azure: recomendación costo/simpleza

### 13.1 Topología MVP

| Componente | Servicio | Razón |
|---|---|---|
| React/Vite | Azure Static Web Apps | hosting estático, TLS/CDN e integración simple |
| API | Azure Container Apps Consumption + ACR privado | contenedor .NET 10 no-root, despliegue por digest y escala 1→0 en dev |
| Worker general | Azure Functions v4 isolated, Flex Consumption | imports, outbox, adquisición, Defender y retención |
| Extractor PDF | Azure Functions v4 isolated, Flex Consumption separado | cola/watchdog con identidad y dependencias mínimas |
| Datos | Azure SQL Database | PaaS SQL Server, Dapper/SP y `VECTOR` nativo |
| Binarios/raw | Azure Blob Storage | PDFs, archivos y snapshots grandes fuera de SQL |
| Scan uploads | Defender for Storage + Event Grid | cuarentena y resultado antimalware antes de parsing |
| Transporte | Azure Queue Storage | triggers at-least-once económicos; payloads solo con IDs |
| Secretos | Azure Key Vault | rotación y acceso por Managed Identity |
| Telemetría | Application Insights + Log Analytics | trazas, métricas, consultas y alertas |
| IA 9B-B | OpenAI detrás de adapters Application/Infrastructure | apagado por defecto; embeddings y Responses/Structured Outputs ligados a política SQL, ZDR, presupuesto y evals |
| Pago | Mercado Pago | suscripciones compatibles con Chile, aislado por gateway |

.NET 10 es LTS, y Azure Functions lo soporta de forma GA en isolated worker; Flex Consumption es apropiado para trabajos intermitentes. Referencias oficiales: [.NET 10](https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview), [versiones de Azure Functions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-versions) y [background jobs en Azure](https://learn.microsoft.com/en-us/azure/architecture/best-practices/background-jobs).

### 13.2 Evolución por ambiente

- **Local en este workspace ARM64:** Azure SQL dev o SQL Server 2025 remoto sobre host x86-64; Azurite para Blob/Queue; proveedores fake/sandbox; `.env`. No se toma Docker/Rosetta como baseline: Microsoft soporta los containers SQL Server Linux solo en hosts Intel/AMD x86-64 y no soporta emulación/traducción. CI de integración usa runner x86-64. [Referencia oficial](https://learn.microsoft.com/en-us/sql/linux/containers/deploy?view=sql-server-ver17).
- **Staging:** mismos tipos de recursos que producción con tamaño mínimo; base y storage separados; datos sintéticos. Azure SQL serverless es aceptable si no hay dispatcher frecuente.
- **Producción piloto:** Container Apps con mínimo definido tras medir cold start, **Azure SQL provisionado pequeño**, Functions Flex y budgets. El polling acotado del outbox impediría normalmente el auto-pause, por lo que serverless no es la recomendación productiva de costo real.
- Recursos separados por ambiente y despliegue por infraestructura como código en FASE 12.

No se agregan en MVP APIM, Front Door, Application Gateway, Private Link, Redis, Service Bus ni AKS. Container Apps se adopta sólo para la API dev; los demás servicios se revisan al aparecer una necesidad medida de WAF global, networking privado, cache distribuida o mensajería avanzada.

### 13.3 Identidad de servicios y secretos

- API/Functions usan Managed Identity para Key Vault, Blob y, cuando se configure, Azure SQL con Entra.
- SQL otorga `EXECUTE`/lectura mínima por rol; aplicaciones nunca son `db_owner`.
- Secretos de proveedor viven en Key Vault y se exponen por referencia/configuración, no en `appsettings.json` desplegado.
- Rotación de JWT admite `kid` y convivencia temporal de clave actual/anterior.
- Data Protection comparte key ring en Blob y protección Key Vault entre API/instancias autorizadas.
- Blob no expone contenedores públicos; uploads/downloads usan API o SAS de vida corta y alcance mínimo.
- Functions usa cuatro UAMI distintas entre sí. `H_general` y `S` solo se adjuntan a
  `FundingPlatform.Workers`; `H_extractor` y `C` solo a `FundingPlatform.ExtractionWorkers`.
- `AzureWebJobsStorage__clientId` vale `H_general` en el worker general y `H_extractor` en el
  extractor. `H_general != H_extractor`; cada una recibe únicamente los roles necesarios para el
  host de su app. Para `document-extractions`, `S` se fija con
  `DocumentExtractionQueueStorage__senderClientId` y solo envía; `C` se fija con
  `DocumentExtractionQueueStorage__clientId` y recibe `Storage Queue Data Reader` y
  `Storage Queue Data Message Processor`.
- `C` solo tiene `Storage Blob Data Reader` sobre el container confiable. `H_general` recibe
  `Storage Blob Data Contributor` solo en cuarentena/confiable para promoción, revocación y
  retención; ese alcance no se comparte con `H_extractor` ni `C`.
- Cuando `021` se despliegue, los principals SQL ya distintos del worker general y la API recibirán,
  respecto de la superficie semántica, sólo `FundingPlatform_SemanticWorkerRole` y
  `FundingPlatform_SemanticAdminRole`, respectivamente. No se agrega una UAMI dedicada: cada host
  conserva sus otros permisos mínimos fuera de 9B-A. El primer rol ejecuta 11 SP de procesamiento;
  el segundo, backfill y cuatro SP administrativos. Ambos tienen DML directo denegado sobre las 11
  tablas semánticas; no se comparten entre hosts ni reciben `db_owner`. La migración crea roles, no
  users/membresías.
- La conexión SqlClient del extractor usa `Authentication=Active Directory Managed Identity` y
  `User Id=<client-id-C>` de esa misma UAMI. Su principal Azure SQL se crea desde ese `clientId`
  codificado como SID binario de 16 bytes; el `principalId` queda sólo para RBAC. El usuario se
  agrega a `FundingPlatform_ExtractionWorkerRole` y se verifica con `USER_NAME()` y
  `HAS_PERMS_BY_NAME`: claim permitido; administración y lectura directa de tablas denegadas.

Los IDs `S` y `C` pueden figurar en la configuración de ambos hosts para que el arranque valide
que no colisionan con la identidad host local; esto no adjunta ni autoriza la identidad en la app
equivocada. Cuatro UAMI no significan cuatro cuentas Storage: cola y Blob pueden compartir GPv2 con
RBAC a la cola/container exactos. Solo el host storage del extractor debe permanecer fuera de esa
cuenta de datos.

Forma conceptual; el runbook activo usa el provisioner .NET idempotente para no convertir el SID a
mano:

```sql
CREATE USER [<nombre-identidad>]
    WITH SID = <0x-sid-binario-del-client-id>, TYPE = E;
ALTER ROLE [FundingPlatform_ExtractionWorkerRole]
    ADD MEMBER [<nombre-identidad>];

-- Ejecutar conectado como la UAMI del extractor; resultado esperado: usuario correcto y 1/0/0.
SELECT USER_NAME() AS DatabaseUser;
SELECT HAS_PERMS_BY_NAME(
    'dbo.FundingPlatform_usp_SourceDocumentExtraction_Claim', 'OBJECT', 'EXECUTE') AS AllowedClaim;
SELECT HAS_PERMS_BY_NAME(
    'dbo.FundingPlatform_usp_SourceDocumentExtraction_AdminStart', 'OBJECT', 'EXECUTE') AS DeniedAdmin;
SELECT HAS_PERMS_BY_NAME(
    'dbo.FundingPlatform_SourceDocuments', 'OBJECT', 'SELECT') AS DeniedTableRead;
```

Los `--assignee-object-id` de RBAC usan el `principalId`; el SID del usuario SQL, `User Id` y los
settings `*ClientId` usan el `clientId`. No se intercambian ni se infiere una identidad por existir
como recurso en el Function App.

### 13.4 Variables previstas

FASE 1 creó `.env.example`; la familia de configuración vigente incluye:

```dotenv
ASPNETCORE_ENVIRONMENT=Development
DOTNET_ENVIRONMENT=Development
AZURE_FUNCTIONS_ENVIRONMENT=Development
AZURE_SQL_CONNECTION_STRING=
AZURE_SQL_LOG_CONNECTION_STRING=
JWT_SECRET=
JWT_ISSUER=
JWT_AUDIENCE=
OPENAI_API_KEY=
OPENAI_MODEL=
OPENAI_EMBEDDING_MODEL=
AzureWebJobsStorage=
AzureWebJobsStorage__accountName=
AzureWebJobsStorage__queueServiceUri=
AzureWebJobsStorage__blobServiceUri=
AzureWebJobsStorage__credential=
AzureWebJobsStorage__clientId=
DocumentExtractionQueueStorage=
DocumentExtractionQueueStorage__accountName=
DocumentExtractionQueueStorage__queueServiceUri=
DocumentExtractionQueueStorage__credential=
DocumentExtractionQueueStorage__senderClientId=
DocumentExtractionQueueStorage__clientId=
IMPORT_WORKER_LEASE_SECONDS=1800
IMPORT_SCHEDULER_BATCH_SIZE=10
IMPORT_OUTBOX_BATCH_SIZE=25
GRANTS_GOV_TIMEOUT_SECONDS=20
CONTENT_RETENTION_BATCH_SIZE=100
CONTENT_RETENTION_SOURCE_DOCUMENT_BATCH_SIZE=25
CONTENT_RETENTION_SOURCE_DOCUMENT_LEASE_SECONDS=900
AZURE_STORAGE_BLOB_SERVICE_URI=
SOURCE_DOCUMENT_INCOMING_CONTAINER=
SOURCE_DOCUMENT_QUARANTINE_CONTAINER=
SOURCE_DOCUMENT_TRUSTED_CONTAINER=
DOCUMENT_EXTRACTION_MAX_BYTES=10485760
DOCUMENT_EXTRACTION_MAX_PAGES=250
DOCUMENT_EXTRACTION_MAX_CHARACTERS=500000
DOCUMENT_EXTRACTION_MAX_UTF8_BYTES=2097152
DOCUMENT_EXTRACTION_MAX_STACK_DEPTH=64
DOCUMENT_EXTRACTION_TIMEOUT_SECONDS=120
DOCUMENT_EXTRACTION_LEASE_SECONDS=300
DOCUMENT_EXTRACTION_WATCHDOG_BATCH_SIZE=25
DEFENDER_EVENT_GRID_ENABLED=false
DEFENDER_EVENT_GRID_TENANT_ID=
DEFENDER_EVENT_GRID_AUDIENCE=
DEFENDER_EVENT_GRID_CALLER_APPLICATION_ID=
DEFENDER_EVENT_GRID_CALLER_OBJECT_ID=
DEFENDER_EVENT_GRID_TOPIC_RESOURCE_ID=
DEFENDER_EVENT_GRID_SUBSCRIPTION_NAME=
DEFENDER_EVENT_GRID_STORAGE_RESOURCE_ID=
DEFENDER_PENDING_SCAN_TIMEOUT_MINUTES=240
OFFICIAL_RSS_ENABLED=false
OFFICIAL_RSS_FEED_URI=
OFFICIAL_RSS_ALLOWED_HOSTS=
OFFICIAL_RSS_LICENSE_NAME=
OFFICIAL_RSS_LICENSE_URI=
OFFICIAL_RSS_COMPLIANCE_APPROVED=false
OFFICIAL_RSS_ROBOTS_POLICY=Enforce
OFFICIAL_RSS_ROBOTS_POLICY_VERSION=1
EMAIL_PROVIDER_API_KEY=
EMAIL_FROM_ADDRESS=
PAYMENT_PROVIDER=MercadoPago
MERCADO_PAGO_ACCESS_TOKEN=
MERCADO_PAGO_WEBHOOK_SECRET=
FRONTEND_BASE_URL=http://localhost:5173
ALLOWED_CORS_ORIGINS=http://localhost:5173
```

Producción añade referencias/configuración no secreta como `KEY_VAULT_URI`, `APPLICATIONINSIGHTS_CONNECTION_STRING` y nombres de containers/key ring; los secretos siguen en Key Vault. La lista exacta solo se incorpora cuando una fase realmente consume la variable.

Local ejecuta Azurite, `FundingPlatform.Workers` en el puerto 7071 y
`FundingPlatform.ExtractionWorkers` en el 7072; cada proyecto conserva su propio
`local.settings.json`. El worker general usa su conexión `AzureWebJobsStorage` para host e `imports`;
el extractor usa su propia conexión, host-only. En Azure, el mismo key
`AzureWebJobsStorage__clientId` contiene `H_general` en la primera app y el distinto `H_extractor` en
la segunda. `DocumentExtractionQueueStorage` es el scope de
cola compartido entre el sender general y el consumer aislado; Blob documental es otro scope y no
comparte permisos. Ambos data planes pueden residir en una misma GPv2 con RBAC exacto. En Azure se
usan conexiones identity-based y cuatro UAMI explícitas, no cuatro cuentas ni account keys. El
extractor falla al iniciar si su host storage reutiliza la cuenta de la cola de extracción o del Blob
documental.

`OFFICIAL_RSS_ENABLED` permanece `false` hasta que el operador configure una política inmutable con
`configure-funding-source-policy` en TTY y el preflight exacto de endpoint, licencia, robots, hosts,
rate, bytes y retención pase. `DEFENDER_EVENT_GRID_ENABLED` también permanece `false` hasta
configurar recursos/RBAC/trust y validar un E2E real. Ninguna variable habilita autopublicación.

Solo `VITE_API_BASE_URL` y otras configuraciones públicas con prefijo `VITE_` entran al bundle React. Ninguna clave secreta usa ese prefijo.

## 14. Estrategia de pruebas

### 14.1 Unitarias backend

- cada regla y hard gate de matching, unknown policy, cobertura y score;
- permisos globales/organizacionales y resolución de TenantContext;
- validadores de auth, perfil, fondos, búsqueda, upload y billing;
- refresh rotation/replay con reloj y generador controlados;
- entitlements, downgrade y períodos de gracia;
- parsers/normalizadores, canonicalización URL y fingerprints;
- deduplicación exacta/difusa;
- extracción estructurada frente a JSON válido/inválido/unknown;
- contrato semántico 9B-A: fake reproducible de 1536 dimensiones, validación de vector, input
  canónico allowlisted/8192 bytes, privacidad, lease/retry, cobro incierto y presupuesto fail-closed;
- administración semántica: MFA, autorización antes de rate limit, idempotencia, errores seguros y
  reportes que no exponen inputs/vectores;
- idempotencia de alertas, importaciones y webhooks.

xUnit + FluentAssertions + NSubstitute o Moq, eligiendo uno. Reloj, IDs y proveedores se abstraen solo donde la prueba/reproducibilidad lo exige.

### 14.2 Integración backend

- migración desde base vacía;
- repositorios/SP contra SQL Server 2025/Azure SQL de test;
- TVP y orden/tipos del `DataTable`;
- concurrencia por `ROWVERSION`;
- búsqueda con volumen y planes de ejecución;
- rotación simultánea de refresh;
- aislamiento tenant A/B para leer, modificar y borrar cada recurso;
- webhook duplicado/fuera de orden;
- claim/retry de jobs y cierre de ImportRun;
- contratos Dapper/SP 9B-A, carreras de claim/lease, replay exacto, reporte parcial, roles SP-only y
  garantía de cero writeback a tablas 9A;
- Blob/proveedores con emulador o fake contractual; sandbox real solo en suite separada.

Los tests SQL no deben usar SQLite: sus tipos, Full Text, SP, locking y `VECTOR` no son equivalentes.

### 14.3 Frontend

- Vitest + React Testing Library para formularios, guards, estados de carga/error, refresh single-flight y paywalls;
- MSW o adapter equivalente para contratos HTTP;
- axe para chequeos de accesibilidad automatizados;
- E2E de journeys críticos en FASE 12: registro/onboarding/recomendación/favorito/checkout admin import.

### 14.4 Corpus de evaluación

9B-A exige un conjunto inmutable revisado por una persona experta, construido desde snapshots
históricos exactos de 9A:

- al menos 30 proyectos, 100 oportunidades distintas y entre 300 y 5000 pares etiquetados;
- relevancia ordinal `0=Irrelevante`, `1=Relevante`, `2=Muy relevante`;
- splits `Development`/`Test` congelados por proyecto para impedir fuga entre ambos;
- manifiesto, provenance, reviewer, hashes de labels y versiones exactas de proyecto/oportunidad;
- diversidad de convocatorias completas, ambiguas, rolling, cerradas e internacionales, monedas,
  cofinanciamiento, antigüedad y perfiles incompletos.

Las métricas de ranking se calculan en `Test` como macro-promedio por corrida/proyecto 9A, no sobre
un ranking global del corpus. El gate de referencia requiere cobertura ≥95%, éxito del proveedor
≥99%, Recall@10 ≥0,80, nDCG@10 ≥0,75, mejora nDCG ≥0,05, cero promociones de hard-fail y
corpus completamente evaluado; también se informan baseline nDCG, MRR@10, cambio medio de rank,
costo incremental y p95. El fake local nunca es elegible aunque alcance umbrales.

El ground truth de extracción y evidencia estructurada sigue siendo una necesidad distinta de 9B-B.
Allí se medirá exactitud por campo y evidencia/`null`; no se mezcla ese objetivo generativo con las
métricas de ranking de 9B-A.

## 15. Riesgos y mitigaciones

| Prioridad | Riesgo | Impacto | Mitigación |
|---|---|---|---|
| P0 | datos vencidos/incorrectos | pérdida de confianza y postulaciones fallidas | evidencia, `LastVerifiedAtUtc`, autocierre, calidad, revisión y muestreo |
| P0 | acceso cruzado entre ONG | incidente grave de privacidad | route tenant, policy, filtros, auditoría y matriz A/B |
| P0 | IA inventa requisitos/montos | recomendación dañina | schema estricto, evidence, `null`, corpus dorado y aprobación humana |
| P0 | pago falso/inconsistente | pérdida financiera/acceso indebido | hosted checkout, webhook verificado, GET autoritativo y reconciliación |
| P0 | fuente sin derecho de uso | bloqueo legal/operativo | allowlist, compliance review, términos/robots, kill switch |
| P0 | prompt injection o SSRF | exfiltración/compromiso | proceso aislado, sin tools, bloqueo de red y límites |
| P0 | archivo malicioso o bomba de descompresión | compromiso del parser/agotamiento de recursos | cuarentena, Defender on-upload, identidad mínima, límites y rechazo cerrado |
| P0 | enlace de postulación fraudulento/alterado | phishing o desvío de postulantes | dominio de fuente aprobado, revisión humana, reputación/allowlist y aviso antes de salir |
| P1 | cookies bloqueadas por topología cross-site | login/refresh intermitente | dominios same-site o BFF decidido antes de auth; pruebas en navegadores restrictivos |
| P1 | carrera de refresh entre pestañas | cierre de sesión o falsa detección de replay | Web Locks/BroadcastChannel y ventana servidor `refresh_conflict` sin emitir token |
| P1 | creación abusiva de tenants Free | evasión de cuotas/costo | `organizations.max_owned`, rate limit y excepción auditada |
| P1 | doble checkout | cobro duplicado y soporte manual | una sesión pendiente por organización, lock, idempotencia y reconciliación |
| P1 | webhook duplicado/desordenado o semántica cambiante | estado comercial incorrecto | adapter con fixtures, evento durable, consulta autoritativa y transiciones monotónicas |
| P1 | PII enviada al proveedor IA | incumplimiento de privacidad | allowlist, redacción, DPA/retención y tests de serializer |
| P1 | pocos fondos de calidad | producto sin valor aunque el software funcione | estrategia editorial, fuente responsable y KPI de vigencia |
| P1 | duplicados | mala UX y alertas repetidas | IDs externos, URL hash, fingerprint y revisión de candidatos |
| P1 | score poco creíble | baja conversión | desglose, cobertura, warnings, versionado e IA fuera del cálculo |
| P1 | costo variable de IA | margen impredecible | hash/cache, batching, modelo por tarea, cuotas y budgets |
| P1 | matching N×M | degradación SQL | candidatos, top N, invalidación incremental y batch |
| P1 | fechas/monedas ambiguas | falsos matches | fecha original/precisión; misma moneda o unknown; no conversión ficticia |
| P1 | cambio de formato externo | importaciones fallidas | adapter por fuente, contract tests, alertas y pausa automática |
| P1 | lock-in de proveedor | migración costosa | interfaces estrechas, IDs propios, raw recuperable y fallbacks |
| P1 | scope excesivo | retraso del piloto | verticales cerradas, gates y V2 explícita |
| P2 | SEO limitado por SPA | menor adquisición orgánica | landing estática cuidada; prerender/SSR en V2 si métricas lo justifican |

Riesgo de negocio no resoluble solo con arquitectura: conseguir y mantener un catálogo autorizado, vigente y suficientemente amplio. Debe tener owner, proceso editorial y métricas desde el inicio.

## 16. Decisiones que requieren validación de negocio antes de su fase

No bloquean FASE 1, pero sí sus respectivas implementaciones:

1. entidad jurídica y país que recibirá pagos;
2. precios, moneda, trial, límites y período de gracia;
3. proveedor de email y dominio/remitente verificado, con idempotency key o reconciliación por referencia demostrada para no reenviar tras respuesta incierta;
4. primera fuente API/RSS y derechos de reutilización;
5. taxonomía inicial revisada por experto y seed Chile;
6. proveedor/modelo real de extracción y embeddings, presupuesto mensual, DPA y política de
   retención/borrado para 9B-B;
7. criterio editorial mínimo para publicar y responsable de aprobación;
8. política de privacidad, términos, retención y eliminación;
9. dominio final y topología `app`/`api` para cookies/CORS;
10. SLA y volumen real del piloto.

## 17. Roadmap por fases y criterios de salida

### Gate común después de cada fase

- `dotnet build` exitoso;
- todos los tests aplicables pasan;
- `npm build` y tests frontend pasan cuando exista frontend;
- migrations se aplican desde cero y, desde la segunda migration, sobre una base anterior;
- OpenAPI, README y `.env.example` actualizados;
- lista de archivos creados/modificados y variables nuevas;
- sin secretos, `TODO` ni `NotImplementedException` pertenecientes al alcance completado;
- revisión de seguridad/tenancy proporcional al cambio.

### FASE 0 — Diseño (este documento)

**Entrega:** alcance MVP/V2, arquitectura, datos, API, amenazas, decisiones y roadmap.
**Salida:** aprobación explícita de las ADR y de los límites. No hay build porque el workspace aún no contiene código.

### FASE 1 — Solución compilable vacía

- solución/proyectos y dependencias en la dirección definida;
- configuración Options, `.env.example`, `.gitignore`, Serilog, CorrelationId, ProblemDetails, OpenAPI y health básicos;
- React/Vite/TS/Tailwind/shadcn, router, Query provider, tema e i18n base;
- tests smoke y README inicial.

**Salida:** API y worker arrancan, frontend renderiza shell y CI local reproduce builds.

### FASE 2 — Base de datos

**Estado:** completada el 2026-08-12. La migración `001_initial_schema.sql`
(`SHA-256 a6fe03d9ae312ee907ab63500be1c5dd7a8158327ed4a3ae5d97e163ad39884c`) quedó
aplicada en `res`: 1/1 aplicada, 41 tablas de negocio más metadata, 4 TVP y 8 SP. Una
segunda ejecución de `--apply` confirmó idempotencia con 0 aplicadas / 0 pendientes.

- migrador forward-only y `FundingPlatform_SchemaVersions`;
- catálogos/seed Chile, plans/features Free, identidad, organizaciones, fondos/fuentes y outbox base;
- FKs, checks, índices, TVPs y SP iniciales;
- `ISqlConnectionFactory`/Dapper y pruebas SQL reales.

**Salida verificada:** base creada repetiblemente desde cero; backups automáticos/PITR
verificados y ventana recuperable registrada; rollback operativo forward-only probado
sin sobrescribir la base compartida ni tocar objetos ajenos.

### FASE 3 — Autenticación

- Identity Core + stores Dapper, JWT, refresh rotativo, email verification/reset, TOTP/recovery para admins, lockout y rate limits;
- Data Protection persistido en Blob y protegido con Key Vault, cookie same-site definida y `AdminCli` con contraseña interactiva no registrable;
- UI completa de auth y refresh single-flight.

**Estado:** completada. El journey registro→verificación→login→refresh→logout/reset,
setup/challenge/recovery MFA, entrega de correo y bootstrap interactivo se ejercitó en el
entorno local conectado a Azure. La revocación por `SecurityVersion`, la carrera multitab
`refresh_conflict` y el replay de familia quedan cubiertos por pruebas automatizadas.

### FASE 4 — Perfil de organización

- creación, membresía, TenantContext, onboarding y perfil N:N;
- completitud/versionado y UI responsive.

**Salida:** actualización transaccional y suite A/B de aislamiento sin fugas.

**Estado:** completada. La migración aditiva `005_organization_onboarding.sql` está aplicada
en `res`; la API trabaja exclusivamente con `PublicId`, exige una sesión completa, valida
membresía activa en SQL, limita atómicamente la creación propia del MVP y usa `ETag/If-Match`.
El frontend incorpora alta inicial y edición responsive en tres secciones. Los smoke tests
reales verifican creación, membresía admin, aislamiento A/B del listado, snapshots v1/v2,
relaciones N:N y outbox con rollback.

### FASE 5 — Proyectos

- entidad `Project`, relaciones, snapshot/versionado y funding gap;
- CRUD tenant con ETag, publicación moderada y perfil público;
- UI de creación, edición y listado por organización.

**Salida:** una ONG crea dos proyectos distintos y el sistema preserva aislamiento, versiones,
moneda y estados sin mezclar sus necesidades de financiamiento.

**Estado:** completada. Las migraciones `006`/`007`/`008`/`009` están aplicadas en `res`. El corte
incluye Microsoft Entra SSO opt-in, CRUD tenant, `ETag/If-Match`, snapshots, funding gap,
readiness, solicitud y archivo idempotentes, cola y detalle Admin/SuperAdmin protegidos por MFA,
aprobación/rechazo auditables, outbox transaccional y proyección pública sin PII. El frontend
incorpora listado/edición, estados editoriales, revisión administrativa, perfil público responsive
y vinculación Microsoft con resultado idempotente explícito. Build, lint y smokes SQL quedaron
limpios. Los medios externos se mantienen fuera de esta fase; la ingesta documental agregada en
FASE 7B valida malware, licencia y procedencia y tampoco publica imágenes o documentos por sí sola.

### FASE 6 — Funders, oportunidades y workflow editorial

- entidad canónica de funder separada de la fuente técnica;
- oportunidad, relaciones, provenance/evidence y CRUD admin mínimo;
- workflow draft/review/published/deactivate y carga manual/archivo seguro sin IA.

**Salida:** un admin publica y corrige funders/oportunidades con ETag/auditoría; el usuario solo ve
contenido publicado. El flujo local de upload prueba cuarentena, `Clean`, `Malicious`, `Failed`,
timeout y retry mediante un fake señalado como tal. Producción nunca lo confunde con Defender.

**Estado:** completada en código y base el 2026-08-21. `010` y `011` están aplicadas en `res`.
La migración operativa posterior `012` agrega el grant auditado de SuperAdmin; el cierre de esa etapa fue
12/12 migraciones, 12/12 smokes SQL, segunda aplicación sin cambios y 833 objetos propios.
El gate actual aprobó 171 pruebas .NET y 48 de frontend, además de build/lint limpios. La carga
real con la identidad local requiere aún asignar sus roles Blob de mínimo alcance; esto no cambia
el código ni autoriza el uso de account keys. FASE 7B incorporó Event Grid/Defender fail-closed y
parsing documental; su activación productiva continúa como tarea explícita del operador.

### FASE 7A — Adquisición durable inicial

- Functions timers, outbox/Queue, scheduler/watchdog, runs, raw inmutable y consola operativa;
- integración oficial Grants.gov gobernada por estado, compliance y kill switch;
- persistencia en dos pasadas, snapshot normalizado rehidratable, leases/retries e idempotencia;
- revisión humana obligatoria: staging solo a borrador, sin autopublicación.

**Salida:** jobs reanudables e idempotentes; retries no duplican datos y toda observación conserva
fuente, hash, fecha y estado. Una fuente fallida no detiene las demás.

**Estado:** completada. El vertical API/Application/Infrastructure/Workers/frontend está
implementado. `013`, `014` y el hotfix forward-only `015` están aplicados en `res`. El smoke real
posterior a `014` detectó un defecto acotado en el patrón SQL de correlation IDs con guion; `015` lo
corrigió sin modificar la migración aplicada. El cierre observado el 2026-08-22 confirmó 15/15
migraciones, 15/15 smokes con rollback, 940 objetos propios y segunda aplicación 0/0.

Hashes principales del cierre: `014`
`1d744783127a8107d22c6218b12c7be74161464dd034fca94d4a3a2822500b6e`, smoke `014`
`beead55a6d68222d2d75b8b5744cd15e1dcdbf457f61d2648d5c56bbe40196f5`, `015`
`ee0a75641df9de32210ff54979b06c5a10542ffca1cc07fd8437eed34471f88c` y smoke `015`
`b6598cc6df6d667d17b257d20f5cac1572ad958dbd506bc4dbd4dcb5e8913fa8`.

### FASE 7B — Documentos y fuentes gobernadas

- parsing PDF aislado y acotado de archivos `Clean` ya promovidos al container confiable;
- receptor Entra autenticado para Event Grid/Defender, recibo mínimo, ETag/SHA exactos y watchdog;
- RSS oficial fijo con compliance vigente, allowlist, `robots.txt`, rate, bytes, retención y kill
  switch; sin crawler genérico;
- decisión humana de duplicados en consola, ETag/idempotencia y cero autopublicación;
- redacción SQL y borrado exacto de Blob/versiones/snapshots bajo política de retención.

**Salida:** cada archivo/fuente conserva licencia, procedencia, hash y evidencia; ningún contenido
malicioso, sin compliance o no revisado llega a superficies públicas.

**Estado:** completada en código y base el 2026-08-22. La migración
`016_governed_document_extraction.sql` quedó aplicada con SHA-256
`96d435dcee7f898a44b59f918c61e52717211476c365231f6f3518288430ec52`; su smoke vigente, tras la
corrección exclusiva del fixture durante 8A, tiene SHA-256
`4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c`. La topología separa el
worker general del extractor mediante cuatro UAMI, conexiones host, cola de datos y scopes Blob. El
parser solicita
cancelación a 120 segundos y Functions impone un límite exterior de 5 minutos; no se declara como
sandbox o preempción dura.

El hardening `017_primary_funder_identity_hardening.sql` quedó aplicado como corrección
forward-only con SHA-256
`214848f1384ba2f6b428fd550e363c538aee509284de49bd2c8feb1a744382ad`; su smoke tiene SHA-256
`b38a14a457e197efdd1b283613622bc61a370855898d539793714478bcb27862`. Impide inferir identidad de
funder por nombre normalizado, exige coincidencia HTTPS canónica fuerte para reutilizarlo y registra
conflictos/legado incierto sin eliminar primary links cuya procedencia no se puede probar. Un
conflicto abierto bloquea catálogo/publicación. `016` permanece inmutable y ninguna ruta autopublica.

El cierre ejecutó `--validate` 1/13 con rollback, `--apply` 1/13, 17/17 smokes con rollback,
segunda aplicación 0/0 y `--status` 17 locales/17 aplicadas, sin discrepancias y con 1251 objetos
propios.

La integración productiva de Defender/Event Grid y la fuente `official-rss` siguen deshabilitadas
hasta que el operador configure infraestructura, RBAC y políticas exactas, y valide un E2E real. La
fase no creó esos recursos ni activó servicios pagados.

### FASE 8A — Catálogo organizacional de oportunidades

- búsqueda protegida con texto, filtros combinables, órdenes allowlisted y paginación server-side;
- detalle publicado completo y fuentes vinculadas;
- favoritos privados por usuario dentro de la organización;
- Full-Text provisionado por un paso no transaccional explícito, con fallback literal.

**Estado:** completada en código y base el 2026-08-22. `018_funding_search_and_favorites.sql` quedó
aplicada con SHA-256 `4b1fd2c54220a5209e39a3ed78c890220617707325e4ffdf236a54f4809492c4`;
su smoke tiene SHA-256 `ad078055fff7bfc41b03a3bfa56ecc3e198d9c9688940213b71016fa36b76caa`.
El provisioning `001_funding_opportunity_full_text.sql` quedó en SHA-256
`4dad7d2263baa0b55c65ea8e5925a4194a0e5cd6de854f3d85742a542cc4b2c5`.

El cierre ejecutó `--validate` una migración/10 lotes con rollback, `--apply` una/10, 18/18 smokes
con rollback, segunda aplicación 0/0 y dos provisiones idempotentes de un script/tres lotes. El
estado final confirmó 18 migraciones locales/18 aplicadas, 1267 objetos propios y Full-Text listo.
El fixture histórico `016` se corrigió para no crear un timestamp futuro; la migración `016`
permaneció inmutable y el smoke final quedó en SHA-256
`4ae81e9760792c929a9c1a10fcfce663e3caa98e3f1bc5305f0e07eddbb9540c`.

El gate de código terminó con build .NET en 0 warnings/0 errores, 242/242 pruebas unitarias, 101/101
de integración, lint frontend, 16 archivos/91 pruebas Vitest y build de producción correctos. 8A no
implementa ni promete matching, score, IA o elegibilidad. El complemento literal permanente del modo
híbrido queda registrado como deuda P2 de rendimiento, sujeto a planes y mediciones de volumen.

### FASE 8B — Project marketplace y actividad básica

- marketplace anónimo de proyectos con filtros, orden y paginación server-side, detalle canónico y
  perfiles públicos seguros de organizaciones;
- postulaciones privadas enlazadas obligatoriamente a organización/proyecto/fondo, con owner,
  seis estados, idempotencia durable y concurrencia optimista;
- calendario básico derivado de postulaciones, proyectos y favoritos, sin persistencia duplicada.

**Estado:** completada en código local el 2026-08-24. El frontend incorpora `/marketplace`,
`/marketplace/projects/:slug`, `/marketplace/organizations/:organizationId`, `/applications` y
`/calendar`; conserva `/projects/public/:slug` como alias. La API materializa los endpoints públicos
`/api/v1/marketplace/*` y las rutas privadas organizacionales `/applications` y `/calendar`.

La superficie pública es fail-closed: exige proyecto activo/publicado, organización activa con perfil
apto y catálogos vigentes; usa DTO allowlisted, cache corta y rate limit, sin PII, membresías ni
drafts. La superficie privada exige sesión completa, membresía, aislamiento tenant mediante `404`,
`no-store` y rate limits. El alta usa `Idempotency-Key`; la edición usa ETag/`If-Match`, y solo el
owner o un Admin organizacional puede mutar. El calendario admite hasta 366 días, no crea una tabla
propia y excluye postulaciones descartadas.

`019_project_marketplace_applications_calendar.sql` (1184 líneas/15 lotes, SHA-256
`eeb6962329261b6736b4e3584d1409e622f1a26a2947bbe3b3ae25a660df53ef`) y su smoke (860 líneas/dos
lotes, SHA-256 `7feccc8bb44f63f776df0b16f313ac9e06c8a421d51904764fe24d1da9732ab9`)
quedaron preparados, pero por instrucción del propietario no se ejecutaron `--validate`, `--apply`,
`--test` o `--status` contra Azure SQL ni otro entorno DB. El último estado observado de `res`
continúa siendo 18/18 de 8A; no se declara 19/19, un nuevo object count ni un smoke SQL real. El
parsing local ScriptDom terminó correctamente y pasaron 4/4 pruebas de arquitectura; son gates
estáticos, no una ejecución SQL.

El gate local de código terminó con build .NET en 0 warnings/0 errores, 261/261 pruebas unitarias y
114/114 de integración. En frontend pasaron lint, 19 archivos/98 pruebas Vitest y el build de
producción. La fase no implementa matching, compatibilidad, score, recomendaciones, IA, embeddings,
alertas, networking o billing.

### FASE 9A — Compatibilidad determinística por proyecto

- TOP 200 sincrónico y determinístico de oportunidades abiertas, sin producto cartesiano completo;
- nueve reglas versionadas: cinco hard gates `Pass`/`Fail`/`Unknown` y cuatro reglas blandas;
- score conservador, cobertura sin renormalizar, razones, advertencias y evidencia allowlisted;
- ejecuciones inmutables, idempotencia durable, versiones de entradas, huellas e `isCurrent`;
- API privada de alta/historial/detalle y UI `/matching` con `/recommended` como alias.

**Estado:** completada en código local. `020_deterministic_project_matching.sql` y su smoke están
preparados localmente; no se ejecutaron `--validate`, `--apply`, `--test` o
`--status` contra SQL Server/Azure SQL. `019` también permanece sin aplicar; el último estado
observado de `res` es 18/18 de 8A. No se declaran smokes SQL, objetos o migraciones adicionales
aplicados.

Las huellas locales congeladas son `984450d06cb17447be8b3af595caa6415ce9e59f2b5e4d53bc3466ce2b25921e`
para la migración (1718 líneas/16 lotes) y
`a827cc9234831c757583b2e6776c13d2550985dcce566653dc171616f3e036f6` para el smoke (924 líneas/un
lote). El parsing T-SQL 170 y la inspección AST locales terminaron limpios; no equivalen a una
ejecución DB.

El gate local pasó build .NET (0 warnings/0 errores), 281/281 pruebas unitarias, 123/123 de
integración, lint frontend, 21 archivos/104 pruebas Vitest y build de producción. El foco
archived/matching pasó 2 archivos/6 pruebas. Estas comprobaciones validan código y contratos locales,
no la aplicación o ejecución de SQL.

**Salida:** compatibilidad reproducible por versiones de proyecto, perfil institucional, contenido
del fondo, motor, perfil/ruleset, calendario y catálogo. Los estados visibles son `Compatible`,
`Incompatible` y `Datos insuficientes`. Es un resultado orientativo: 9A no usa IA/embeddings, no
constituye una recomendación y no confirma elegibilidad.

### FASE 9B-A — Embeddings y evaluación semántica en sombra

- configuración inmutable, embeddings `VECTOR(1536)` project-first, jobs/leases/retries y presupuesto;
- corpus humano versionado, backfill idempotente y ranking coseno exacto por corrida histórica 9A;
- API agregada Admin/SuperAdmin con MFA para crear/listar/detallar/reportar evaluaciones;
- fake léxico determinístico sólo en `Development`/`Testing`; hosted deshabilitado/fail-closed;
- ninguna mutación de score, clasificación, vigencia, orden o UI de 9A.

**Estado:** fase completada en código local. `021_shadow_semantic_evaluation.sql` y su smoke no se han
aplicado ni validado contra SQL Server/Azure SQL; `019` y `020` también siguen pendientes. No hubo
llamadas OpenAI, entrenamiento, Azure ML, recursos Azure ni costo de proveedor.

Artefactos locales congelados: migración `021`, 3995 líneas/48 lotes y SHA-256
`f6a7cc2a7faba60edce4611c58f56850cf6fd1000b50d7a2f55a53ab188737c3`; smoke, 1710 líneas/un lote y
SHA-256 `64ad6a521c0eaa6bbb3674b8b0966e572731110eafef57c84b87726baa94cfbc`. ScriptDom parseó ambos
localmente; no se ejecutaron contra un motor SQL.

El gate local pasó build .NET con 0 warnings/0 errores, 324/324 pruebas unitarias, 136/136 de
integración, lint frontend, 21 archivos/104 pruebas Vitest y build de producción. Son verificaciones
de código/contrato, no una validación DB ni una llamada a un proveedor.

**Salida:** reporte medido de cobertura, éxito, Recall@10, nDCG@10/baseline/delta, MRR@10, rank,
costo incremental, p95 y seguridad de hard gates. El fake nunca es promovible y un reporte parcial
queda explícitamente inelegible.

### FASE 9B-B — Proveedor real, gobierno e IA generativa

**Revisión 2026-08-25:** quedó implementada localmente la capa de código y persistencia gobernada,
pero no se activó ni evaluó un proveedor. `022` agrega políticas inmutables de proveedor/modelo/
capability/endpoint, hashes de DPA y términos, ZDR, residencia, precios, aprobador y expiración; una
configuración real de embeddings queda ligada por FK y fingerprint. `023` agrega configuraciones,
runs, jobs, leases, presupuesto y resultados estructurados para explicaciones administrativas sólo
en modo sombra.

El provider boundary usa `/v1/embeddings` para `text-embedding-3-small` o
`text-embedding-3-large`, siempre con dimensión 1536, y `/v1/responses` con el snapshot exacto
`gpt-5.6-sol`, `store=false` y JSON Schema estricto. Los hosts oficiales son allowlisted; no hay
redirects ni fallback hosted al fake. Provider, modelo y fingerprints provienen de SQL inmutable,
nunca del request HTTP o de aliases de entorno. La API key sólo puede inyectarse al worker desde
configuración secreta/Key Vault y no se guarda en SQL, logs o responses.

El input de explicación es efímero y project-first: se deriva de un resultado Test/primary
congelado de 9B-A y de sus nueve reglas 9A. No incluye títulos de proyecto, nombres de organización,
IDs de tenant/usuario, email, RUT, URLs, notas ni billing; máximo 8192 bytes UTF-8. SQL guarda el
hash, no el JSON. C# exige propiedades, orden, rangos, vocabulario y nueve reglas exactas antes de
llamar. La respuesta persiste únicamente assessment, resumen de hasta 300 caracteres, razón estable,
máximo tres reglas citadas, uso/costo/latencia y hashes; no prompt ni raw response.

Los endpoints nuevos son `POST /api/v1/admin/semantic-explanation-runs` y
`GET /api/v1/admin/semantic-explanation-runs/{runId}`. Exigen Admin/SuperAdmin con MFA reciente,
rate limit, no-store e idempotencia durable. No existe ruta cliente ni writeback. La explicación no
modifica 9A, el ranking 9B-A, hard gates, score, clasificación, vigencia u orden visible y siempre se
presenta como auditoría interna orientativa, no como elegibilidad o recomendación.

Huellas locales: `022` `d961a90278a8081c175418f6331be6dd19b65a0563b75fe6c857417c266f0f56`
(788 líneas/9 lotes), smoke `4204196816b74194ee012b63bd3c0a184e7dfa649bcd6b4f82a80d9370ca9b22`
(362/un lote); `023` `add58976e0963dc0cec0b434d18415869eb5f0e96e0bed35264e3363a021eca9`
(2164/25 lotes), smoke `11d1a4d51008e0d6c6c27ac9265a4078955911506de8f863fcdad0298ca62a3c`
(335/un lote). ScriptDom pasó los cuatro. Build .NET: 0 warnings/0 errores; Unit 347/347;
Integration 142/142; frontend lint, 21/104 y build.

No se ejecutaron `019`–`023` contra SQL Server/Azure SQL, no se llamó a OpenAI, no se crearon
recursos Azure y no hubo costo. Para un go/no-go todavía se requiere DPA/ZDR aprobado para el
proyecto exacto, secreto en Key Vault, precios vigentes, corpus humano real, ejecución controlada de
evals y revisión de privacidad/costo/calidad. La extracción generativa, evidence documental y toda
promoción continúan diferidas hasta esa evidencia. Entrenar un modelo propio o usar Azure ML no es
un requisito del MVP.

**Salida de código:** proveedor reemplazable y gobernado, Structured Outputs acotado y explicación
shadow reproducible. **Salida operacional pendiente:** decisión go/no-go basada en corpus real.

### FASE 10A — Búsquedas guardadas y alertas diarias

- búsquedas privadas por usuario+organización, filtros normalizados y reapertura desde la SPA;
- digest email diario `PublicReady`, historial, baja segura y delivery idempotente con leases;
- runtime apagado por defecto y rol SQL mínimo del worker.

Código local completado mediante `024_saved_search_alerts.sql` (1264 líneas/19 lotes, SHA-256
`f6222f40fb6b6ad436e6496d383f4b05900458e4201d9176165dcf9d113e99a4`) y smoke (293 líneas/un
lote, SHA-256 `24f5aa7def2ecd6b7bf6f9c5c6843e105f34afca1fad0f69c8e4c5f484d7b035`). Gates:
ScriptDom, build .NET 0 warnings/0 errores, Unit 360/360, Integration 149/149, lint frontend,
23 archivos/108 pruebas Vitest y build. `019`→`025` no se ejecutaron contra una base; no se llamó a
Communication Services ni se envió email.

El pipeline y calendario ya pertenecen a 8B; 10A no los duplica. La activación exige aplicar las
migraciones, crear el usuario Entra/rol mínimo, verificar dominio y remitente, asignar Email Sender,
guardar la clave HMAC en Key Vault y habilitar `Alerts` de forma explícita.

### FASE 10B — Networking básico

- directorio privado para miembros, derivado solo de ONG/proyectos marketplace-ready y opt-in;
- preferencias `IsDiscoverable`/`AllowRequests` separadas, editables únicamente por OrganizationAdmin;
- solicitud `Connect` con proyecto público opcional, mensaje privado allowlisted, purpose fijo,
  idempotencia durable, un par activo y cuotas HTTP+SQL;
- aceptación/rechazo por destinatario, cancelación por remitente y bloqueo explícito, todo con ETag;
- ningún chat, contacto automático, PII de miembros, proyecto draft o cambio de matching.

Código local completado mediante `025_organization_networking.sql` (717 líneas/11 lotes, SHA-256
`f0add029613446ad5350b9ddaa8873497e4074a5483b40c6518838941abc24cf`) y smoke transaccional
(273 líneas/dos lotes, SHA-256
`02485713222d60c4a87b5bc514bd34a1b1f094247625bd75d4c8976335e87af7`). Las tablas conservan
preferencias, solicitudes/snapshots e idempotency ledger; triggers impiden borrar o reescribir el
historial fuera de sus transiciones. API y UI usan sesión completa/no-store, tenant server-side,
roles revalidados, `Idempotency-Key`, ETag y estados seguros.

Gate local: ScriptDom mediante tests de infraestructura, build .NET 0 warnings/0 errores,
Unit 370/370, Integration 156/156, lint frontend, 25 archivos/111 pruebas Vitest y build. `019`→`025`
no se ejecutaron contra SQL Server/Azure SQL; `res` sigue observado en 18/18 y la activación requiere
validate/apply/smoke/reapply/status en un ambiente autorizado.

**Salida:** networking privado, opt-in y moderado sin modificar matching, postulaciones ni alertas.

### FASE 11 — Suscripciones y administración completa

**Estado 2026-08-26:** implementación local cerrada mediante `026` y el complemento aditivo `028`:
planes y precios separados,
Free efectivo por ausencia de suscripción pagada, entitlements server-side, checkout idempotente,
webhook autenticado con inbox durable, consulta autoritativa y reconciliación. La API y frontend
exponen planes, suscripción/uso, cancelación/reanudación y vistas administrativas sin datos de
tarjeta ni payload crudo. El adapter real queda limitado a Mercado Pago sandbox y
`Billing:Enabled=false`; Professional/Organization no son comprables hasta aprobar precios e IDs de
prueba. `028` completa el resumen del usuario con proyectos, postulaciones, calendario y alertas, y
las vistas administrativas de organizaciones y errores sanitizados. No se aplicó `019`→`028` ni se
conectó DB/Azure/proveedor.

- precios/uso, Mercado Pago **sandbox**, checkout, webhook y reconciliación;
- revisión/deduplicación, fuentes, runs, errores, usuarios, organizaciones y billing;
- paywalls backend/frontend, dashboard operativo y auditoría consultable.

**Salida:** operación cotidiana sin SQL manual; billing sandbox E2E, matriz de entitlements y
policies administrativas verificadas. No se cobran pagos reales todavía.

### FASE 12 — Hardening, testing y despliegue

**Estado FASE 12A (2026-08-25):** IaC de `dev` preparada localmente en Bicep, sin ejecutar Azure.
Incluye presupuesto con notificaciones, SQL serverless auto-pause, API Container Apps Consumption
0,5 vCPU/1 GiB con réplica `1` reducible a `0`, ACR Basic privado, Static Web Apps Free, Functions
Flex, tres fronteras Storage, cinco UAMI, Key Vault/Data Protection y observabilidad. La imagen API
es no-root, excluye secretos del contexto, se construye remotamente y se despliega por digest OCI.
Los workflows separan compilación sin credenciales de `validate`/`what-if`/`apply` manual mediante
OIDC; `apply` exige confirmación literal. La región se rechaza si no ofrece Container Apps, ACR y
Functions Flex. Quedan para 12B publicación de Functions/frontend, DNS/dominio común, secretos,
usuarios SQL mediante aprovisionamiento idempotente, aplicación `001`→`028` en la base dev vacía,
E2E, restore y decisión de piloto. `027` deja versionados los roles mínimos de API, worker general y
extracción, pero no crea principals ni membresías y no fue aplicado a ninguna base.

**Actualización FASE 12A (2026-08-27):** la infraestructura base de dev fue creada y Azure SQL quedó
disponible en `sql-rf-dev-ag26rf01-centralus/risefunding-dev`. Antes de aplicar, la cadena
`001`→`028` ejecutó correctamente `--validate`: 28 migraciones/348 lotes bajo una sola transacción y
rollback completo. La base dev continúa sin historial aplicado. Los intentos intermedios permitieron
corregir portabilidad/compilación en `019`, `021`, `022`, `023` y `025`; sus huellas vigentes son,
respectivamente, `6d6e9a0a86a3ea7ff31c5ae43f31b4528aaa16d9ad14cd9a9f1cbecdbad3ebcd`,
`e7f10a5b9fa50969c69abaefac9f56c8b23022886f39ccd93f2c7546c4127993`,
`a804657adabb4906da96fa2024025630782b4b0149c631f720513e401696a585`,
`4566bcacf528ed355033dbb80f0751ebb8e8a94cb5d6207126b426cf7a947ede` y
`06bf9e4351bb2054cb335a1e16cb9a4a6ec02c724dea1aafb005162eb801c6e4`. El smoke `019` vigente es
`eb346bf26c9226df80a93eb7bdd3f2900254f437e252ffaf94548254b4a8fbeb`. `--apply`, los 28 smokes,
Full-Text, principals runtime, paquetes de aplicación, E2E y restore continúan pendientes.

**Actualización posterior FASE 12A (2026-08-27):** `001`→`028` fueron aplicadas correctamente en
Azure SQL dev. El preflight posterior ejecutó `029_sql_hyphen_allowlist_compatibility.sql` en siete
lotes, completó los 29 smokes y revirtió todos los cambios; la cadena local validada suma 29
migraciones/355 lotes. `029` no modificó los checksums ya registrados y continúa pendiente de
aplicación, por lo que Azure conserva 28 migraciones en su historial. Full-Text, principals runtime,
bootstrap SuperAdmin, paquetes de aplicación, E2E y restore continúan pendientes.

- E2E, auditoría/revalidación de MFA administrativa, carga, accesibilidad y chaos/fallback acotado;
- IaC, CI/CD, Key Vault, App Insights, backups, restore y runbooks;
- staging y smoke tests de Azure.

**Salida:** restore probado, SLO/alertas activos, checklist de seguridad y aprobación del **primer piloto pagado**.

Hitos: alpha interna al terminar FASE 8; beta cerrada después de FASE 10; beta funcional con billing
sandbox después de FASE 11; piloto pagado/producción solo tras FASE 12. Funder Matching avanzado,
consorcios, donaciones, corporate challenges y Proposal AI permanecen en MVP 2/3.

## 18. Qué no se debe sobrearquitectar

- No crear microservicio por módulo.
- No introducir event sourcing, MediatR/CQRS framework o un rule engine genérico sin una necesidad medible.
- No crear `IRepository<T>` genérico: oculta consultas y no representa agregados reales.
- No implementar dos gateways, dos proveedores IA o todos los tipos de fuente simultáneamente; las interfaces prueban sustituibilidad.
- No añadir una segunda base “de logs” solo porque existe `CreateConnectionLog`.
- No precomputar cada combinación proyecto/fondo.
- No usar IA para reglas que SQL/C# puede evaluar exactamente.
- No modelar un grant recurrente como programa+rondas hasta que el catálogo muestre esa necesidad; cada edición anual es una oportunidad en MVP.
- No implementar conversión monetaria sin fuente/fecha de tipo de cambio.
- No construir un constructor visual de reglas; pesos/parámetros se administran inicialmente por seed/SP controlado.
- No crear traducciones en BD hasta publicar un segundo idioma; sí usar códigos estables desde hoy.

## 19. Resultado de FASE 0

Este documento conserva la arquitectura y el esquema lógico aprobados. FASE 1 materializó
la solución compilable y FASE 2 entregó el baseline SQL acotado descrito en su roadmap;
las tablas y capacidades diferidas se incorporarán en las migraciones de sus fases.

## 20. Cómo funciona FundingPlatform de punta a punta en 10 pasos

1. Una persona crea su cuenta, verifica el email y recibe una sesión con JWT corto y refresh token rotativo.
2. Crea o selecciona su organización; el servidor valida la membresía en cada operación y nunca confía en el `organizationId` del navegador por sí solo.
3. Completa el perfil institucional con geografía, áreas, beneficiarios, tipo, antigüedad, presupuesto, experiencia, idiomas y monto buscado.
4. Administradores y proveedores aprobados incorporan convocatorias; documentos grandes quedan en Blob y cada ejecución se registra.
5. El pipeline actual normaliza, deduplica y conserva evidencia; la extracción generativa de campos
   sigue diferida y lo desconocido permanece `null`.
6. Una persona administradora revisa los campos críticos y publica una oportunidad canónica con fuente y fecha de verificación.
7. El motor 9A descarta incompatibilidades explícitas y calcula reglas ponderadas; 9B-A compara por
   separado un ranking de embeddings y 9B-B prepara explicaciones administrativas en sombra, sin
   sumarlos al score ni cambiar el orden visible.
8. La organización ve compatibilidad orientativa, score, cobertura, razones y advertencias; puede
   buscar, guardar, marcar favorito y seguir su postulación. No recibe una recomendación semántica.
9. El plan de la organización determina límites y funciones; solo un webhook verificado y reconciliado puede activar una suscripción pagada.
10. Workers reimportan fuentes, recalculan matches y envían alertas idempotentes, mientras auditoría y telemetría permiten operar y explicar todo el recorrido.
