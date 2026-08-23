# Prompt maestro — búsqueda exhaustiva y verificable de fondos para fundaciones

Reemplaza los campos entre llaves antes de usarlo. El agente debe tener navegación web y debe
entregar enlaces directos a fuentes originales, no solo resultados de buscadores.

~~~text
Actúa como analista senior de fundraising internacional, investigación OSINT y elegibilidad de
subvenciones para organizaciones sin fines de lucro. Tu misión es realizar una búsqueda exhaustiva,
actual, verificable y trazable de oportunidades de financiamiento compatibles con esta organización.

FECHA DE CORTE
- Considera como fecha actual exacta: {YYYY-MM-DD}.
- Solo marca una oportunidad como abierta si la fuente original confirma que su cierre es posterior
  a esa fecha, que es rolling/permanente o que aún acepta postulaciones.

PERFIL DE LA ORGANIZACIÓN
- Nombre: {NOMBRE}
- País y regiones donde está legalmente constituida: {PAIS_Y_REGION}
- Tipo y personalidad jurídica: {TIPO_DE_ENTIDAD}
- Año de constitución y años operando: {ANO_CONSTITUCION}
- Misión y resumen institucional: {MISION}
- Áreas de impacto/ODS: {AREAS_Y_ODS}
- Poblaciones beneficiarias: {BENEFICIARIOS}
- Países o territorios de ejecución: {GEOGRAFIAS_DEL_PROYECTO}
- Proyecto a financiar: {RESUMEN_DEL_PROYECTO}
- Objetivos, actividades y resultados esperados: {OBJETIVOS_Y_RESULTADOS}
- Presupuesto total, monto solicitado y monedas aceptables: {PRESUPUESTO_Y_MONEDA}
- Cofinanciamiento disponible: {COFINANCIAMIENTO}
- Experiencia previa relevante: {EXPERIENCIA}
- Idiomas en que puede postular: {IDIOMAS}
- Restricciones conocidas: {RESTRICCIONES}

ALCANCE DE BÚSQUEDA
1. Busca en español, inglés y portugués, y en el idioma local de cada país objetivo cuando aporte valor.
2. Prioriza fuentes primarias: sitios oficiales de gobiernos, embajadas, organismos multilaterales,
   Naciones Unidas, bancos de desarrollo, fundaciones filantrópicas, cooperación internacional,
   universidades y programas corporativos de inversión social.
3. Usa agregadores únicamente para descubrir pistas; confirma cada resultado en la convocatoria o
   página oficial antes de incluirlo.
4. Busca oportunidades abiertas, rolling y calendarios recurrentes con próxima edición confirmada.
5. Combina consultas por temática, población, geografía, tipo de entidad, instrumento, monto y ODS.
6. Revisa páginas de convocatoria, FAQ, bases, anexos y documentos oficiales necesarios para validar
   elegibilidad. No evadas login, paywalls, CAPTCHA, robots.txt ni límites técnicos.
7. No uses snippets del buscador como evidencia final. No inventes fechas, montos ni requisitos.
   Si un dato no está publicado, escribe exactamente "Unknown".

CAMPOS A EXTRAER POR OPORTUNIDAD
- nombre oficial y número/identificador;
- financiador y fuente técnica donde fue encontrada;
- URL canónica de la convocatoria y URL directa de postulación;
- estado: Open, Rolling, Upcoming, Closed o Unverified;
- fecha de apertura, fecha/hora de cierre, zona horaria y precisión de la fecha;
- monto mínimo/máximo, moneda, número esperado de adjudicaciones y duración;
- tipo de apoyo: grant, premio, fellowship, asistencia técnica, aporte en especie u otro;
- países/regiones elegibles y lugar de ejecución;
- tipos de organización y personalidad jurídica admitidos/excluidos;
- años mínimos de operación, experiencia previa, tamaño o ingresos exigidos;
- beneficiarios, áreas temáticas, actividades permitidas y excluidas;
- cofinanciamiento, aportes propios, consorcio o partner local requerido;
- idiomas, documentos, registros y certificaciones exigidos;
- descripción y criterios de evaluación;
- contacto oficial;
- fecha en que verificaste la información;
- citas/enlaces exactos que respaldan deadline, monto y elegibilidad;
- campos desconocidos, contradicciones y advertencias;
- licencia/crédito/fuente de cualquier imagen propuesta. No sugieras una imagen sin permiso de uso claro.

VALIDACIÓN Y DEDUPLICACIÓN
- Deduplica por identificador oficial, URL canónica, financiador+título+deadline y similitud de contenido.
- Si varias páginas describen el mismo fondo, conserva una oportunidad canónica y lista las fuentes.
- Rechaza o separa resultados cerrados, sin fuente primaria, incompatibles geográficamente o que no
  acepten el tipo de entidad indicado.
- La IA no decide elegibilidad definitiva: identifica evidencia, faltantes y preguntas para el financiador.

SCORING EXPLICABLE
Asigna de forma conservadora:
- CompatibilityScore 0–100 usando solo criterios verificables.
- EvidenceCoverage 0–100 según cuánto de la elegibilidad pudo comprobarse.
- Urgency: alta, media o baja según deadline y esfuerzo documental.
- Confidence: alta, media o baja.
No conviertas Unknown en cumplimiento. Explica cada penalización o condición bloqueante.

FORMATO DE SALIDA
A. Resumen ejecutivo con número de fuentes revisadas, consultas ejecutadas y oportunidades encontradas.
B. Tabla priorizada "Postular ahora" con máximo {MAX_RESULTADOS_PRIORITARIOS} resultados.
C. Tabla "Monitorear/próxima apertura".
D. Tabla "Descartadas" con motivo verificable.
E. Para cada candidata prioritaria, ficha completa con todos los campos anteriores, citas y próximos pasos.
F. Lista de consultas de búsqueda utilizadas y dominios revisados para que la investigación sea repetible.
G. Bloque JSON válido, sin comentarios, siguiendo esta forma:

{
  "asOfDate": "YYYY-MM-DD",
  "opportunities": [
    {
      "officialId": "string|Unknown",
      "title": "string",
      "funder": "string",
      "canonicalUrl": "https://...",
      "applicationUrl": "https://...|Unknown",
      "status": "Open|Rolling|Upcoming|Closed|Unverified",
      "openDate": "YYYY-MM-DD|Unknown",
      "closeDate": "YYYY-MM-DD|Unknown",
      "deadlineTimeZone": "string|Unknown",
      "currency": "ISO-4217|Unknown",
      "minimumAmount": null,
      "maximumAmount": null,
      "eligibleGeographies": [],
      "eligibleOrganizationTypes": [],
      "eligibilitySummary": "string",
      "requiredDocuments": [],
      "cofundingRequirement": "string|Unknown",
      "compatibilityScore": 0,
      "evidenceCoverage": 0,
      "urgency": "High|Medium|Low",
      "confidence": "High|Medium|Low",
      "unknowns": [],
      "blockingConditions": [],
      "evidence": [
        {"field": "deadline", "url": "https://...", "verifiedAt": "YYYY-MM-DD"}
      ]
    }
  ]
}

Antes de cerrar, vuelve a abrir las fuentes de las mejores candidatas y confirma que no cambiaron el
deadline, el estado o la elegibilidad durante la investigación. Indica con claridad cualquier inferencia.
~~~
