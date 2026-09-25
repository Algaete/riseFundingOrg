# ES/EN: edición disponible y propuesta de piloto IA

Actualizado: 25-09-2026. La autorización de publicación no autoriza nuevos gastos.

## Dos funciones independientes

- Edición editorial: `FundingTranslations__Enabled=true` en API y
  `VITE_FUNDING_TRANSLATIONS_ENABLED=true` al compilar el frontend. Permite
  cargar ES/EN, revisar y guardar traducciones; no llama a un proveedor de IA.
- Generación IA: permanece **OFF**. No hay clave/modelo/presupuesto autorizados.
  Solo propone textos a petición del administrador; nunca publica automáticamente.

SQL053/057/058/060 ya están en el último release anterior. No reaplicar ni cambiar
sus scripts históricos. La nueva opción manual `editorial_translations` del
workflow frontend selecciona el flag de compilación; predeterminado `false`.
Al repetir un release con la edición activada, seleccionar explícitamente `true`.
Activar primero la API, publicar después el frontend y verificar ambos idiomas.
Desactivación: frontend con la opción `false`, después API editorial en `false`;
las traducciones guardadas no se borran.

Sin traducción revisada para la versión actual se muestra el original y su aviso.
Activar edición no traduce retroactivamente todo el catálogo. Un borrador no es
visible al público; una modificación del original invalida la traducción anterior.

## Propuesta acotada, todavía NO autorizada ni aplicada

Modelo candidato: `gpt-4.1-mini-2025-04-14`, snapshot con Responses y salidas
estructuradas según la [ficha oficial](https://developers.openai.com/api/docs/models/gpt-4.1-mini).
Tarifas estándar consultadas el 25-09: USD 0,40/millón de tokens de entrada y
USD 1,60/millón de salida, sin asumir descuento de caché o Batch.
[Precios oficiales](https://developers.openai.com/api/docs/pricing).

Proponer al dueño: **USD 5 por mes UTC**, máximo **150 intentos/mes**, reserva
máxima **USD 0,03/intento**, aprobación de procesamiento externo por **30 días**.
Solo texto de convocatorias, no perfiles privados, archivos ni credenciales.
Antes de habilitar, verificar acceso al modelo y condiciones/retención del proyecto;
`store:false` no equivale a retención cero.

Con 24.000 bytes de entrada +16.384 de margen y 8.192 tokens de salida:
`((24000 + 16384) × 0.40 + 8192 × 1.60) / 1000000 = 0.0292608 USD`.
Una reserva de 0,03 cubre ese límite conservador. 150 reservas suman USD 4,50.
Es un control de esta aplicación con tarifas configuradas, no un límite de toda
la cuenta OpenAI, impuestos u otros consumos. Cambios de tarifa requieren revisión.

El adaptador fija `service_tier:default` para no heredar procesamiento prioritario
desde ajustes de cuenta. [Referencia de Responses](https://developers.openai.com/api/reference/cli/resources/responses/methods/create).
No hay llamada al proveedor durante estas pruebas ni por leer una convocatoria.

## Prueba de aceptación después de autorización

1. Configurar clave solo en servidor/secret manager y límites aprobados; nunca Git
   ni variables VITE. Fijar fecha UTC de vencimiento 30 días después del permiso.
2. Generar una propuesta EN→ES en una convocatoria conocida, sin datos privados.
3. Revisar los once campos: países elegibles, exclusiones, beneficiarios, montos,
   monedas, fechas y negaciones. Una buena forma JSON no garantiza fidelidad.
4. Repetir la lectura: debe reutilizar propuesta, sin segundo cobro. Confirmar
   reserva persistida. Fallos inciertos no se reintentan ni liberan presupuesto.
5. Guardar solo después de revisión explícita. Verificar detalle/lista/búsqueda ES,
   EN y original, sin mezclar versiones ni modificar importes/fechas estructurados.
6. Probar también ES→EN. Detener ante omisiones o alteración de elegibilidad.

Después: traducciones iniciales revisadas del catálogo; matching/alertas y otros
idiomas se auditan por separado. No afirmar que todo el contenido ya es bilingüe.
