# Matching geográfico: muestra explícita de desarrollo

La muestra **no es una migración** ni se ejecuta al iniciar API/workers. Solo se permite
en `sql-rf-dev-ag26rf01-centralus.database.windows.net/risefunding-dev`, por una cuenta
existente, activa, confirmada y habilitada para administración. No crea identidades,
no cambia roles globales, contraseñas o MFA y no envía notificaciones.

Todos los registros llevan `TEST · DATOS DE PRUEBA ·` en el nombre/título y un aviso
de ficción en su descripción. No son convocatorias reales y no aceptan postulaciones.
La fuente es manual, sin proveedor programable, cron ni secretos. No requiere servicios
nuevos, llamadas de IA, cambios de SKU ni procesos periódicos.

## Registros y resultado esperado

- Organización TEST de Chile, privada en networking, con un proyecto borrador privado.
- Cinco organizaciones aliadas TEST (Francia, España, Alemania, Reino Unido y EE. UU.),
  visibles en el directorio, pero sin aceptar solicitudes de contacto.
- Un financiador ficticio y dos fondos TEST publicados: socio UE / socio Europa M49.
- La cuenta indicada es propietaria únicamente de estas organizaciones nuevas; sus
  organizaciones reales no se editan. El matching permite seleccionarlas o abrirlas
  por `organizationId` comprobado contra las membresías devueltas por la API.
- Las fechas de perfil de las organizaciones TEST son deliberadamente sintéticas y
  anteriores a las membresías existentes para no sustituir la organización predeterminada
  en otras pantallas. Las versiones y membresías registran el instante real de creación.
- UE devuelve Francia, España y Alemania; excluye Reino Unido y EE. UU.
- Europa devuelve Reino Unido y dos de los anteriores; excluye EE. UU. El aliado del
  Reino Unido comparte dos áreas de impacto para aparecer entre las tres sugerencias.
- Un cálculo real y versionado del motor determinístico incluye ambos fondos TEST
  compatibles. No se insertan puntajes inventados. «Buscar apoyos para este fondo»
  carga las recomendaciones exclusivamente bajo demanda.

El directorio y el ranking son reales: si otros candidatos o ediciones posteriores
cambian el resultado, la verificación falla en lugar de forzar resultados o borrar datos.

## Operación

Aplicar primero las migraciones 050/051 y desplegar API/frontend del mismo release.
Usar acceso SQL autorizado y acotado; si se requiere firewall temporal, usar una sola
IP pública y retirarlo en un `trap` al terminar. Nunca abrir el rango completo.

Con las variables habituales de conexión Entra, destino esperado y
`RF_DEV_SAMPLE_OWNER_EMAIL` (correo proporcionado en tiempo de ejecución):

```sh
dotnet run --project tools/FundingPlatform.AdminCli -- dev-geographic-sample --preview
RF_DEV_SAMPLE_CONFIRMATION=WRITE-DEV-TEST-DATA dotnet run --project tools/FundingPlatform.AdminCli -- dev-geographic-sample --apply
dotnet run --project tools/FundingPlatform.AdminCli -- dev-geographic-sample --verify
```

`--preview` valida el SQL, las sugerencias de la aplicación y un cálculo real dentro
de una transacción que se revierte. `--apply` repite esas comprobaciones antes del commit.
Una segunda aplicación reutiliza los IDs y la clave idempotente del cálculo; no crea
duplicados ni restablece ediciones. Un conjunto incompleto, renombrado o de otro dueño
se rechaza. `--verify` no crea cálculos ni persiste cambios.

La salida de apply/verify imprime el enlace privado exacto de matching, sin credenciales.
La guía pública está en `/test-data/matching-geografico.html` y contiene un enlace
con organización y proyecto explícitos (solo accesible por sus miembros).

## Retiro recuperable

```sh
RF_DEV_SAMPLE_CONFIRMATION=WRITE-DEV-TEST-DATA dotnet run --project tools/FundingPlatform.AdminCli -- dev-geographic-sample --disable
```

Desactiva exclusivamente los seis IDs de organización, un proyecto, dos fondos, un
financiador y la fuente exacta de la muestra, verificando antes etiquetas y propietario.
No elimina filas, membresías, revisiones ni el historial de matching. No reactiva nada
automáticamente en aplicaciones posteriores. La reactivación requiere revisión explícita.
