# Elegibilidad revisada y catálogo chileno — 21 de noviembre de 2026

Esta entrega agrega límites al presupuesto total del proyecto y al presupuesto anual
institucional, áreas y beneficiarios obligatorios, requisitos manuales y restricciones
regionales. Las reglas no convierten monedas: una comparación entre monedas distintas
queda sin determinar. Un límite estricto rechaza la igualdad; los intervalos de presupuesto
que cruzan el umbral quedan sin determinar. «Otro» no acredita un requisito obligatorio.

El perfil `deterministic-sql-v3` conserva los nueve criterios ponderados y agrega cinco
condiciones de peso cero. Un incumplimiento conocido determina incompatibilidad, aunque
haya requisitos pendientes. Sin incumplimientos, los requisitos manuales o una política
sin revisar mantienen el resultado en datos insuficientes. La puntuación es afinidad y
no certifica admisibilidad. Las versiones y resultados v1/v2 conservan su significado.

SQL065 corrige exclusivamente las tres referencias del piloto original cuyo hash usaba
UTF-16; no cambia contenido, versiones ni estado editorial. El publicador original
también usa UTF-8 para futuras instalaciones.

SQL064 agrega una política JSON opcional, validada y vinculada a la versión editorial.
La API y el editor administrativo permiten mantenerla. El perfil v3 se crea inactivo;
el publicador del lote lo activa atómicamente con las diez políticas revisadas.

## Catálogo

El archivo `database/Curation/chile-eligibility-catalog-2026-11.json` contiene siete
actualizaciones y tres incorporaciones, con fuentes y condiciones pendientes:

- FAU-LAC Respuesta Rápida: hasta USD 8.000; hasta USD 10.000 con cuidado colectivo.
- IDEA WILD: aporte principalmente en equipamiento, solicitado por una persona designada;
  valor estrictamente inferior a USD 1.500. No es un límite al costo total del proyecto.
- ITI Comunidades en Acción 2026: hasta CLP 2 millones, Iquique y Alto Hospicio;
  cierre 22 de noviembre a las 23:59 de Chile (23 de noviembre, 02:59 UTC).

Las fichas antiguas conservan su fecha de verificación de fuente, salvo Pollination,
reconsultada el 21 de noviembre. No se publican como abiertas las modalidades por
invitación de FAU-LAC ni programas sin elegibilidad chilena confirmada. Los candidatos
excluidos y sus motivos quedan en el JSON. Diez fichas no completan la meta de 50–60.

## Validación y publicación

Se ejecutaron 65 pruebas SQL con rollback, 23 comprobaciones de mapa y 13 de traducción.
SQL064 incluye 26 casos y sus repeticiones: fronteras presupuestarias, monedas diferentes,
intervalos, categorías, beneficiarios, revisión manual, regiones y preservación del
historial. El publicador verifica el lote completo, repetición sin duplicados, rechazo de
versiones concurrentes y las pruebas históricas con v3 activo. Las pruebas históricas
seleccionan v2 dentro de su transacción y restauran v3 al revertir.

La entrega requiere esta secuencia:

1. CI correcto en el commit exacto de main.
2. `infra/scripts/check-dev-database.sh --release`: migración, repetición y pruebas.
3. Desplegar API y frontend del mismo commit.
4. `infra/scripts/curate-pilot-dev.sh --preview-eligibility` con rollback.
5. Aplicar el lote con `RF_CATALOG_ELIGIBILITY_CONFIRMATION` igual a
   `PUBLISH-THREE-NEW-REVIEW-SEVEN-AND-ACTIVATE-ELIGIBILITY-V3` y `--apply-eligibility`.
6. Comprobar fichas, desglose, cálculo nuevo y conservación del borrador TEST por UI.

Los scripts SQL de Azure usan una regla temporal limitada a la IP del ejecutor y la
eliminan al terminar. El publicador no consulta cuentas ni habilita extracción automática.
No se agregan servicios pagados, IA generativa ni cobros.

Las comprobaciones de despliegue y las capturas de aceptación se registran junto al
commit y los workflows de la entrega. No confundir la validación local con publicación
en Azure.
