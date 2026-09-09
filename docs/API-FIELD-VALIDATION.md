# Validaciones por campo: contrato aditivo

Estado: I18N-05E completo en desarrollo local. No desplegado.

## Alcance

Códigos por campo en organizaciones/proyectos, publicación y revisión, fondos/financiadores,
filtros públicos y privados, postulaciones/calendario, alertas/búsquedas guardadas, networking,
matching, suscripciones, importaciones/deduplicación, adjuntos, documentos fuente,
administración de usuarios/operaciones y administración semántica. Autenticación conserva las
reglas de Identity y añade códigos a sus errores de registro, contraseña y confirmación MFA.

Los errores de binding de solicitudes (JSON, valores de query y tipos de contenido) reciben
un código genérico seguro. Cuando el parser no identifica un campo, se usa `request`;
no se inventa una ruta de campo. No confundir códigos generales de `type` con reglas por campo.

No se cambian reglas, normalización, obligatoriedad, permisos, ETags, idempotencia,
snapshots, aislamiento entre organizaciones ni política editorial. Los estados HTTP y el
contrato `errors` existentes se conservan; binding incorpora un cuerpo seguro sin datos enviados.

## Respuesta

Se preservan `application/problem+json`, `type`, `title` y `errors` anteriores.
La extensión aditiva `validationIssues` acompaña los mismos campos, también en HTTP 409/422
cuando ya existían errores por campo:

```json
{
  "title": "One or more validation errors occurred.",
  "status": 400,
  "errors": { "summary": ["Admite hasta 1000 caracteres."] },
  "validationIssues": {
    "summary": [{ "code": "text-max-length", "min": null, "max": 1000 }]
  }
}
```

Un cliente antiguo sigue leyendo `errors`. Uno nuevo prefiere `validationIssues` por campo;
si falta esa extensión, sólo presenta mensajes heredados reconocidos. No hace falta publicar
API y web al mismo instante. Códigos futuros o malformados producen un aviso genérico traducido.

## Reglas del contrato

- `code` es estable, sensible a mayúsculas y ajeno al idioma. Cambiar texto no cambia su ID.
  Los IDs opacos `api-validation-NNN` son valores literales permanentes: no renumerar al
  reordenar archivos, retirar reglas o agregar módulos.
- `min`/`max` describen límites de la regla, nunca valores ingresados. En backend son enteros
  de 64 bits para permitir tamaños de archivos; la web acepta sólo enteros positivos seguros
  para parámetros que la traducción espera. No admite texto libre como interpolación.
- `FieldValidationErrors.Set` preserva la precedencia anterior (último error del campo).
  `Add` conserva varias incidencias de preparación/password, sin mensajes duplicados.
  `Merge` preserva códigos y límites al combinar resultados; `Remove` elimina ambos.
- Las familias `funding-ready-*`, `project-ready-*` y `auth-*` usan códigos de sus fuentes,
  no comparaciones de mensajes. Si esas fuentes añaden reglas, añadir traducciones y pruebas.
- Un diccionario legado sigue siendo aceptado. Su combinación con errores tipados puede usar
  `validation-unknown`; nunca inferir una regla por fragmentos de texto.
- No se devuelven excepciones de parsing, SQL, tokens ni valores enviados en nuevos metadatos.
  La web no usa texto arbitrario de servidor como traducción.
- React Hook Form y algunos avisos conservan un descriptor interno validado; otros conservan
  el error original. Ambos se traducen al renderizar. Cambiar idioma no reinicia el formulario,
  repite mutaciones ni modifica su ETag. El descriptor no se persiste ni envía a la API.

## Registro y mantenimiento

Hay 252 códigos con recursos ES/EN en
`frontend/funding-platform-web/src/i18n/validation/{es,en}.ts` y `api-validation/{es,en}.ts`.
El registro extendido tiene huecos intencionales por reutilización de reglas existentes.

`tests/field-validation-contract.test.mjs` comprueba emisores estáticos de Application/API,
paridad y ausencia de IDs duplicados. Las pruebas de endpoints verifican el JSON real,
readiness, HTTP 400/415/422 y ausencia de datos de entrada en problemas de parsing. La suite
de navegador combina respuestas heredadas y nuevas y comprueba conservación de borradores.

Para agregar una regla: asignar un código nuevo o reutilizar uno de idéntica semántica,
emitirlo desde la validación, conservar el contrato anterior, traducir ES/EN, registrar recursos
en la ruta y añadir pruebas del consumidor. Ver [carga y formatos](I18N-LOADING-AND-FORMATS.md).
