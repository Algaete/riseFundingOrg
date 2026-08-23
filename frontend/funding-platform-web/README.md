# FundingPlatform · frontend

Base del frontend del MVP construida con React, TypeScript y Vite. Incluye las
rutas públicas, de organización y administrativas definidas para Fase 1, con
shell responsive. El primer vertical funcional muestra oportunidades persistidas
desde Grants.gov en `/funding` y su ficha trazable en `/funding/:slug`.

## Comandos

- npm run dev
- npm run lint
- npm test
- npm run build

Configura VITE_API_BASE_URL a partir de .env.example. Por defecto, el cliente
HTTP utiliza `/api/v1`, envía cookies y normaliza respuestas Problem Details como
ApiError. Vite proxifica `/api` a `http://localhost:5070`; para otro puerto usa, por
ejemplo, `FUNDING_PLATFORM_API_PROXY_TARGET=http://localhost:5080 npm run dev`.

## Estructura

- src/api: cliente HTTP y configuración de TanStack Query.
- src/components: shell, layout, tema y primitivas compatibles con shadcn/ui.
- src/features: vertical slices; incluye catálogo/ficha de fondos y los journeys de autenticación/MFA.
- src/hooks: hooks compartidos.
- src/pages: páginas públicas, de organización y administrativas.
- src/types: contratos transversales.
- src/utils: utilidades sin estado.

La sesión mantiene el access token únicamente en memoria y rota el refresh token en
una cookie HttpOnly. Incluye single-flight refresh, retry acotado para carreras entre
pestañas, rutas protegidas y guarda administrativa. Los permisos tenant detallados y
los contratos generados desde OpenAPI se completan con sus verticales.
