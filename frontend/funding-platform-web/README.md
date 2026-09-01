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
- npm run typecheck:e2e
- npm run test:e2e:public

Configura VITE_API_BASE_URL a partir de .env.example. Por defecto, el cliente
HTTP utiliza `/api/v1`, envía cookies y normaliza respuestas Problem Details como
ApiError. Vite proxifica `/api` a `http://localhost:5070`; para otro puerto usa, por
ejemplo, `FUNDING_PLATFORM_API_PROXY_TARGET=http://localhost:5080 npm run dev`.

## Pruebas de navegador

Instala Chromium una vez con `npx playwright install chromium`. La suite
`npm run test:e2e:public` construye un preview aislado, simula únicamente los
contratos públicos necesarios y valida navegación, guards, vista móvil y reglas axe
etiquetadas WCAG 2.0/2.1 A/AA. Es una comprobación automática, no una certificación
de conformidad WCAG. CI la ejecuta sin credenciales Azure ni de usuarios. El workflow
`Azure dev frontend` repite la misma suite después de publicar y comprueba además el
SHA de `deploy-meta.json`.

`npm run test:e2e:authenticated` queda disponible para una cuenta de prueba manual,
pero no recibe secretos desde CI. Lee `E2E_USER_EMAIL` y `E2E_USER_PASSWORD` del
entorno y siempre exige un `PLAYWRIGHT_BASE_URL` explícito. Su origen debe coincidir
exactamente con `E2E_ALLOWED_ORIGINS`; cada POST de autenticación sólo puede salir al
origen listado en `E2E_ALLOWED_API_ORIGINS`. Para un frontend remoto, el origen debe
usar HTTPS; HTTP sólo se permite en loopback. La suite bloquea cualquier otro POST y
deshabilita capturas, video y trazas para reducir el riesgo de persistir contraseñas,
cookies o tokens.

Para probar en local, primero inicia Vite manualmente en otra terminal con una API
aprobada que permita CORS desde ese origen; la suite no levanta un preview cuando
recibe `PLAYWRIGHT_BASE_URL`. Carga la cuenta mediante un prompt para no escribir la
contraseña en la línea de comandos y luego ejecuta:

```sh
printf 'Correo E2E: '
IFS= read -r E2E_USER_EMAIL
printf 'Password E2E (oculto): '
IFS= read -rs E2E_USER_PASSWORD
printf '\n'
export E2E_USER_EMAIL E2E_USER_PASSWORD

PLAYWRIGHT_BASE_URL='http://127.0.0.1:5173' \
E2E_ALLOWED_ORIGINS='http://127.0.0.1:5173' \
E2E_ALLOWED_API_ORIGINS='https://api-dev.example' \
npm run test:e2e:authenticated

unset E2E_USER_EMAIL E2E_USER_PASSWORD
```

`E2E_ALLOWED_API_ORIGINS` debe contener el origen que observa el navegador: el de la
API si el bundle usa una URL absoluta, o el del frontend si se usa un proxy relativo.
No se debe usar el SuperAdmin real. Hasta disponer de una identidad E2E efímera y
dominios same-site, este camino valida sólo la sesión actual y no certifica refresh
entre recargas.

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
