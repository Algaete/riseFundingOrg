# Categoría «Otros» y antecedentes de proyectos — 21-09-2026

Bloque 3 del feedback: implementado localmente. **No desplegado; migraciones054/055
validadas en Azure dev con rollback** dentro de052–059. Ver
[preflight aprobado](runbooks/feedback-sql-preflight-2026-09-21.md). No incorpora servicios, proveedores,
archivos adjuntos, traducción automática ni nuevas llamadas externas.

## Oportunidades: Otros (especificar)

- Reutiliza `FundingCategories.Id=16`, código `OTHER`, fijado por migración 031.
  No crea categorías globales a partir de texto libre ni reactiva catálogos.
- `otherCategoryDescription` es texto opcional en el contrato general, pero
  obligatorio al seleccionar Otros. Se recorta el espacio exterior y se admiten
  hasta 200 unidades UTF-16, de acuerdo con los límites de C#/JavaScript/SQL.
- El formulario conserva lo escrito mientras se alterna la selección. Al guardar
  sin Otros, envía null y elimina la descripción. La API rechaza texto con Otros
  desmarcado; frontend y API señalan el campo exacto.
- Se guarda en la misma operación/versionado/snapshot que el resto de la ficha,
  con ETag, idempotencia, propiedad de workspace, MFA administrativo y revisión
  existentes. Editar contenido publicado sigue requiriendo corrección editorial.
- Admin, workspace del financiador, organización y ficha pública leen el campo.
  La ficha pública lo distingue como «descripción del editor» y lo renderiza como
  texto, no HTML. No se incorpora automáticamente al matching, tarjetas, búsqueda
  ni a las once traducciones del bloque 2A: se conserva la redacción del editor.
- Registros antiguos mantienen null; no se inventa contenido ni se modifica su
  estado de publicación. Si un registro antiguo tiene Otros, al editarlo debe
  completarse la descripción. Un cliente antiguo no puede borrar silenciosamente
  una descripción al enviar Otros sin el texto.
- SQL 054 añade una columna nullable y actualiza los procedimientos vigentes de
  escritura y detalle. Valida selección, longitud y coincidencia exacta con el
  snapshot antes de persistir. No altera el criterio público de disponibilidad.

## Proyectos: antecedentes opcionales

Objeto `enrichment.background`, reutilizando el agregado y las versiones de proyecto:

| Campo | Uso |
| --- | --- |
| `additionalInformation` | Contexto, trayectoria y otros antecedentes relevantes. |
| `technicalInformation` | Resumen técnico y referencias descriptivas a estudios/informes. |
| `existingPartnerships` | Alianzas existentes y aportes, distinguiendo acuerdos de conversaciones. |
| `previousResults` | Resultados verificables, proyectos anteriores y aprendizajes. |

Cada campo admite hasta 3000 unidades UTF-16; ninguno es obligatorio. Se recortan
espacios exteriores y el vacío se normaliza a null. Textos y errores de interfaz
ES/EN; cambiar idioma no traduce ni borra lo escrito.

Estos antecedentes se incluyen en la revisión y ficha pública **solo cuando se
publica el proyecto**. El formulario lo advierte y pide no incluir datos sensibles
o confidenciales. No son notas privadas ni certifican/verifican alianzas. No se
ejecuta HTML, no se descargan referencias y no se generan alianzas automáticamente.
Los adjuntos, sus permisos y escaneo siguen siendo un módulo separado.

### Compatibilidad al actualizar

- `enrichment` omitido/null conserva la sección existente.
- `enrichment.background` omitido/null conserva los antecedentes existentes.
- `enrichment.background: {}` borra explícitamente sus cuatro campos.
- Si se envía un objeto background, reemplaza la sección completa; los campos
  omitidos dentro de ese objeto quedan en null.
- `enrichment: {}` mantiene el comportamiento anterior para los campos originales,
  pero preserva background para no perder datos con clientes anteriores al bloque.
- ETag protege la lectura/mezcla de compatibilidad ante escrituras concurrentes.
  SQL rechaza actualizaciones directas antiguas que omiten antecedentes ya guardados.

SQL 055 valida forma JSON, claves permitidas, tipos, duplicados y longitudes. Eleva
el límite existente de EnrichmentJson de 240000 a 400000 bytes para cubrir los
textos nuevos incluso con caracteres escapados. La proyección pública mantiene
redacción de ubicación/precisión geográfica existentes y solo añade background
validado como objeto JSON. Sin permisos runtime adicionales.

## Verificación y salida a dev

- Regresión completa: **1176 pruebas frontend (95 archivos), 1092 unitarias .NET
  y 378 HTTP aprobadas**. Build frontend/API y lint aprobados; diff sin errores
  de espacios. Pruebas HTTP con repositorios simulados, no contra Azure SQL.
- Pruebas de validación, normalización, snapshots, preservación/borrado explícito,
  contratos HTTP, texto público, formularios ES/EN, errores y límites.
- Migraciones y smokes 054/055 analizados como Azure SQL con ScriptDom; smokes
  transaccionales de datos sintéticos con rollback preparados. **Análisis no equivale
  a ejecución SQL.** Docker está instalado pero su daemon no está disponible;
  no se arrancó infraestructura ni se contactó Azure para suplirlo.
- Preflight pendiente: aplicar en SQL desechable el historial, correr smokes y
  contratos de resultados vigentes, verificar permisos y las migraciones nuevas.
- Despliegue cuando se autorice: SQL primero, API después, frontend al final.
  Probar guardar/reabrir, corregir/publicar, Otros requerido/quitar Otros,
  antecedentes públicos de proyecto aprobado, rechazo de acceso ajeno y ETag vencido.
- No volver a una API pre-055 que ignore background esperando poder editarlo:
  SQL protege los datos rechazando escrituras incompletas. No eliminar columnas
  ni historial para efectuar rollback.
- No mezclar automáticamente el trabajo previo de importaciones internacionales
  ni desplegar la rama de respaldo entera. No hay commit/push de este bloque.
