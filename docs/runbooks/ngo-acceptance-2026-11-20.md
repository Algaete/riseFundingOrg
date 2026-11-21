# Aceptación del piloto ONG: compatibilidad y borrador

## Alcance

Verificación del 20 de noviembre de 2026 en el frontend de Azure dev, con sesión
autenticada y una ONG/proyecto explícitamente ficticios. Base del repositorio:
`8dbde8eaddf15582e41ebc3ba463c39d37686689`. La publicación anterior del frontend
corresponde a `836c78da89756517307924dc9cf6592a4ad90807`.

No se enviaron postulaciones al financiador ni se activaron proveedores de IA,
servicios de pago o recursos nuevos. Las pruebas de base de datos se ejecutaron
en SQL Server local, limitado a loopback; no se abrió el firewall de Azure SQL.

## Verificación visual con datos persistidos

- La sesión se restableció después de recargar la página.
- El cálculo sin cambios recuperó la misma ejecución existente, sin duplicarla.
- Se probaron cambios de versión del perfil y la indicación de resultados
  desactualizados, conservando el historial anterior.
- Con año de constitución ficticio 2026, el motor evaluó seis fondos: dos
  incompatibles y cuatro con datos insuficientes. PAOCC explicó el incumplimiento
  de sus tres años requeridos frente a cero años de operación. Los resultados
  incompatibles mostraron puntuación «No aplica».
- Se retiró el año temporal y se guardó el perfil restaurado (versión 4). El nuevo
  cálculo mostró seis fondos con datos insuficientes, conservando el caso negativo
  en su historial e indicando que corresponde a una versión anterior.
- Se creó y editó un único registro de seguimiento para Global Fund for Children:
  estado «Preparando postulación», monto simulado USD 450, fecha planificada
  2026-11-25 y notas que indican expresamente no enviarlo al financiador.
- Una recarga completa conservó estado, monto, fecha y notas. El calendario
  mostró un único hito el 25 de noviembre, enlazado al mismo registro.
- Se revisaron formulario, campos y acciones en escritorio y viewport 390 × 844.
  El viewport temporal se restauró al finalizar.

## Pruebas de datos y aplicación

| Comprobación | Resultado |
| --- | --- |
| Solución .NET, Release, SDK 10.0.302 | Compilación sin errores ni advertencias |
| Unitarias de matching, postulaciones, recomendaciones y enriquecimiento | 69 correctas |
| Integración de workflows, fases 8B/9A y validación | 72 correctas |
| Suite completa frontend después de actualizar Zod | 1.263 correctas |
| Lint, build frontend, tipos E2E y `git diff --check` | Correctos |
| Scripts smoke contra SQL Server real local | 63 correctos, cambios revertidos |
| Contrato SQL del mapa | 23 comprobaciones correctas, sin commit de fixtures |
| Contrato SQL de traducciones | 13 comprobaciones correctas, sin commit de fixtures |
| Auditoría npm de dependencias de producción después del ajuste | 0 vulnerabilidades reportadas |

Los casos SQL cubren compatibilidad positiva, incompatibilidad, datos desconocidos,
precisión de plazos, aislamiento entre organizaciones, versiones, idempotencia,
creación/edición de postulaciones, duplicados, conflictos y calendario. La prueba
positiva es sintética: no certifica que la ONG ficticia sea elegible para un fondo
real. Algunas pruebas React emiten advertencias `act`; la suite termina sin fallos.

## Ajuste publicado con esta aceptación

Se fija Zod en `4.6.7` y se actualiza el lockfile. La versión anterior `3.25.76`
activaba una alerta de agotamiento de memoria durante validación de colecciones.
La suite completa verifica los formularios existentes con la nueva versión.
Referencia del mantenedor: [corrección de Zod](https://github.com/colinhacks/zod/pull/6652).

El resultado de cero vulnerabilidades corresponde a `npm audit --omit=dev`, no a
todas las herramientas de desarrollo. La instalación también reportó cinco
alertas en dependencias de desarrollo, fuera de esta corrección acotada.

El despliegue necesita únicamente el workflow de frontend existente con
`editorial_translations: true`. No requiere migración ni nueva revisión de API.

## Límites antes de un piloto de IA

La compatibilidad es orientativa y aplica nueve reglas estructuradas; no representa
una comprobación exhaustiva de las bases. Por ejemplo, el presupuesto del proyecto
inferior a USD 10.000 de The Pollination Project y requisitos específicos de
discapacidad/cultura necesitan revisión adicional. No se debe convertir un puntaje
de afinidad en afirmación de elegibilidad ni hacer pasar información desconocida
por un requisito cumplido.

El piloto de IA sigue pendiente de acotar proveedor, costos y evaluación de
respuestas con fuentes. Esta aceptación no activa generación automática, búsqueda
automática de fondos ni envío de postulaciones. El dominio no fue modificado.
