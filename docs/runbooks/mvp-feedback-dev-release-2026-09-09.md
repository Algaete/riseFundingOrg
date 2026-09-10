# Release del feedback MVP en Azure dev — 2026-09-09

## Resultado y autorización

El usuario autorizó explícitamente fusionar la PR #13 en main y desplegar Azure dev,
manteniendo los adjuntos deshabilitados hasta validar Defender. Se completó el release
de base de datos, worker general, API y frontend, en ese orden. Sin producción ni cambios
de cuentas, servicios de pago, fuentes restringidas o privilegios permanentes nuevos.

- [PR #13](https://github.com/Algaete/riseFundingOrg/pull/13): fusionada.
- Commit desplegado: `4db49d40d8d950ce640e03caa7882ae87b19edb5`.
- [CI de main](https://github.com/Algaete/riseFundingOrg/actions/runs/34364239752): aprobado.
- [Infraestructura](https://github.com/Algaete/riseFundingOrg/actions/runs/34364239713): aprobada.
- [API](https://github.com/Algaete/riseFundingOrg/actions/runs/34366217623): release y verificación aprobados.
- [Frontend](https://github.com/Algaete/riseFundingOrg/actions/runs/34367321191): release y 186 pruebas de navegador aprobados.
- Sitio: https://salmon-glacier-0721afc0f.7.azurestaticapps.net

El desarrollo local validó 887 pruebas unitarias .NET, 298 HTTP, 937 frontend y 185 de
navegador (solo el SHA de Azure se omitió en local). CI volvió a aprobar sobre el commit
fusionado. En Azure pasaron las 186 pruebas de navegador en 8,2 minutos, incluido el SHA
servido por `deploy-meta.json` y el identificador del workflow `34367321191`.

## Base de datos

Destino exacto: `risefunding-dev`, servidor `sql-rf-dev-ag26rf01-centralus`, grupo
`rg-rf-dev-ag26rf01`. Antes de modificar se confirmó PITR de siete días y una ventana de
restauración existente. `check-dev-database.sh --release` verificó checkout limpio, SHA
actual de main, CI aprobado, tenant, suscripción y destino.

1. Preflight: 16 migraciones (`031`–`046`), 144 lotes y 46 smokes, todo revertido.
2. Aplicación definitiva: 16 migraciones, 144 lotes.
3. Segunda aplicación: cero migraciones y cero lotes pendientes.
4. Pruebas posteriores: 46 smokes aprobados; solo sus fixtures se revirtieron.
5. Regla temporal de una sola IP eliminada al terminar.

La base conserva aplicadas las 46 migraciones. No se ejecutó bootstrap de usuarios ni
se trataron fixtures de escaneo como evidencia de Defender real.

## Worker general

Paquetes del artefacto CI `10109321988`, con revisión, manifiestos, inventario y hashes
comprobados independientemente antes del despliegue:

- SHA-256 del artefacto exterior:
  `f3899575fad87d7ddd3d5a3c1ef0b21bc2ce03f82d7f02b6fc89fc96aceecbd4`.
- SHA-256 de `general-workers.zip`:
  `877562591fd2269909ecea19e20f21b48d693f23f1a469c4db2d78200fe57980`.

Publicación ZIP con AAD en `func-rf-dev-ag26rf01-general`, sin habilitar autenticación
básica ni crear permisos nuevos. Se confirmó el inventario de 17 funciones: activas
únicamente `ImportSchedulerFunction`, `ImportOutboxDispatcherFunction` e
`ImportQueueFunction`; las otras 14 deshabilitadas. Los tres nuevos triggers de adjuntos
se deshabilitaron antes de publicar su código y `PROJECT_ASSETS_ENABLED=false`.
El worker de extracción no se publicó ni habilitó.

## API, frontend y comprobaciones reales

API lista en la revisión `ca-rf-dev-ag26rf01-api--0000003`, imagen fijada al digest:
`crrfdevag26rf01wz3m6hb7mucby.azurecr.io/rise-funding-api@sha256:801f7ace0f43439fac00ed0cf4ecd4997200fb14b6b4d33ddf7927f5dd36bf3c`.
El workflow conservó la configuración fuera de imagen y las tres variables de telemetría
autorizadas. API y frontend aprobaron el perfil explícito `imports-only` del verificador.

- Salud, explorador de fondos, catálogos, mapa y búsqueda anterior: HTTP 200.
- Profesionales, perfil profesional privado y matching sin sesión: HTTP 401.
- `/funding/explore`, `/marketplace/map` y `/matching/ecosystem`: shell SPA correcto.
- CORS admite el origen dev exacto y no concede acceso al origen de prueba no confiable.
- Paginación inválida del explorador: HTTP 400 con contrato de validación por campo.
- Catálogo público y mapa devolvieron `totalCount=0`; no se publicaron borradores.

## Límites y recuperación

Adjuntos (imágenes, PDF, MP4 y TXT) siguen deshabilitados. Su activación requiere evidencia
real de almacenamiento, permisos y Defender según `project-assets-rollout.md`. No se
habilitaron SSO, correo, nuevas fuentes restringidas ni otros jobs. No se consultaron
contraseñas ni se modificaron cuentas reales. Las pantallas autenticadas en las pruebas
públicas usan respuestas sintéticas: no equivalen a un recorrido real con un usuario.

La imagen anterior de API queda identificada para un rollback acotado:
`crrfdevag26rf01wz3m6hb7mucby.azurecr.io/rise-funding-api@sha256:ef3fdd8e186d86a686662adf7340fdff486aa33ce85022a31f1303978d294ee6`.
Revisión anterior: `ca-rf-dev-ag26rf01-api--0000002`. SHA frontend anterior:
`0e8d816b686beec5d7259150b9d484bc1a0c87c2`. No se ejecutó rollback ni se promete que
cualquier código anterior sea compatible con las migraciones nuevas: debe comprobarse
antes de revertir componentes. Las migraciones son forward-only; no ejecutar down/reset.
