# Fondos: filtros y clasificación revisada

`/funding/explore` complementa el buscador de texto y el espacio de oportunidades de cada ONG.
Filtra país/región, área, instrumento, organización elegible, idioma declarado, montos y moneda,
fechas, tipo de financiador principal y requisitos de consorcio/socio internacional.
«No informado» no se transforma en «No», ni se convierten monedas. El filtro de idioma incluye
los propósitos declarados; el detalle existente distingue documento/postulación/trabajo.

Desde el detalle administrativo: **Revisar clasificación**. Solo administradores con MFA vigente
pueden confirmar datos respaldados por una fuente ya vinculada. Se conserva historial e idempotencia,
se exige ETag y versión del fondo. Cambiar el contenido invalida la clasificación pública hasta otra
revisión. Guardar clasificación no publica, aprueba ni modifica el fondo subyacente.

Ingesta: se reutiliza el conector RSS/Atom oficial gobernado, sin inventar un segundo canal con
menos controles. Se corrigió selección del enlace alternativo de Atom, deduplicación exacta y rechazo
de identidades contradictorias o HTML disfrazado de feed. Se mantienen límites, robots, licencia,
allowlist, fingerprint de política, staging y revisión editorial. No se habilitó FundsforNGOs:
faltan feed/API y condiciones de acceso autorizadas; no se realizará scraping restringido.

SQL 045 crea solo dos tablas editoriales auxiliares y tres procedimientos con permiso EXECUTE
limitado al rol API; no permisos directos de tablas. Smoke transaccional preparado, ejecución SQL
pendiente del preflight de despliegue. No se han cambiado cuentas, roles reales ni publicado fondos.
