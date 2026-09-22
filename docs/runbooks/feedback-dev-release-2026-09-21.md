# Release seleccionado del feedback de septiembre

El usuario autorizó avanzar desde el preflight aprobado hacia publicación de
SQL → API → frontend y verificación. Destino: recursos Azure dev existentes.
No autoriza cambiar capacidad, crear servicios ni habilitar proveedores pagos.

## Selección

Rama preparada desde `main` ca3c28fce2d2c1c61fb9127d804ab40f9994ce7c, sin mover
la rama de respaldo ni sobrescribir su trabajo. Incluye:

- Formularios: proyectos USD, buscador de países, indicadores con ejemplos,
  ubicación por mapa y cierre con hora local/minutos/zona predefinida.
- Eliminación de enlaces públicos adicionales a fuentes (postulación se conserva).
- Categoría Otros con detalle, antecedentes de proyectos y portadas temáticas.
- Traducciones editoriales revisadas ES/EN, listados y búsqueda bilingüe,
  con ambos flags desactivados. No genera traducciones automáticamente.
- SQL052–059 y regresión actualizada. SQL052 solo añade AUD al catálogo;
  SQL059 repara únicamente los dos hashes de identidad de fondos TEST geográficos.

Excluidos: observador FundsforNGOs, credenciales, importación asistida/normalización
de monedas y sus tests, cambios pausados de workers/adjuntos/infra. El repositorio
SQL compartido conserva el comportamiento de ingesta de main y solo incorpora las
lecturas del feedback. Los dobles de tests de ingesta cambian únicamente la firma
de búsqueda necesaria para la interfaz de catálogo.

## Verificación y orden

La selección local pasa1059 unitarias .NET y1194 frontend/95 archivos, lint,
build frontend y tipos E2E. Los conteos del respaldo1139/1208 incluyen trabajo
excluido deliberadamente, no pruebas omitidas dentro del release.
Integración HTTP y CI deben terminar aprobados antes de merge/despliegue.
El preflight previo del mismo SQL pasó59 smokes,23 checks de mapa y13 de
traducciones con rollback; se repite para el SHA limpio y aprobado antes de apply.

Publicación mediante PR/CI → main exacto → wrapper SQL con preflight/apply/reapply/test
→ workflow API por digest → workflow frontend por SHA y QA automatizado.
Conservar escala de API, SQL0,5–1vCore/autopausa60, MFA, configuración de sesión
y servicios deshabilitados. Retirar solo las reglas temporales SQL creadas.

La habilidad Browser confirmó que no hay navegador conectado para QA interactivo.
Los workflows existentes conservan sus pruebas de navegador público; no reemplazan
la aceptación autenticada de los formularios con una cuenta real.

## Límites

No afirmar que este documento prueba un despliegue ya realizado. Registrar SHA,
PR, pipelines y resultados efectivos al finalizar en el seguimiento del release.
Siguen pendientes activación/carga inicial de traducciones, generación automática
con presupuesto/proveedor, descubrimiento abierto y multimedia/adjuntos por plan.
El módulo de archivos y el importador pausado no se activan en este release.
