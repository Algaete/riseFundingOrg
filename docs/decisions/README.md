# Registros de decisiones arquitectónicas

Esta carpeta contendrá Architecture Decision Records para decisiones que afecten estructura, seguridad, operación, costos o sustituibilidad de proveedores.

Durante FASE 0, las decisiones iniciales quedaron consolidadas en la sección “Decisiones técnicas
registradas” de [FASE-0-DISENO-TECNICO.md](../FASE-0-DISENO-TECNICO.md). Las decisiones posteriores
se registran por separado.

## Índice

- [ADR-009 — Proyecto como sujeto principal de matching](ADR-009-project-first-matching.md)
- [ADR-010 — Adquisición gobernada en lugar de crawler universal](ADR-010-governed-ingestion.md)
- [ADR-011 — Separar Funder de FundingSource](ADR-011-funder-vs-source.md)
- [ADR-012 — Agente semántico acotado y supervisado](ADR-012-bounded-semantic-agent.md)

## Convención

Los ADR nuevos usarán nombres como:

~~~text
ADR-013-titulo-breve.md
~~~

Cada registro incluirá:

1. título y fecha;
2. estado: Proposed, Accepted, Superseded o Rejected;
3. contexto y problema;
4. decisión;
5. alternativas consideradas;
6. consecuencias, riesgos y criterio para revisarla;
7. enlaces a ADR relacionados.

Los ADR son inmutables una vez aceptados. Una decisión nueva que reemplace otra crea un archivo adicional y marca la anterior como Superseded. Nunca se incluyen secretos, credenciales ni datos personales.
