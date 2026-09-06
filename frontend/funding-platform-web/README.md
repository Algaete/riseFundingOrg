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
- npm run test:e2e:authenticated (sólo con opt-in y cuenta efímera)

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

`npm run test:e2e:authenticated` queda separado del CI ordinario y sólo se activa con
`E2E_REQUIRE_AUTHENTICATED=true`. Una vez activado falla, en vez de omitir pruebas, si
falta cualquier credencial o destino protegido. Lee `E2E_USER_EMAIL` y
`E2E_USER_PASSWORD` del entorno y exige un `PLAYWRIGHT_BASE_URL` explícito. Su origen
debe ser el único valor de `E2E_ALLOWED_ORIGINS`, y
`E2E_ALLOWED_API_ORIGINS` debe contener exactamente un origen de API. Los valores son
orígenes canónicos sin ruta ni barra final; un destino remoto siempre usa HTTPS y
HTTP sólo se permite en loopback.

La suite permite recursos de lectura únicamente desde esos dos orígenes y limita las
mutaciones a `POST /api/v1/auth/login`, `/refresh` y `/logout`. Antes de abrir el
formulario remoto verifica `deploy-meta.json` contra `E2E_EXPECTED_RELEASE_SHA` y
comprueba mediante la Public Suffix List que frontend y API comparten el dominio registrable
protegido `E2E_COOKIE_SITE`, incluidos los sufijos privados de proveedores cloud.
Luego valida login, los atributos seguros de la cookie, persistencia mediante refresh tras una recarga real, logout del
servidor y el guard de `/account` después de otra navegación documental. Capturas,
video, trazas y reintentos están deshabilitados; el cleanup defensivo intenta revocar
y verifica una sesión que haya quedado abierta sin persistir ni imprimir valores de cookies o tokens.

Para probar en local, primero inicia manualmente un preview sin HMR en otra terminal
con una API aprobada que permita CORS desde ese origen; la suite no levanta el
preview cuando recibe `PLAYWRIGHT_BASE_URL`:

```sh
VITE_API_BASE_URL='http://127.0.0.1:5070/api/v1' \
VITE_EXTERNAL_AUTH_BASE_URL='http://127.0.0.1:5070/api/v1' \
npm run build
npm run preview -- --host 127.0.0.1 --port 5173 --strictPort
```

Después carga la cuenta mediante un prompt para no escribir la contraseña en la
línea de comandos y ejecuta:

```sh
printf 'Correo E2E: '
IFS= read -r E2E_USER_EMAIL
printf 'Password E2E (oculto): '
IFS= read -rs E2E_USER_PASSWORD
printf '\n'
export E2E_USER_EMAIL E2E_USER_PASSWORD

PLAYWRIGHT_BASE_URL='http://127.0.0.1:5173' \
E2E_ALLOWED_ORIGINS='http://127.0.0.1:5173' \
E2E_ALLOWED_API_ORIGINS='http://127.0.0.1:5070' \
E2E_REQUIRE_AUTHENTICATED='true' \
npm run test:e2e:authenticated

unset E2E_USER_EMAIL E2E_USER_PASSWORD
```

`E2E_ALLOWED_API_ORIGINS` debe ser el origen que observa el navegador: el de la API
si el bundle usa una URL absoluta, o el del frontend si se usa un proxy relativo. En
loopback `E2E_EXPECTED_RELEASE_SHA` y `E2E_COOKIE_SITE` son opcionales; en cualquier
destino remoto son obligatorios.

El workflow manual `Azure dev authenticated E2E` ejecuta el mismo journey sin subir
reportes de sesión. Requiere seleccionar `main`, indicar su SHA completo, confirmar
`RUN-DEV-AUTH-E2E` y aprobar el environment `dev-auth-e2e`. Ese environment debe
restringirse a `main`, exigir reviewer y definir sólo estas credenciales efímeras:

- Variables: `AUTH_E2E_FRONTEND_ORIGIN`, `AUTH_E2E_API_ORIGIN` y
  `AUTH_E2E_COOKIE_SITE`.
- Secretos: `AUTH_E2E_USER_EMAIL` y `AUTH_E2E_USER_PASSWORD`.

No se debe usar una cuenta humana ni el SuperAdmin real. La cuenta E2E debe estar
verificada, sin MFA pendiente, con permisos mínimos y poder revocarse o rotarse sin
afectar datos reales.

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
