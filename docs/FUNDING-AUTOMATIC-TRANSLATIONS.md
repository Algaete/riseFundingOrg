# Traducción automática de fondos — propuestas bajo demanda

Estado al 22-09-2026: **implementación local, apagada, no desplegada**.
Extiende la traducción editorial ES/EN de SQL053/057/058. Nueva migración: SQL060.
No se leyeron credenciales reales ni se hicieron llamadas a OpenAI, cambios en Azure
o activaciones de flags durante este desarrollo.

## Flujo

1. Administrador con MFA abre un fondo → Traducciones → elige ES o EN.
2. Si el proveedor y los límites están autorizados, aparece **Generar propuesta automática**.
3. Tras confirmar, la API lee los once campos canónicos y comprueba versión/ETag.
4. SQL reserva de forma atómica el máximo presupuestado para la llamada. Una
   combinación fondo + versión de contenido + idioma admite un único intento.
5. OpenAI devuelve los once textos con esquema estricto; se valida integridad,
   cobertura, longitudes, estado completo y uso de tokens. No se acepta un rechazo,
   respuesta parcial, campos extra, texto faltante ni cambio de modelo.
6. La propuesta se conserva en una tabla separada y se carga en el editor. No
   cambia el fondo, una traducción revisada existente ni su publicación.
7. El administrador revisa todos los campos y usa el guardado editorial existente.
   Solo **Guardar traducción revisada**, con confirmación explícita, permite su
   uso en el catálogo/detalle en el idioma elegido por la persona.

Un nuevo clic o una reconexión reutiliza la propuesta persistida sin pagar otra
llamada. Los cambios sin guardar bloquean generación/cambio de idioma. Durante
la llamada no se pueden editar ni guardar los campos. Si la respuesta falla,
el contenido anterior se conserva. La UI también rechaza respuestas nulas,
incompletas o de otro idioma/versión.

La propuesta no es un `FundingTranslation` y no tiene `Reviewed=true`. Solo
`FundingTranslation_Save` mantiene el flujo editorial existente y sus controles
de concurrencia. El público no llama al generador. No hay timer ni worker nuevo.

## Integración y límites

El adaptador usa Responses API con `text.format`/`json_schema`, `strict: true`,
once propiedades requeridas y anulables, `additionalProperties: false` y
`store: false`, siguiendo la [documentación oficial de salidas estructuradas](https://developers.openai.com/api/docs/guides/structured-outputs).
No habilita herramientas, navegación, ejecución de instrucciones de la fuente ni
traducción por visita. El texto es contenido no confiable, no instrucciones; la
revisión humana sigue siendo obligatoria.

Se reutiliza la validación de orígenes oficiales de OpenAI. El adaptador de
explicaciones de matching NO se reutiliza para traducir: su propósito, modelo,
esquema, autorizaciones y límites son diferentes. Los flags de semántica no cambian.
Este propósito usa su propia clave y aprobación con vencimiento.

`store: false` no garantiza por sí solo retención cero por parte del proveedor.
Antes de activar, verificar condiciones del proyecto/API, procesamiento externo,
residencia y retención para los textos que se enviarán. No se envían IDs internos,
credenciales, objetos de usuario, montos/fechas estructurados ni adjuntos; solo los
once campos de texto (que sí pueden contener nombres o contactos de una convocatoria).

Configuración en `.env.example` bajo `FundingTranslations__Generation__`:

- `Enabled=false`, `ExternalProcessingApproved=false`; vencimiento sin establecer.
- `ApiKey` solo servidor; nunca `VITE_`, Git ni logs. `EndpointOrigin` debe ser
  un origen HTTPS oficial permitido; sin redirecciones ni cookies.
- `Model` sin predeterminado: elegir y probar un identificador estable compatible
  con salidas estructuradas. La respuesta debe declarar ese mismo modelo.
- Tarifas de entrada/salida por millón, costo máximo por solicitud, presupuesto
  mensual y límite de solicitudes: **cero por defecto, por lo tanto inoperante**.
- Entrada: hasta 24.000 bytes JSON UTF-8 por defecto, nunca truncada. Límite
  configurable hasta 64.000. Salida: 8.192 tokens por defecto, máximo 16.384.
- Tiempo: 60 s por defecto, configurable 10–120 s. Respuesta HTTP: máximo 256 KiB.

La aprobación solo es válida si todos los límites son coherentes. El máximo por
solicitud debe cubrir conservadoramente:

`((MaximumInputBytes + 16384) * tarifaEntrada + MaximumOutputTokens * tarifaSalida) / 1000000`

El presupuesto se controla por mes UTC, con `sp_getapplock` y registros
persistentes, compartidos entre instancias, administradores, fondos e idiomas.
Topes técnicos: USD 1 por intento, USD 100/mes y 1.000 solicitudes/mes; **son
techos de configuración, no presupuesto activado ni recomendación de gasto**.
Los importes de reserva/presupuesto admiten hasta seis decimales.

Cada intento consume la reserva máxima, incluso ante fallo o cancelación. No se
libera automáticamente: pudo haberse producido un cargo aunque la respuesta no
llegara. Se registran modelo, versión de prompt, actor, tiempos, tokens y reserva.
No se almacenan errores/payloads del proveedor ni la clave.

Este es un límite conservador de la aplicación calculado con las tarifas
configuradas, no un límite de facturación de toda la cuenta del proveedor. Verificar
tarifas antes de autorizar; el presupuesto no cubre otros usos de la misma cuenta.

## Fallos y recuperación

- 428/412: falta ETag o cambió el fondo; no se inicia una llamada nueva.
- 429: presupuesto/cantidad alcanzada o bloqueo de reserva temporalmente ocupado;
  no se inició llamada nueva. Una propuesta ya completada se reutiliza sin reserva.
- 409: ya hay un intento en curso o fallido para esa versión/idioma. No se reintenta.
- 422: entrada demasiado extensa/inválida; no se envía ni recorta.
- 502/504: no se confirmó una respuesta válida o hubo timeout. Se conserva la
  reserva; el administrador puede continuar manualmente.
- 503: proveedor, aprobación o flags no disponibles.

Un cierre abrupto del proceso puede dejar el intento `processing`: se bloquea
repetirlo hasta investigar. Este bloque NO implementa recuperación/reintento de
intentos inciertos. No borrar registros para liberar presupuesto. La traducción
manual sigue disponible. Una nueva versión real del fondo tiene otro identificador
lógico de generación; no editar el fondo artificialmente para eludir este control.

## Verificación y puesta en marcha pendiente

Pruebas sin proveedor real: contrato del adaptador, respuestas incompletas/nulas,
esquema/uso incorrecto, URLs no permitidas, no reintentos, permisos/MFA,
presupuesto, concurrencia de versión y borrador sin publicación; pruebas del editor.
SQL060 y smoke060 pasan el parser T-SQL; smoke027 y los conteos037/038 incluyen
exactamente dos permisos EXECUTE nuevos solo para la API, sin permiso de tablas.

Regresión local completa: **1.165 unitarias .NET, 430 pruebas HTTP y 1.221 pruebas
frontend (97 archivos), todas aprobadas, sin omisiones**. Compilación API/frontend,
lint y tipos E2E correctos. No se ejecutó un navegador E2E nuevo ni se probó calidad
con un modelo real. El primer intento de runner .NET falló por permisos de sockets;
se detuvo ese proceso y se repitió autorizado. La primera suite completa detectó
el manifiesto estático sin SQL060: se añadieron exactamente los dos procedimientos
y el conteo esperado pasó de 40 a 42; no se relajaron controles ni omitieron pruebas.

**Pendiente antes de activar:**

1. Preflight SQL real (incluidos presupuesto, concurrencia y rollback), apply,
   reaplicación idempotente y smokes. Docker no está iniciado localmente; no se
   ejecutó SQL060 contra SQL Server ni Azure en este desarrollo.
2. Acordar modelo, clave del proyecto, condiciones de procesamiento, tarifas,
   presupuesto mensual, límite de solicitudes y vencimiento de aprobación.
3. Desplegar API/frontend y activar los flags de traducciones y generación solo
   en el entorno autorizado. No cambiar capacidad ni la autopausa de SQL.
4. Probar una convocatoria con el proveedor real y revisar fidelidad ES/EN;
   aprobarla y comprobar la alternancia de idioma pública. Las pruebas simuladas
   validan el contrato, no la calidad de una traducción de un modelo real.
5. Cargar/revisar traducciones iniciales. Traducción masiva, planificación automática,
   idiomas adicionales y recuperación asistida de fallos no forman parte de este bloque.

No presentar este desarrollo local como traducción automática activa en Azure.
