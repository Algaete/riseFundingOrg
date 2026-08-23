# ADR-010 — Adquisición gobernada en lugar de crawler universal

**Fecha:** 17 de agosto de 2026

**Estado:** Accepted

## Contexto

El producto necesita recopilar oportunidades desde Internet de forma periódica. Ejecutar un crawler
genérico dentro de la API crea riesgos de duplicación, SSRF, bloqueo de hosts, incumplimiento de
términos, fallas por escala y pérdida de estado.

## Decisión

La adquisición se ejecuta en Azure Functions mediante timers, outbox y Queue Storage. SQL conserva
runs, raw inmutable, estados e idempotencia. Cada fuente usa un adapter específico detrás de
`IFundingSourceProvider`.

El orden preferido es API oficial, RSS/feed, manual/archivo y finalmente web. Una fuente web requiere
compliance vigente, allowlist, rate limit, User-Agent identificable, caché condicional, bloqueo SSRF,
retención definida y kill switch. No se evaden autenticación, paywalls, CAPTCHA o anti-bot.

La captura y la publicación son procesos separados. La IA no publica y una persona revisa los
campos críticos antes de que una oportunidad quede disponible.

## Consecuencias

- La API responde `202` y no espera un scrape.
- Los mensajes contienen IDs/versiones, no HTML, documentos ni secretos.
- Retries y entregas duplicadas son esperables y deben ser idempotentes.
- Cada fuente implica mantenimiento y contract tests con fixtures.
- La falta de permiso bloquea esa fuente, no todo el pipeline.
