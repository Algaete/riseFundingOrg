# Mapa avanzado: publicado y validado en Azure dev — 2026-09-12

## Estado exacto

Código preparado en una copia aislada de `main`, sin el bloque de adjuntos.
Commit local: `d750805d5abbab9e4c60ff944f68bf3dbd177713`.
Base: `65e7ce51df768e511608bdef6890e7612aa2d173`.
Rama: `codex/advanced-map-release`.
Copia de publicación: `/private/tmp/rf-map-release.xgDZGN/worktree`.

El usuario autorizó explícitamente publicar los 29 archivos de este commit en el
repositorio **público** `https://github.com/Algaete/riseFundingOrg` y desplegar el bloque
en Azure dev. Push completado y [PR 21](https://github.com/Algaete/riseFundingOrg/pull/21)
creado. CI `34707073159` e infraestructura `34707073103` finalizaron correctamente.

El usuario concedió posteriormente permiso explícito para fusionar el PR 21 en `main`,
aplicar 049 y desplegar API/frontend de Azure dev, manteniendo adjuntos apagados y
la misma capacidad. PR fusionado; revisión de release:
`3784dc8585b22adbfec71a2d2b29d2fceeb9ea04`. La copia aislada está limpia en esa revisión
y su árbol coincide exactamente con el commit aprobado. Infraestructura de main
`34707747993` y CI de main `34707746786` aprobadas.
Release SQL completado mediante `check-dev-database.sh --release`, con SHA exacto:
preflight aprobado; 049 aplicada (1 migración, 3 lotes); reapply cero cambios;
49/49 smokes y 23 comprobaciones de resultados posteriores aprobadas. Los fixtures
se revirtieron y la regla temporal de una IP fue retirada; listado posterior vacío.
API publicada y validada (ejecución `34708508309`, revisión `0000008`), misma escala.
Digest nuevo: `sha256:642fd9001c3296d262e93c39436cad5e0c9b1dd54aa88d7d77cbd3bfa6a47295`.
Nueve consultas HTTP públicas correctas: CORS, forma y paginación, parámetros nuevos,
cinco rechazos 400, cinco tipos de organización y 249 países. El mapa público real
tiene cero proyectos en este corte; la exactitud con resultados no vacíos fue
verificada mediante los fixtures SQL revertidos, no mediante datos públicos ficticios.
Frontend publicado para la misma revisión (`34708798045`); validación de destino,
compilación/pruebas, publicación/verificación y navegador Azure correctos. Los cuatro
trabajos finalizaron con éxito. [Ejecución final](https://github.com/Algaete/riseFundingOrg/actions/runs/34708798045).
Lectura independiente: `deploy-meta.json` coincide con SHA/run exactos y
`/marketplace/map` responde HTML 200. SQL conserva `GP_S_Gen5`, mínimo 0,5/máximo 1,
autopausa 60 minutos después del despliegue.
Los registros locales de esta preparación no forman parte del commit público.

Lectura de configuración previa: SQL mínimo 0,5/máximo 1 vCore, autopausa 60 minutos;
API revisión `0000007`, una réplica mínima/máxima y adjuntos deshabilitados por defecto.
Se conservaron capacidad, autopausa y flags; la revisión API avanzó a `0000008`.
El verificador HTTP de solo lectura se ejecutó
fuera del repositorio después de publicar la nueva API; sus nueve consultas pasaron.

## Verificación terminada

- 943 pruebas unitarias .NET y 340 HTTP con repositorios simulados.
- 1.052 pruebas frontend; build, lint y tipos E2E correctos.
- 210 pruebas Playwright correctas; una omitida porque los metadatos de revisión
  Azure no existen en localhost. Capturas de 320/1024 px inspeccionadas.
- La skill de navegador no encontró ninguna instancia disponible; se usó la suite
  Playwright existente, con datos y sesiones sintéticos.
- Preflight en Azure SQL dev: migración 049 (3 lotes), 49/49 smokes y 23
  comprobaciones de resultados reales del procedimiento correctas.
- Las pruebas de resultados usan los mismos parámetros del repositorio de producción
  y consumen ambas tablas de resultados. Cubren paginación, moneda y montos,
  necesidades, IDs explícitos y exclusión de borradores/organizaciones no aptas.
- La transacción del preflight se revirtió, incluidas la migración y las cuentas/proyectos
  sintéticos. La aplicación definitiva posterior de 049 sí quedó persistida; se
  repitieron los 49 smokes y 23 contratos con rollback de fixtures, no de la migración aplicada.
- Se retiró la regla temporal de una IP de SQL; lectura posterior confirmó cero reglas
  con el prefijo temporal de esta comprobación.
- No se cambió capacidad, autopausa, infraestructura, workers ni flags de adjuntos.
  La validación sí puede despertar SQL bajo demanda.

## Cierre y límites

Autorizaciones, fusión, CI de main, release SQL, API, frontend y verificaciones finales
completados. La copia aislada de publicación quedó limpia en la revisión desplegada.
El worktree principal conserva las preparaciones locales ajenas al mapa, sin descartarlas.

[Abrir el mapa](https://salmon-glacier-0721afc0f.7.azurestaticapps.net/marketplace/map).
No se habilitaron adjuntos ni servicios nuevos; siguen reservados para el final.
Este release no completa las recomendaciones ligadas a brechas ni las integraciones
que requieren acceso externo. La verificación pública no utiliza cuentas reales ni
sustituye una aceptación posterior con proyectos reales y consentimiento de ubicación.

## Archivos exactos del commit (29)

- `database/Migrations/049_project_map_advanced_filters.sql`
- `database/Tests/049_project_map_advanced_filters_smoke.sql`
- `database/Fixtures/project_map_contract.sql`
- `database/README.md`
- `docs/PROJECT-MAP.md`
- `src/FundingPlatform.Core/Marketplace/ProjectMapModels.cs`
- `src/FundingPlatform.Application/Marketplace/ProjectMapService.cs`
- `src/FundingPlatform.Api/Endpoints/ProjectMapEndpoints.cs`
- `src/FundingPlatform.Api/Endpoints/MarketplaceEndpoints.cs`
- `src/FundingPlatform.Contracts/Marketplace/MarketplaceContracts.cs`
- `src/FundingPlatform.Infrastructure/Persistence/Marketplace/SqlProjectMapRepository.cs`
- `src/FundingPlatform.Infrastructure/Persistence/Migrations/DatabaseMigrationRunner.cs`
- `src/FundingPlatform.Infrastructure/Persistence/Migrations/ProjectMapSqlVerifier.cs`
- `tools/FundingPlatform.DatabaseMigrator/Program.cs`
- `frontend/funding-platform-web/src/features/marketplace/marketplace-api.ts`
- `frontend/funding-platform-web/src/features/project-map/project-map-api.ts`
- `frontend/funding-platform-web/src/features/project-map/project-map-page.tsx`
- `frontend/funding-platform-web/src/features/project-map/map-filters.ts`
- `frontend/funding-platform-web/src/features/project-map/map-filters-form.tsx`
- `frontend/funding-platform-web/src/features/project-map/map-filters.test.ts`
- `frontend/funding-platform-web/src/features/matching/discovery-matching-page.tsx`
- `frontend/funding-platform-web/src/i18n/project-map/es.ts`
- `frontend/funding-platform-web/src/i18n/project-map/en.ts`
- `frontend/funding-platform-web/src/i18n/ecosystem/es.ts`
- `frontend/funding-platform-web/src/i18n/ecosystem/en.ts`
- `frontend/funding-platform-web/e2e/project-map-checks.ts`
- `frontend/funding-platform-web/e2e/ecosystem-checks.ts`
- `tests/FundingPlatform.UnitTests/ProjectMapAdvancedTests.cs`
- `tests/FundingPlatform.IntegrationTests/ProjectMapEndpointTests.cs`
