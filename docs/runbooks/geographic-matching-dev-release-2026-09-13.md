# Release dev: matching geográfico y datos TEST

Publicación solicitada por el usuario con muestra persistente y claramente identificada.
No se desplegaron los cambios locales pausados de adjuntos, workers o infraestructura.

## Revisión publicada

- PR: https://github.com/Algaete/riseFundingOrg/pull/22
- Commit: `3d933a44f70e2e6a5a9cb46b4a338d2475292760`.
- CI main: https://github.com/Algaete/riseFundingOrg/actions/runs/34733383231 (aprobado).
  El primer intento falló por una espera de `findByRole('checkbox', {name:'Salud'})`
  en un test preexistente del editor; 1.073/1.074 pruebas de frontend pasaron.
  Los 17 tests del archivo y tres arranques separados del caso pasaron localmente.
  Se repitió una vez el job fallido completo, sin omitir pruebas ni cambiar la aplicación;
  el reintento, incluido el recorrido de navegador, quedó aprobado.
- Validación de infraestructura: https://github.com/Algaete/riseFundingOrg/actions/runs/34733383242 (aprobada; no despliegue Bicep).
- API: https://github.com/Algaete/riseFundingOrg/actions/runs/34734267706 (aprobada).
  Revisión activa/lista `ca-rf-dev-ag26rf01-api--0000009`;
  digest `sha256:7f4040a975ca32f03a9db816a1c158353dd69b1f83a8f4d397fe4d6857e15cd6`.
- Frontend: https://github.com/Algaete/riseFundingOrg/actions/runs/34734521568.
  **Todos los jobs aprobados**, incluido el recorrido final de navegador sobre Azure.
  Publicación, SHA, fallback SPA y CORS aprobados; `deploy-meta.json` confirma el commit
  y runId anteriores. Las pruebas de flujos privados de navegador usan respuestas
  simuladas; la aceptación con la sesión real corresponde al usuario. Los datos y
  resultados de la muestra sí se verificaron contra SQL real y la API pública.

## SQL y muestra

- Dos preflights reales con rollback verificaron 050/051, 51 smokes, el sembrado,
  el servicio de sugerencias con contextos reales y dos coincidencias compatibles reales.
- Release SQL del commit limpio/aprobado: 2 migraciones / 7 lotes; segunda aplicación
  0 cambios; 51 smokes + 23 comprobaciones de mapa posteriores aprobados con rollback.
- Sembrador AdminCli: preview aprobado, apply con commit y verify en una conexión nueva
  aprobado. La muestra permanece guardada; el rollback de verify no retira los TEST.
- Segunda ejecución de apply aprobada: reutilizó los registros y el mismo runId
  `091edf3c-20af-f111-a6a8-002248455055`, sin duplicar ni restablecer datos.
- Los dos fondos salen por `GET /api/v1/funding-discovery?query=TEST` con sus títulos TEST.
- Todas las reglas temporales de firewall SQL usadas en estas operaciones se retiraron.
  Inventario final de reglas `TemporaryMigrationClient-check-*`: vacío.
- SQL se mantiene en `GP_S_Gen5`, mínimo 0,5 / máximo 1 vCore y autopausa de 60 minutos.
  API conserva mínimo/máximo 1 réplica. Sin servicios nuevos ni cambios de autenticación.

## Acceso y expectativas

Guía pública: https://salmon-glacier-0721afc0f.7.azurestaticapps.net/test-data/matching-geografico.html

Organización privada de origen: `70510000-0000-4000-8000-000000000001`.
Proyecto privado: `70510000-0000-4000-8000-000000000002`.
Ejecución persistente del motor: `091edf3c-20af-f111-a6a8-002248455055`.
La cuenta propietaria es la indicada operativamente mediante `RF_DEV_SAMPLE_OWNER_EMAIL`;
no se creó ninguna cuenta ni se cambiaron contraseñas, MFA o roles globales.

En `/matching?organizationId=70510000-0000-4000-8000-000000000001&projectId=70510000-0000-4000-8000-000000000002&runId=091edf3c-20af-f111-a6a8-002248455055`,
pulsar **Buscar apoyos para este fondo**:

- Fondo `70510000-0000-4000-8000-000000000101` (UE): Francia, España, Alemania.
- Fondo `70510000-0000-4000-8000-000000000102` (Europa M49): Reino Unido, Francia, España.
- Estados Unidos queda excluido en ambos. Reino Unido queda excluido de UE.

Los nombres de todos los registros comienzan con **TEST · DATOS DE PRUEBA ·**.
Las organizaciones aliadas son ficticias y visibles, pero no aceptan solicitudes.
Las sugerencias no envían invitaciones, no usan IA y no alteran el puntaje del matching.
La selección usa áreas estructuradas compartidas (IDs 1 y 6), no inferencias del título.
Las fechas de perfil organizacional son sintéticas para mantener detrás los TEST en
la selección predeterminada; versiones/membresías registran el instante real de creación.

Retiro recuperable: seguir [el runbook de la muestra](geographic-matching-dev-sample.md),
comando explícito `dev-geographic-sample --disable`. No ejecutado: los TEST se dejan
disponibles para la revisión del usuario.
