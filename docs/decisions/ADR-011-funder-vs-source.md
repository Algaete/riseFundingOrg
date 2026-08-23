# ADR-011 — Separar Funder de FundingSource

**Fecha:** 17 de agosto de 2026

**Estado:** Accepted

## Contexto

Una oportunidad puede encontrarse en un portal agregador, un sitio gubernamental o un documento,
mientras que el dinero lo entrega una entidad diferente. El baseline conserva `SponsorName` y
`FundingSource`, pero ninguno modela completamente al financiador estratégico.

## Decisión

`Funder` es la entidad canónica que financia. `FundingSource` es el origen técnico/editorial desde
el que se adquirió una observación. `FundingOpportunity` se relaciona con uno o más funders mediante
un rol, y con una o más fuentes mediante provenance/source links.

Los aliases de funder se normalizan y los merges requieren revisión. El historial de grants solo se
persiste cuando existe licencia, fuente y fecha de verificación.

## Consecuencias

- Se habilita Funder Matching sin depender de una convocatoria abierta.
- Una misma oportunidad puede tener fuente, administrador y financiador distintos.
- `SponsorName` queda como presentación/transición hasta una migración aditiva; no se edita 001.
- Deduplicar funders y deduplicar oportunidades son procesos diferentes.
