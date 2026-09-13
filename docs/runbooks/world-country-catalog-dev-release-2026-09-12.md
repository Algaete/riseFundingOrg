# Azure dev: catálogo mundial de países — 2026-09-12

## Alcance y revisión publicada

El propietario autorizó publicar la corrección del selector de país en Financiadores.
Se aislaron 15 archivos en una rama/worktree separado; los cambios locales de búsqueda
unificada y la preparación de adjuntos no forman parte de esta publicación.

- [PR 19](https://github.com/Algaete/riseFundingOrg/pull/19), fusionado tras CI e infraestructura aprobados.
- Commit publicado: `1e96564e60b2bb53459bf4254133f7bed05279a7`.
- [CI del commit final](https://github.com/Algaete/riseFundingOrg/actions/runs/34675163780): aprobado.
- [Validación de infraestructura](https://github.com/Algaete/riseFundingOrg/actions/runs/34675163784): aprobada; no despliega recursos.
- [Workflow de frontend](https://github.com/Algaete/riseFundingOrg/actions/runs/34675762800).
- [Frontend dev](https://salmon-glacier-0721afc0f.7.azurestaticapps.net).

## SQL: aplicación y pruebas reales

Destino exacto: `sql-rf-dev-ag26rf01-centralus/risefunding-dev`, grupo `rg-rf-dev-ag26rf01`.
Se usó el migrador existente, con autenticación Azure CLI y validación de destino.
El release exigió checkout limpio del SHA exacto de main, CI aprobado y PITR de al menos siete días.

- Preflight previo: una migración/un lote y 48/48 smokes, todo revertido.
- Preflight del release: una migración/un lote y 48/48 smokes, todo revertido.
- Apply: migración `048_world_country_catalog.sql`, un lote aplicado.
- Reapply: cero migraciones/cero lotes.
- Verificación posterior: 48/48 smokes, fixtures revertidos.
- El smoke 048 creó un financiador sintético con Estados Unidos y lo actualizó a Japón;
  verificó los IDs persistidos y estado borrador. No dejó cuentas ni financiadores de prueba.
- Ambas reglas temporales de firewall se eliminaron. Consulta posterior: ninguna regla
  `TemporaryMigrationClient-check-*` restante.

## Frontend y lectura pública

La versión aislada pasó 967 pruebas de frontend, lint, build y tipos E2E;
también las cinco unitarias .NET específicas del catálogo. CI aprobó sus suites completas.
Los cuatro escenarios de navegador del catálogo cubren administrador/propietario,
320/1280 px, ES/EN, selección, creación, edición y reapertura con API sintética.

La API pública de Azure devolvió las 249 identidades esperadas de la migración,
comprobadas por ID y código ISO. Chile conserva `152/CL`; ejemplos adicionales:
Estados Unidos `840/US`, Japón `392/JP`, España `724/ES` y Brasil `76/BR`.

Static Web Apps sirve `deploy-meta.json` con el SHA anterior y runId `34675762800`.
Publicación, verificación de commit, SPA y CORS del workflow aprobadas.
La ruta `/admin/funders/new` y su módulo de entrada respondieron HTTP 200.
**Suite de navegador sobre Azure: aprobada el 2026-09-12 a las 05:44 UTC.**
La ejecución usa fixtures API sintéticos; la lectura pública y los smokes SQL
anteriores verifican por separado el catálogo y la persistencia reales.
No se abrió ni modificó una cuenta real mediante navegador.

## Costos y funciones preservadas

SQL mantiene `GP_S_Gen5`, mínimo 0,5/máximo 1 vCore y autopausa de 60 minutos.
Estaba pausado antes del trabajo y online al verificarlo después; la actividad de
despliegue lo despierta temporalmente. No se afirma costo cero ni pausa inmediata.

API conserva la revisión `ca-rf-dev-ag26rf01-api--0000007`; no hubo despliegue API/worker
ni Bicep. El worker conserva `PROJECT_ASSETS_ENABLED=false` e
`ImportWorkers__OnDemandOnly=true`; los temporizadores y triggers de adjuntos siguen
apagados. No se habilitaron servicios de escaneo, almacenamiento ni tareas nuevas.

Recargar la página para renovar el catálogo cacheado de una sesión anterior.
El campo sigue siendo un país opcional del financiador; no cambia la cobertura
global de las convocatorias ni la elegibilidad de sus beneficiarios.

## Registro público adicional

El despliegue y sus verificaciones terminaron correctamente. Un comentario adicional
de evidencia en el PR fue bloqueado por el control de seguridad por incluir metadatos
de infraestructura en un destino público; no se envió ni se reintentó. Este registro
permanece local. Publicar ese comentario requiere autorización específica del propietario.
