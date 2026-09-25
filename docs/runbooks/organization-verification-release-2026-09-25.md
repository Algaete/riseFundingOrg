# Verificación de organizaciones y edición ES/EN — release dev

Autorización: «continua con punto 1,2 y4» (25-09-2026): validación SQL,
GitHub/Azure dev y avance de traducciones. No autoriza IA de pago, adjuntos,
antivirus, nuevas capacidades o recursos. Repo público `Algaete/riseFundingOrg`.

Estado de esta revisión: preparación, sin afirmar publicación completada.
Base de release: main`e546c2cac6c0831c65d81fb62c00cab036a2ac83`, SQL062,
APIrevisión0000012. Checkout aislado; importador y otros cambios excluidos.

## Alcance

- SQL063/verificación privada pendiente, verificada, rechazada; razón, confirmación,
  historial, atribución y control de concurrencia. No modifica permisos de negocio.
- Corrección del historial SQL vacío a`[]`; normalización defensiva del cliente.
- Edición manual ES/EN activable por separado de generación IA; opción explícita
  en el workflow frontend que exige API ya activada. IA permanece OFF.
- Generador preparado fija tarifa estándar`service_tier:default`; piloto deUSD5/mes
  solo propuesto, no aprobado ni ejecutado. Ver`translation-pilot-2026-09-25.md`.

## Validación local real

SQL Server2025 Developer, contenedor efímero, solo localhost14363, sin datos reales.
Imagen oficial digest`sha256:2b5b581621126574f3d1f75e78d3eebe8d05aedb59ad0cfdf9aa42cb0634d726`.
Baseline001–062 aplicado intacto; preflight063:1migración y63smokes revertidos;
apply063:1; reapply:0;63smokes finales aprobados.21comprobaciones multiconexión
y permisos efectivos aprobadas; fixtures y usuarios sintéticos retirados.

Incidencias resueltas durante validación: SQL2022 no soportaVECTOR histórico;
se usó2025. Un preflight de toda la cadena desde vacío sufrió deadlock1205;
se reprodujo el baseline062 existente aplicando001–062 sin cambios y se probó
la nueva063 encima. El primer smoke063 detectóhistorialNULL y se corrigió a`[]`.
No se omitieron pruebas ni se modificaron migraciones históricas.

Checkout aislado:1.150unitarias.NET,487HTTP,1.263frontend/98archivos aprobados.
8E2E de verificación +2E2E de traducción manual a320/1280px; lint/build/tipos,
accesibilidad y capturas revisadas. Estas pruebas no son aceptación de cuentas reales.

## Orden de publicación y controles

1. Preflight Azure con rollback, regla temporal exacta deIP y limpieza garantizada.
2. Commit/PR, CI e infraestructura correctos; main exacto y checkout limpio.
3. Wrapper SQL`--release`: preflight, apply, reapply0, smokes/mapa/traducciones.
4. Workflow API conSHA exacto. Conservarréplicas1–1 ySQLmin0,5/max1/autopausa60.
5. Habilitar únicamente edición manual API; generación IA explícitamentefalse.
6. Frontend con`editorial_translations=true`; verificar metadataSHA y navegación.

Primer intento de preflight Azure agotó timeout de conexión (-2), retirando su
regla temporal. Segundo intento aprobado: 1 migración, 5 lotes, 63 smokes,
23 comprobaciones de mapa y 13 de traducciones; rollback total y regla retirada.
Todavía no se ha aplicado SQL063 permanentemente en Azure.

La comprobación adicional del navegador con traducciones activadas detectó
16 tests antiguos cuyos mocks/contadores solo admitían lecturas sin `locale`.
Se ajustan los recursos exactos y se comprueba que cambiar ES→EN causa solo
la nueva lectura esperada, preservando filtros y página. No se omiten tests,
no se amplían permisos y no se cambian las reglas de negocio. CI público pasa
a probar la configuración activada que se publicará; se prueba también OFF.
RegistrarSHA, workflows, revisión/digest y resultadoSQL antes de dar por terminado.

## Pendientes que esta autorización no resuelve

No hay autorización monetaria/modelo/clave/retención para generación IA: sigueOFF.
No afirmar catálogo íntegramente traducido ni revisión editorial automática.
Falta aceptación con cuentas reales y política del dueño sobre pendientes/rechazadas.
Adjuntos/AV, búsqueda abierta continua y otras decisiones de producto no cambian.
