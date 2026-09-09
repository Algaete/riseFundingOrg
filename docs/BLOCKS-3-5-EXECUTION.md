# Bloques 3–5: ejecución autorizada

Alcance autorizado: completar consecutivamente los tres bloques locales, sin esperar confirmación
entre ellos. No incluye push, despliegue, cambios de cuentas reales ni ejecución SQL en Azure.

## 3. Mapa

- [x] API pública paginada y filtros, exclusivamente proyectos publicados y puntos opt-in redondeados.
- [x] Mapa mundial autocontenido, agrupación, zoom, navegación y fichas/listado accesibles ES/EN.
- [x] Migración/smoke, pruebas de privacidad, interfaz/navegador y commit local.

## 4. Espacio de financiadores

- [x] Registro de un perfil nuevo, propiedad explícita vinculada al usuario y aislamiento por financiador.
- [x] Gestión de perfil/oportunidades propias con borrador y envío a revisión, sin permisos globales Admin.
- [x] Aprobación/rechazo exclusivos de administración; concurrencia, trazabilidad y pruebas de aislamiento.
- [x] Interfaz ES/EN, migración/smoke, verificación y commit local.

## 5. Profesionales, alianzas y consorcios

- [x] Perfil profesional y capacidades con visibilidad opt-in y directorio filtrable.
- [x] Colaboración explícita y gestión de consorcios por proyecto, invitación y aceptación por participantes.
- [x] Permisos de propietario/participante, estados y protección de información privada.
- [x] Interfaz ES/EN, migración/smoke, verificación y commit local.

## Verificación del cierre local

839 pruebas unitarias .NET, 282 de integración HTTP con repositorios simulados,
924 de frontend (73 archivos) y 179 de navegador aprobadas. Build, lint y tipos E2E
aprobados. Solo se omite la prueba del SHA de Azure en el servidor local.
Los smokes 041–043 están escritos y analizados sintácticamente; no se ejecutaron en SQL real.

Contratos: [mapa](PROJECT-MAP.md), [financiadores](FUNDER-WORKSPACE.md),
[profesionales y consorcios](PROFESSIONALS-AND-CONSORTIA.md).

Se reutilizan los módulos existentes; no se amplía el motor de matching (bloque 6), conectores (7)
ni formatos multimedia (8). Las pruebas locales con dobles de repositorio y el parser SQL no
sustituyen la posterior ejecución de smokes y aceptación en Azure dev.
