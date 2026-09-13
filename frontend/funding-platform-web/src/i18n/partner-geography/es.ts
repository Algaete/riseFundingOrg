export const partnerGeographyEs = {
  "title": "Países y regiones admitidos para los socios",
  "help": "Indica el país de sede que las bases exigen a las organizaciones aliadas. No modifica los países elegibles del postulante ni la ubicación del proyecto. No deduzcas este requisito del país del financiador.",
  "scope": "Alcance geográfico de los socios",
  "scopes": {
    "0": "Pendiente de confirmar",
    "1": "Sin restricción geográfica, confirmado en las bases",
    "2": "Países o regiones específicos"
  },
  "regionsTitle": "Regiones o grupos de países",
  "countriesTitle": "Países concretos",
  "search": "Buscar un país",
  "selected": "Países seleccionados",
  "union": "Se admite cualquiera de los países seleccionados o incluidos en las regiones seleccionadas. Selecciona al menos uno.",
  "distinction": "Europa (ONU M49) y Unión Europea son grupos distintos. Si las bases usan otra definición, selecciona sus países concretos. Las regiones no incluyen automáticamente territorios asociados por vínculo político.",
  "regions": {
    "M49-002": "África (ONU M49)",
    "M49-019": "América (ONU M49)",
    "M49-142": "Asia (ONU M49)",
    "M49-150": "Europa (ONU M49)",
    "M49-009": "Oceanía (ONU M49)",
    "M49-419": "América Latina y el Caribe (ONU M49)",
    "EU": "Unión Europea (27 países)"
  },
  "catalogUnavailable": "No está disponible el catálogo geográfico. La selección guardada se conserva; reintenta cargarlo para editar.",
  "unavailableCountry": "País no disponible ({{id}})",
  "remove": "Quitar {{country}}",
  "choose": "Selecciona al menos un país o región.",
  "reconfirm": "He revisado la selección con el catálogo actual",
  "status": {
    "unverified": "País o región del socio pendiente de confirmar: otro país no garantiza que sea admisible.",
    "specific": "Filtrado por país de sede según la selección revisada del fondo.",
    "any": "Las bases revisadas no imponen una restricción geográfica adicional al socio.",
    "needs-review": "La selección geográfica necesita revisión. No se proponen organizaciones hasta corregirla."
  },
  "summaryHelp": "Comprobamos la sede declarada, no la elegibilidad completa, la composición del consorcio ni si ya cuentas con ese socio. Este filtro no se aplica a personas profesionales.",
  "home": "Sede declarada: {{country}}.",
  "unknownHome": "País de sede no informado.",
  "matched": "El país de sede coincide con la selección geográfica revisada."
} as const
