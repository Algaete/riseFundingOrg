# Evidencia de release dev — 2026-09-06

## Alcance y código aprobado

Release final de API y frontend: `0e8d816b686beec5d7259150b9d484bc1a0c87c2`.
La instrumentación y los gates de FASE 12B se fusionaron en el [PR #7](https://github.com/Algaete/riseFundingOrg/pull/7).
El [PR #8](https://github.com/Algaete/riseFundingOrg/pull/8) agregó la publicación acotada de API
y el [PR #9](https://github.com/Algaete/riseFundingOrg/pull/9) preparó Git en el ejecutor temporal.
El [PR #10](https://github.com/Algaete/riseFundingOrg/pull/10) corrigió la identidad APM con evidencia
real y serializó los releases de frontend/API. Todos se fusionaron después de pasar CI.

El release conserva `Contributor` sólo sobre el Resource Group y los roles existentes de tareas/pull
sobre ACR. No requiere asignaciones nuevas ni permisos a nivel de suscripción. Sus únicas
mutaciones de API son la imagen por digest y las tres variables OTel obligatorias; SQL, identidades,
escala, ingress y Functions quedan fuera de ese cambio.

## Validaciones previas

- Build Release local sin errores ni advertencias; 501 pruebas unitarias y 178 de integración aprobadas.
- CI: build/tests .NET, integración, paquetes Functions offline, frontend y E2E público aprobados.
- Validación Bicep y construcción del contenedor aprobadas en CI.
- Pruebas aisladas del release: rechazo de SHA/rama/confirmación/checkout incorrectos, límites de
  identidad/suscripción, cambios concurrentes, mutaciones exactas y preparación de Git.
- La validación PITR de sólo lectura pasó para una base temporal nueva, con almacenamiento máximo
  de 32 GiB y cómputo serverless acotado. No se ejecutó la restauración ni se creó esa base.

## Ejecuciones y estado

El release final de API pasó en el
[run 34015067993](https://github.com/Algaete/riseFundingOrg/actions/runs/34015067993), conservando
configuración y escala 1/1, con salud, SQL y catálogo aprobados. Imagen por digest:
`sha256:ef3fdd8e186d86a686662adf7340fdff486aa33ce85022a31f1303978d294ee6`.
Revisión preparada: `ca-rf-dev-ag26rf01-api--0000002`.

El frontend del mismo SHA pasó en el primer intento del
[run 34015108191](https://github.com/Algaete/riseFundingOrg/actions/runs/34015108191): metadata,
raíz/fallback SPA, headers, CORS y E2E público de navegador aprobados. Esperó a que terminara la
API mediante la concurrencia compartida.

El canary final a las `05:57 UTC` confirmó:

- Dos `AppRequests`: 400 y 404, con plantillas de ruta, `AppRoleName=FundingPlatform.Api` y los
  trace IDs W3C esperados tanto en ProblemDetails como en la correlación HTTP.
- Dos `AppTraces` y una dependencia SQL correlacionada con el mismo nombre de servicio.
- Cero marcadores de query/slug exportados, cero campos de query/HTTP target y cero texto SQL
  en atributos o datos de la dependencia, mediante consultas agregadas acotadas al canary.

La identidad APM y la privacidad de estas solicitudes de API quedaron verificadas. Esto no prueba
excepciones ni el pipeline independiente del host de Functions.

## Historial de los intentos previos

El primer release conjunto fue `da6d960e1f8a15b03c1c40f3ecf565c6e12805c0`:

- [API — run 34014384048](https://github.com/Algaete/riseFundingOrg/actions/runs/34014384048): aprobado,
  incluyendo preservación de configuración, salud, SQL y catálogo.
- [Frontend — run 34014385588](https://github.com/Algaete/riseFundingOrg/actions/runs/34014385588): aprobado
  en el intento 2, incluyendo metadata, CORS, SPA y E2E público. La primera verificación coincidió con
  la transición de revisión API; al repetir con API estable pasó. La concurrencia ahora se comparte
  con API/infraestructura para evitar esa carrera.
- [Primer intento API](https://github.com/Algaete/riseFundingOrg/actions/runs/34013933373): falló
  durante los prerrequisitos, antes de construir/actualizar. La API conservó su revisión saludable.
  Se corrigió la disponibilidad de Git en el contenedor Azure CLI y se agregó una regresión.

Digest anterior al inicio de esta ventana:
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
de registrar el distro, conservando el ID de instancia. El canary final descrito arriba verificó
la corrección; las alertas todavía no se activaron.

Para volver al release inmediatamente anterior al ajuste de identidad, el workflow final registró
el digest `sha256:287bf96c46c9e1dae7da1ee6bf8cdfc9c7c46a38521631a3683b99473a356497` y la revisión
`ca-rf-dev-ag26rf01-api--0000001`. Usar el rollback gobernado y repetir el smoke.

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
