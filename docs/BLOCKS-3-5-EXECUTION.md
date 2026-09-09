# Bloques 3–5: ejecución autorizada

Alcance autorizado: completar consecutivamente los tres bloques locales, sin esperar confirmación
entre ellos. No incluye push, despliegue, cambios de cuentas reales ni ejecución SQL en Azure.

## 3. Mapa

- [x] API pública paginada y filtros, exclusivamente proyectos publicados y puntos opt-in redondeados.
- [x] Mapa mundial autocontenido, agrupación, zoom, navegación y fichas/listado accesibles ES/EN.
- [x] Migración/smoke, pruebas de privacidad, interfaz/navegador y commit local.

## 4. Espacio de financiadores

- [ ] Registro de un perfil nuevo, propiedad explícita vinculada al usuario y aislamiento por financiador.
- [ ] Gestión de perfil/oportunidades propias con borrador y envío a revisión, sin permisos globales Admin.
- [ ] Aprobación/rechazo exclusivos de administración; concurrencia, trazabilidad y pruebas de aislamiento.
- [ ] Interfaz ES/EN, migración/smoke, verificación y commit local.

## 5. Profesionales, alianzas y consorcios

- [ ] Perfil profesional y capacidades con visibilidad opt-in y directorio filtrable.
- [ ] Colaboración explícita y gestión de consorcios por proyecto, invitación y aceptación por participantes.
- [ ] Permisos de propietario/participante, estados y protección de información privada.
- [ ] Interfaz ES/EN, migración/smoke, verificación y commit local.

Se reutilizan los módulos existentes; no se amplía el motor de matching (bloque 6), conectores (7)
ni formatos multimedia (8). Las pruebas locales con dobles de repositorio y el parser SQL no
sustituyen la posterior ejecución de smokes y aceptación en Azure dev.
