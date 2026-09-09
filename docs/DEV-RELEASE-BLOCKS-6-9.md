# Release dev: bloques 6–9

En curso. No confundir los commits locales con una versión publicada.

## Destino y recuperación

- Repositorio: `Algaete/riseFundingOrg`; release desde `main` con CI aprobado.
- Grupo: `rg-rf-dev-ag26rf01`; Azure SQL: `sql-rf-dev-ag26rf01-centralus/risefunding-dev`.
- Preflight real iniciado desde 30 migraciones aplicadas; cadena local 001–046.
- Recuperación PITR de siete días verificada. Cada preflight revierte todos sus cambios
  y elimina su propia regla de firewall de una sola IP; no modifica cuentas.

## Correcciones encontradas contra SQL real

Se corrigieron migraciones aún **no aplicadas** en dev: límites de compilación después de
agregar columnas (`033`, `037`, `038`), restricciones con nombre explícito (`039`, `042`,
`043`, `045`), serialización de rowversion (`043`, `045`) y reconstrucción del encabezado
de procedimientos que Azure conserva con espacios (`046`). `001`–`030` no se modificaron.

Los smokes históricos se adaptan a los resultados ampliados, manifiestos de `038` y
delegación real de auditoría. La verificación de backfill `010` sólo incluye filas que
no hayan cambiado desde esa migración; los borradores importados posteriores siguen
sujetos al flujo editorial, no se publican ni completan artificialmente para pasar un test.

## Orden de publicación

1. Completar preflight SQL 001–046 y suites locales; subir la rama y validar CI en PR.
2. Integrar el commit revisado en `main`, esperar CI del SHA exacto.
3. Desde checkout limpio de ese SHA ejecutar `infra/scripts/check-dev-database.sh --release`
   con `RF_DEV_RELEASE_SHA` y `RF_DEV_DATABASE_CONFIRMATION=DEPLOY-DEV-DATABASE`.
   El wrapper valida destino, CI, recuperación, preflight, apply idempotente y smokes.
4. Ejecutar el release existente de API por SHA/digest; publicar paquetes verificados del
   worker manteniendo las restricciones de triggers y después el frontend del mismo SHA.
5. Verificar API, catálogo, rutas nuevas y metadatos de revisión del sitio publicado.

`--release` no es el bootstrap `prepare-database-dev.sh`: no solicita ni configura contraseñas,
SuperAdmin, identidades adicionales, Full-Text o servicios de pago. Si algún paso falla, detener
la publicación y conservar la evidencia; no forzar history/checksums ni restaurar datos a ciegas.

## Activaciones separadas

Mantener adjuntos, Defender, envíos de correo, SSO y proveedores externos no autorizados con
sus flags actuales. MP4/TXT está desarrollado, pero su activación en Azure requiere el
runbook de adjuntos y scan real. No presentar recibos sintéticos como prueba de Defender.
