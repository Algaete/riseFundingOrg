# Búsqueda unificada — release Azure dev 2026-09-12

## Alcance autorizado

El usuario confirmó expresamente la publicación de los 25 archivos de búsqueda
unificada en el repositorio público `Algaete/riseFundingOrg` y después en Azure dev.
Se usa un worktree separado basado en el catálogo mundial ya desplegado.
No se incluyen mapa avanzado, migración `049`, adjuntos, cambios API/worker ni infraestructura.

La entrega ofrece `/search`, acceso desde la portada y navegación, filtros comunes,
secciones por tipo y paginación. Conserva autorización de directorios, membresía y
visibilidad opt-in. No crea un índice externo ni tareas programadas.

## Revisión y validación

- Base: `1e96564e60b2bb53459bf4254133f7bed05279a7` (países, PR 19).
- Commit de búsqueda: `eb3687367c8c537da962e311a907cc373e3579de`.
- PR: <https://github.com/Algaete/riseFundingOrg/pull/20>.
- Validación local aislada: 1.025 pruebas frontend, 8 pruebas focalizadas de navegador,
  lint, compilación de producción y tipos E2E aprobados. Las APIs E2E son sintéticas.
- CI PR: `34704073551`; validación infraestructura: `34704073518`.

## Estado

Commit, push y PR 20 fusionada. CI PR e infraestructura aprobadas.
Main: `65e7ce51df768e511608bdef6890e7612aa2d173`; árbol Git idéntico al commit probado.
CI adicional de main `34704637888` e infraestructura `34704637866` aprobadas.
El workflow frontend `34704669922` publicó la revisión exacta; `deploy-meta.json`
confirma ese SHA y run, y `/search` devuelve el shell SPA con HTTP 200.
Verificación de despliegue, perfil bajo demanda y suite de navegador sobre Azure
**aprobadas**. Ejecución completa: <https://github.com/Algaete/riseFundingOrg/actions/runs/34704669922>.
Release de búsqueda cerrado en este alcance; no equivale a aceptar todos los requisitos del MVP.
Ruta publicada: <https://salmon-glacier-0721afc0f.7.azurestaticapps.net/search>.
La versión previa era `1e96564e60b2bb53459bf4254133f7bed05279a7`, ejecución `34675762800`.

La publicación usó únicamente `frontend-dev.yml`, con la revisión exacta de main,
confirmación `DEPLOY-DEV-FRONTEND` y verificación `on-demand-imports`. El proceso
comprobó que SQL conserva min 0,5 / max 1 vCore y autopausa 60 min, los temporizadores
siguen deshabilitados y los adjuntos permanecen apagados. No se aumentó capacidad.
Las pruebas de conectividad pueden despertar SQL; esto no significa costo cero.

Lecturas públicas reales posteriores (sin sesión, sin escrituras):

- Proyectos: HTTP 200, contrato paginado válido, cero proyectos publicados al consultar.
- Fondos con `onlyOpen=true`: HTTP 200, contrato válido, un fondo abierto visible.
- Ambas consultas usaron página 1 y tamaño 6, los mismos límites de “Todo” en la búsqueda.

La aceptación privada con cuentas reales es posterior: no se crean usuarios, cambian
roles, envían invitaciones ni publican fondos durante esta entrega.

## Pendientes fuera de esta publicación

- Mapa avanzado: preparación local y migración `049`, pendientes de validación SQL real y despliegue.
- Adjuntos: bloque completo en pausa; no se activa Defender ni otra solución de escaneo.
- El workspace principal conserva los cambios previos y pendientes del usuario. La rama
  de release se verificó limpia, con exactamente 25 archivos respecto a su base; no se
  restauraron ni incluyeron cambios ajenos para forzar un árbol limpio.
- Esta evidencia se conserva localmente; no se enviaron comentarios de infraestructura
  al PR público ni se incorporó este runbook adicional a los 25 archivos autorizados.
