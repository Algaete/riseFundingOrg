# ADR-012 — Agente semántico acotado y supervisado

**Fecha:** 17 de agosto de 2026

**Estado:** Accepted

## Contexto

La visión solicita IA para estructurar oportunidades, calcular compatibilidad y recomendar estrategia.
Un agente con navegador, secretos y escritura directa introduciría resultados no reproducibles,
prompt injection y acciones sin autorización.

## Decisión

El MVP separa extracción, normalización, validación, embeddings, matching y redacción. La extracción
usa salida estructurada versionada y evidencia. El motor determinístico decide hard gates y score.
El agente solo redacta recomendaciones desde un DTO allowlisted del breakdown calculado.

No recibe herramientas de publicación, SQL, email, pagos, navegador libre ni secretos. Los campos
sin evidencia se marcan `unknown`; una persona aprueba publicación y puede corregir datos.

## Consecuencias

- Los resultados son auditables y evaluables con corpus dorado.
- Hechos e inferencias se presentan por separado.
- Un cambio de modelo/prompt/schema exige versión y evaluación antes de producción.
- Proposal AI con herramientas adicionales requerirá otro ADR y human approval explícito.
