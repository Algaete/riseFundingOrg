# Multimedia privada — bloque 8

Implementado localmente; disponibilidad en Azure sujeta a los gates del
[runbook de adjuntos](runbooks/project-assets-rollout.md). No es reproducción pública.

| Formato | Límite por archivo | Tratamiento |
| --- | --- | --- |
| JPEG, PNG, WebP | 10 MiB | Decodificación y recodificación de imagen existente |
| PDF | 25 MiB | Copia original privada, análisis y descarga |
| MP4 no fragmentado | 25 MiB | Comprobación acotada del contenedor, análisis y descarga |
| TXT UTF-8 | 1 MiB | UTF-8 estricto sin controles binarios, análisis y descarga |

Máximo ocho imágenes y cuatro documentos/videos combinados; doce adjuntos por proyecto.
Los originales MP4, PDF y TXT conservan sus metadatos. No se transcodifican ni se afirma
que la comprobación estructural MP4 valide todos los códecs o garantice reproducción.
ZIP, ejecutables, documentos Office y otros contenedores no se admiten en este bloque.

## Separación de responsabilidades

- Aplicación: permisos por organización, borrador editable, versiones y cuotas compartidas.
- Inspección: tamaño/longitud/tipo y estructura acotada; nunca sustituye el antivirus.
- Promoción: copia de los bytes exactos con ETag y hash, versiones `mp4-copy-v1` y `utf8-copy-v1`.
- SQL `046`: extensiones de restricciones verificadas y procedimientos existentes;
  mantiene recibos Defender, auditoría, revocación tardía y retención por manifiesto exacto.
- API: autenticación obligatoria, `attachment`, `nosniff`, CSP sandbox y `private, no-store`.
- Interfaz: selección y estados reales; ningún video, iframe o vista pública automática.

Validación local: 176 pruebas focalizadas de adjuntos/migraciones, 11 del panel, descarga
HTTP de los tres originales y prueba de copia exacta. Smoke SQL `046` usa recibos sintéticos
dentro de rollback: no acredita Defender real. La validación integrada se registra en
[bloques 6–9](BLOCKS-6-9-EXECUTION.md).
