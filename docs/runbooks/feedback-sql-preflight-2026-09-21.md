# Preflight del feedback de septiembre — aprobado con rollback

## Resultado final de pruebas

`bash infra/scripts/check-dev-database.sh --preflight` terminó con exit0:

```text
Contrato SQL de mapa: 23 comprobaciones correctas; fixtures sin commit.
Contrato SQL de traducciones: 13 comprobaciones correctas; fixtures sin commit.
Preflight correcto: 8 migración(es), 40 lote(s); 59 prueba(s), 59 lote(s). Todos los cambios fueron revertidos.
Temporary single-IP database firewall rule removed.
```

Migraciones ensayadas: 052–059. Smokes001–059 completos, sin saltos ni filtros.
Regresión unitaria final: **1139 aprobadas, cero fallos y cero omitidas**.
`git diff --check` y `bash -n infra/scripts/check-dev-database.sh` correctos.
No se repitió frontend/HTTP: no cambiaron en este seguimiento; último corte1208/421.
No hubo commit/push, apply, deploy, activación de flags o proveedores externos.

## Comprobación posterior independiente

- `--status` terminó con exit0: 51 migraciones registradas, 59 locales;
  **052–059 siguen pendientes**, coherente con rollback. Full-Text existente listo.
- El wrapper de status también retiró su regla temporal.
- Inventario final ARM: únicamente la regla preexistente
  `AllowAzureServicesForDev` (0.0.0.0–0.0.0.0); ninguna regla temporal residual.
  No se cambió ni amplió esa regla preexistente.
- Base `Online` después de probar; SKU `GP_S_Gen5`, mínimo0,5, máximo1 vCore,
  autopausa60 minutos, sin cambios. No se afirma que ya se haya pausado; depende
  de que cese la actividad. No seguir consultando SQL para vigilar la pausa.
- La reparación059 de las dos muestras TEST **continúa pendiente**: incluirla
  en el release autorizado, no ejecutar un UPDATE independiente fuera de él.

## Estado comprobado

- Sesión Azure CLI disponible en la suscripción dev esperada.
- Consulta ARM inicial de solo lectura: `risefunding-dev` estaba **Paused**, SKU
  `GP_S_Gen5`, mínimo 0,5 y máximo 1 vCore, autopausa 60 minutos.
- El usuario autorizó despertar SQL dev y una regla temporal de una sola IP para
  preflight transaccional. No autoriza apply, release ni reparaciones persistentes.
- Mac ARM64; Docker daemon apagado. Según README, emular SQL Server x86-64 en
  este equipo no es un baseline válido. No basta con encender Docker.
- `main` remoto observado: `ca3c28fce2d2c1c61fb9127d804ab40f9994ce7c`.
  El trabajo está en `codex/workspace-backup-2026-09-13`, HEAD `b9f4481`.
  Las migraciones existentes 001–051 son iguales a las de ese main. La rama de
  respaldo contiene otros cambios de adjuntos/workers/infra que no deben publicarse.

Las conexiones generan consumo durante el tiempo activo y hasta la autopausa;
no hay servicios ni capacidad nuevos. Se usa Azure CLI con entorno Staging para
evitar cargar `.env`, sin imprimir secretos ni datos de usuarios.

## Hallazgos durante la ejecución

1. Primer intento: timeout SQL -2 durante reanudación serverless; ARM confirmó
   `Resuming`. Regla temporal retirada. No migraciones ejecutadas en ese intento.
2. SQL053: error 468 de collation en los joins de claves `OPENJSON`. Corrección
   local de la migración aún pendiente: columna y joins con collation binaria
   explícita. Test unitario añadido; los ocho scripts 052–059 compilan en SQL real.
3. Smoke013: error 52311. Diagnóstico agregado de solo lectura encontró **dos**
   identidades discordantes, ambas fondos TEST de matching geográfico y ambas
   hashes UTF-16 en vez de UTF-8. El seed explícito quedó corregido para futuras
   creaciones. Nueva migración059 candidata repara únicamente IDs, slugs, títulos,
   fuente/URL y marcador de esas muestras, con hash heredado y sin colisiones.
   No cambia contenido/publicación, cuentas ni fondos reales. Esta reparación
   también se revierte en preflight; no está aplicada permanentemente.
4. Smoke019: error53907 porque contaba proyectos públicos de toda la base como
   si solo existieran los dos fixtures. Sus tres búsquedas positivas se acotan
   al sufijo único compartido por los fixtures, incluidos los controles privados.
   Mantiene conteos, filtros, paginación y rechazos; no se omite la prueba.
5. Smoke037: error55733 de conteo global de permisos al añadir SQL053/057.
   Se actualizaron los conteos esperados de smoke037 y smoke038 para los cuatro
   procedimientos de traducción (3+1). Smoke027 conserva la allowlist nominal de
   cada EXECUTE; permisos de workers y prohibiciones API/adjuntos no se modifican.
6. Smoke058: error547 por `FundingOpportunities_ArchiveActive`. El escenario
   inactivo ahora pone también `PublicationStatus=4`, conforme al contrato real;
   se corrigió igualmente el fixture de resultados de traducciones. No se altera
   la restricción ni el flujo de publicación.

El wrapper agrega `--check-source-identities`, diagnóstico de conteos, protegido
por el mismo destino exacto/acceso temporal. No escribe ni imprime registros.
Cada intento fallido revirtió su transacción y retiró su propia regla temporal.
El intento final completo pasó y revirtió también la reparación candidata059.

## Comprobación añadida en este bloque

`FundingTranslationSqlVerifier` está integrado en el callback transaccional del
migrador cuando existe SQL058, después de la verificación del mapa. Consume ambos
result sets de Public_List y el de ReadSummaries, sin crear otra conexión ni hacer
commit. El fixture exige una transacción existente y usa solo identidades
sintéticas con dominio `example.invalid`.

Prepara 13 comprobaciones reales: original por defecto, ES/EN, coincidencia en
resumen, exclusión de borrador/versión antigua/inactivo, deduplicación, páginas
primera/segunda/vacía, conteo global, puntuación literal, montos/portada/versiones
canónicas y retirada de revisión/publicación. Los smokes 053–058 siguen cubriendo
edición, SQL de organización/explorador y el resto de campos nuevos.

En la preparación pasaron1132 unitarias; con las correcciones finales pasan1139.
Los 13 checks de contratos de resultado real ya fueron ejecutados y aprobados
dentro del preflight completo. Frontend/HTTP no cambiaron en este seguimiento.

## Procedimiento autorizado

1. Reconfirmar suscripción, tenant, servidor, base y estado/capacidad; no extraer
   secretos ni cargar `.env` local. Usar la identidad ya autenticada de Azure CLI.
2. Ejecutar `bash infra/scripts/check-dev-database.sh --preflight`: valida destino,
   crea regla única de la IP actual, aplica pendientes y ejecuta smokes dentro de
   transacción con rollback y verifica contratos de mapa/traducción. Su trap retira
   exactamente la regla temporal creada, también ante error.
3. Revisar el resultado de los 59 smokes, 23 checks de mapa y 13 de traducciones.
   Si hay error, corregir localmente y repetir; no saltar pruebas ni hacer apply.
   El número de migraciones pendientes debe comprobarse contra SQL, no inferirse.
4. Verificar que no quedó regla `TemporaryMigrationClient-check-*` propia y que
   capacidad/autopausa siguen iguales. No reconsultar SQL periódicamente para
   "vigilar" la pausa, porque esas consultas la mantendrían activa.

SQL052 solo añade AUD al catálogo y preserva valores existentes; no inicia
FundsforNGOs. Resolver y documentar su inclusión en la cadena antes del release.

## Publicación posterior

Solo después del preflight: crear release seleccionado sobre main actualizado,
dejando fuera el observador FundsforNGOs, credenciales, activaciones de adjuntos,
workers e infraestructura. Revisar los cambios compartidos de snapshots/API para
no perder los campos del feedback ni incorporar el importador pausado.

Los scripts actuales exigen un SHA exacto de main limpio y CI verde. No sortear esos
controles con el checkout sucio. Orden: SQL con preflight/apply/reapply/test → API
→ frontend → QA y activación explícita de traducciones. Los flags siguen apagados.
El workflow de frontend todavía no habilita traducciones: no prometer que publicar
el código por sí solo activará ese módulo ni traducirá los fondos existentes.
