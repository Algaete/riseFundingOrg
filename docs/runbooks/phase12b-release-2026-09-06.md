# Evidencia de release dev — 2026-09-06

## Alcance y código aprobado

Release de API y frontend: `da6d960e1f8a15b03c1c40f3ecf565c6e12805c0`.
La instrumentación y los gates de FASE 12B se fusionaron en el [PR #7](https://github.com/Algaete/riseFundingOrg/pull/7).
El [PR #8](https://github.com/Algaete/riseFundingOrg/pull/8) agregó la publicación acotada de API
y el [PR #9](https://github.com/Algaete/riseFundingOrg/pull/9) preparó Git en el ejecutor temporal.
Los tres se fusionaron después de pasar CI.

El release conserva `Contributor` sólo sobre el Resource Group y los roles existentes de tareas/pull
sobre ACR. No requiere asignaciones nuevas ni permisos a nivel de suscripción. Sus únicas
mutaciones de API son la imagen por digest y las tres variables OTel obligatorias; SQL, identidades,
escala, ingress y Functions quedan fuera de ese cambio.

## Validaciones previas

- Build Release local sin errores ni advertencias; 499 pruebas unitarias aprobadas.
- CI: build/tests .NET, integración, paquetes Functions offline, frontend y E2E público aprobados.
- Validación Bicep y construcción del contenedor aprobadas en CI.
- Pruebas aisladas del release: rechazo de SHA/rama/confirmación/checkout incorrectos, límites de
  identidad/suscripción, cambios concurrentes, mutaciones exactas y preparación de Git.
- La validación PITR de sólo lectura pasó para una base temporal nueva, con almacenamiento máximo
  de 32 GiB y cómputo serverless acotado. No se ejecutó la restauración ni se creó esa base.

## Ejecuciones y estado

- [API — run 34014384048](https://github.com/Algaete/riseFundingOrg/actions/runs/34014384048): aprobado,
  incluyendo preservación de configuración, salud, SQL y catálogo.
- [Frontend — run 34014385588](https://github.com/Algaete/riseFundingOrg/actions/runs/34014385588): aprobado
  en el intento 2, incluyendo metadata, CORS, SPA y E2E público. La primera verificación coincidió con
  la transición de revisión API; al repetir con API estable pasó. La concurrencia ahora se comparte
  con API/infraestructura para evitar esa carrera.
- [Primer intento API](https://github.com/Algaete/riseFundingOrg/actions/runs/34013933373): falló
  durante los prerrequisitos, antes de construir/actualizar. La API conservó su revisión saludable.
  Se corrigió la disponibilidad de Git en el contenedor Azure CLI y se agregó una regresión.

Digest anterior para rollback:
`sha256:8f7f03ea78cf1569b6ec86d0c2d02ac203c8242cecba46beecaa86a10d882ed3`.
Revisión anterior: `ca-rf-dev-ag26rf01-api--xk5s810`; escala previa: mínimo 1, máximo 1.

La primera imagen publicada tiene digest
`sha256:287bf96c46c9e1dae7da1ee6bf8cdfc9c7c46a38521631a3683b99473a356497` y revisión
`ca-rf-dev-ag26rf01-api--0000001`. El smoke observó dos respuestas 500 transitorias antes de pasar
sus reintentos acotados; el canary posterior respondió 400/404 previstos.

La comprobación APM usa únicamente solicitudes anónimas con marcadores sintéticos y trace IDs
controlados. Ambas respuestas 400/404 conservaron los IDs W3C en ProblemDetails y correlación HTTP.
Se confirmó ingesta del request 400 y su log, sin marcadores de query exportados. La segunda traza
no quedó en la muestra; los siguientes canaries separan solicitudes bajo el muestreo de 1/s.

El primer canary detectó `AppRoleName=ca-rf-dev-ag26rf01-api`, porque el detector Azure prevalece
sobre el nombre de servicio de entorno. El código fija ahora la identidad de recurso de API después
de registrar el distro, conservando el ID de instancia; requiere volver a verificar ingesta como
`FundingPlatform.Api` antes de aprobar este gate o activar las alertas que filtran ese nombre.

## Gates que este release no cierra

La auditoría de sólo lectura a las `05:47:45 UTC` confirmó las tres asignaciones OIDC acotadas,
cero roles a nivel de suscripción/ancestros, cero Functions publicadas en ambos hosts, las 14+2
barreras exactas en `true`, SCM/FTP basic auth cerrado y cero recursos de alertas operacionales.

- Dominio común para `app`/`api` y cuenta técnica protegida antes del E2E autenticado remoto.
- Configuración y canary del pipeline independiente del host de Functions; no se publican ZIPs
  ni se habilita ninguno de los 16 triggers.
- Restore PITR real a una base temporal y verificación de la restauración.
- Activación, prueba de entrega y acuse de alertas operacionales.
- Correo, SSO, Defender/Event Grid y demás integraciones continúan bajo sus gates específicos.

Esta evidencia no constituye aprobación para un piloto pagado ni para producción.
