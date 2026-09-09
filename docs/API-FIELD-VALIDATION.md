# Validaciones por campo: contrato aditivo

Estado: I18N-05E.1, implementado localmente. No desplegado.

## Alcance

Crear/actualizar organizaciones y guardar su perfil; crear/actualizar proyectos.
Incluye las validaciones de sus servicios y los errores sanitizados de relaciones/catálogos
que esos servicios convierten desde persistencia. No cambia reglas, normalización, campos
obligatorios, permisos, ETags, snapshots ni política editorial.

No incluye todavía publicación/revisión, financiadores/oportunidades, autenticación,
matching, conexiones, postulaciones, suscripciones, importaciones ni errores del model binder.
No confundir códigos generales de `type` con códigos de reglas por campo.

## Respuesta

Se preservan HTTP 400, `application/problem+json`, `type`, `title` y `errors` anteriores.
La extensión opcional `validationIssues` acompaña los mismos campos:

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

El ejemplo omite `type` y extensiones de diagnóstico. Un cliente antiguo sigue leyendo
`errors`. Un cliente nuevo prefiere `validationIssues` para cada campo que la incluya,
y sólo usa mensajes heredados conocidos cuando el campo no trae códigos. No hace falta
desplegar API y web al mismo instante; ambas combinaciones siguen siendo compatibles.

## Reglas del contrato

- `code` es estable y no depende del idioma. Cambiar la traducción no cambia el código.
- `min`/`max`, opcionales o nulos, describen límites de la regla; nunca valores ingresados.
  En este corte sólo `text-max-length` utiliza `max` como parámetro de traducción.
- No enviar contenido libre, excepciones, SQL, tokens ni identificadores privados como
  parámetros o mensajes nuevos. Los mensajes heredados conservados ya son sanitizados.
- `FieldValidationErrors` mantiene juntos mensaje y código, preservando la precedencia
  anterior: la última regla fallida para un campo reemplaza su error, sin duplicarlo.
  El arreglo del protocolo permite evolución; este corte emite un error por campo.
- No obtener códigos comparando mensajes ni inferir equivalencias por fragmentos de texto.
  Un diccionario heredado no se convierte automáticamente a códigos inventados.
- Los consumidores verifican el formato recibido. Un código desconocido, parámetros
  inválidos o mensajes desconocidos producen un aviso genérico traducido, nunca texto crudo.
- React Hook Form conserva un descriptor interno validado como mensaje; se traduce al
  renderizar. No se persiste ni se envía este descriptor a la API. Cambiar idioma no reinicia
  el formulario, la mutación, el foco lógico ni el ETag.

## Registro y mantenimiento

Los 37 códigos actuales se emiten en `OrganizationProfileService`/`ProjectService` y tienen
recursos separados en `frontend/funding-platform-web/src/i18n/validation/{es,en}.ts`.
`tests/field-validation-contract.test.mjs` comprueba cobertura y paridad contra los emisores.
Las pruebas de servicio verifican precedencia, límites y mensajes heredados; las de endpoints
ejercitan el JSON real de los cuatro endpoints con repositorios simulados. Las pruebas web
comprueban respuestas antiguas/nuevas, fallbacks, cambios de idioma y conservación de datos.

Para ampliar a otro módulo: emitir el código desde la regla, mantener el contrato anterior,
integrar el consumidor y añadir pruebas de protocolo/idioma antes de declarar cobertura.
Las validaciones editoriales y de preparación para publicar son el siguiente corte.
Carga diferida de idiomas y formatos restantes siguen pendientes en I18N-05E.
