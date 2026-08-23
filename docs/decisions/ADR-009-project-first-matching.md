# ADR-009 — Proyecto como sujeto principal de matching

**Fecha:** 17 de agosto de 2026

**Estado:** Accepted

## Contexto

El diseño inicial calculaba compatibilidad principalmente entre el perfil de una organización y una
oportunidad. La visión funcional ampliada distingue organización y proyecto: una misma ONG puede
tener proyectos con territorios, beneficiarios, presupuestos, duración y objetivos diferentes.

## Decisión

La organización continúa siendo el límite de tenant, autorización y suscripción. El proyecto pasa a
ser el sujeto principal de Opportunity Matching. Cada cálculo usa simultáneamente una versión del
proyecto y una versión del perfil institucional.

Un match reproducible identifica `ProjectVersion`, `OrganizationProfileVersion`,
`FundingContentVersion`, perfil/engine de matching y calibración semántica. Las reglas de elegibilidad
institucional usan la organización; temática, territorio, beneficiarios, presupuesto, duración e
impacto usan preferentemente el proyecto.

Las recomendaciones sin proyecto, si se conservan, se rotulan como descubrimiento institucional y
no se mezclan con scores de proyecto.

## Consecuencias

- `Project` debe implementarse antes del motor de matching.
- Las rutas de matches quedan anidadas bajo organización y proyecto.
- Cambiar proyecto u organización invalida los matches correspondientes.
- Aumenta el volumen; solo se calculan oportunidades activas y candidatos prefiltrados.
- El baseline SQL 001 no se modifica; el modelo se agrega mediante migraciones futuras.
