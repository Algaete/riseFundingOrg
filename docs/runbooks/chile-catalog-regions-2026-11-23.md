# Cobertura regional de FAE y MAPFRE — 23 de noviembre de 2026

La aceptación pública del lote de 16 encontró que FAE y MAPFRE aparecían al buscar por Chile, pero se excluían al seleccionar una región. Las dos fichas tenían país 152 y ninguna región registrada; el buscador exige cobertura regional explícita para fichas que no son globales. Las fuentes revisadas admiten postulaciones chilenas sin restricción subnacional.

La corrección registra las 16 regiones de Chile únicamente para estas dos fichas. No modifica la lógica del buscador ni convierte datos territoriales desconocidos de otras fichas en cobertura nacional. GEF conserva exclusivamente Atacama, Ñuble y Los Ríos. El catálogo sigue con 45 fichas y 40 abiertas o continuas al 23-11; la meta de 50–60 abiertas permanece pendiente.

El lote inicial `chile-catalog-next-2026-11-23` es inmutable. El lote `chile-catalog-regions-2026-11-23` exige versión 1, país Chile y ausencia previa de regiones en los dos IDs exactos; crea versión 2, evidencia y evento editorial, preservando el contenido y la versión original. No cambia fuentes, financiadores, montos, plazos, requisitos ni perfiles de usuarios.

## Verificación

`--verify-regions-local` reproduce primero la exclusión de ambas fichas en Atacama. Después comprueba que las dos aparecen en cada una de las 16 regiones usando el procedimiento real del buscador, y que GEF sigue limitado a sus tres regiones. Compara las otras 43 fichas y sus versiones, el contenido original y la versión 1 de los dos objetivos; verifica repetición sin cambios y rechazo de replay alterado. Todo se revierte en la base descartable `res` de `127.0.0.1,14363`.

## Publicación

1. Compilar el publicador, aprobar la prueba local y CI del PR y de main.
2. Ejecutar `bash infra/scripts/curate-pilot-dev.sh --preview-regions` con reversión.
3. Publicar con `RF_CATALOG_REGIONS_CONFIRMATION=CONFIRM-FAE-AND-MAPFRE-ALL-SIXTEEN-CHILE-REGIONS-20261123` y `--apply-regions`. Repetir: debe reportar cero cambios y dos revisiones ya aplicadas.
4. Repetir la aceptación pública del lote: 45 fichas, 40 abiertas, versiones 2 solo en FAE/MAPFRE, cobertura de las dos en las 16 regiones, GEF sin ampliación, filtros de tipo y salud, y cuatro páginas sin duplicados.
5. Comprobar retiro del acceso SQL temporal. No requiere migraciones, despliegues de API/frontend ni cambios de capacidad.

Evidencias en `artifacts/expand-20261123/`. La revisión visual del lote permanece separada de las pruebas de datos y CI: no se considera aprobada mientras Chrome siga inaccesible.
