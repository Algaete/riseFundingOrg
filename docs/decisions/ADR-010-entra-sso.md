# ADR-010 — Microsoft Entra SSO mediante backend OIDC

**Fecha:** 21 de agosto de 2026

**Estado:** Accepted

## Contexto

FundingPlatform ya emite JWT propios, rota refresh tokens, exige MFA a roles privilegiados y usa
una SPA React separada. Se requiere SSO sin convertir tokens del proveedor en credenciales visibles
en el navegador ni vincular por accidente una identidad externa a una cuenta local existente.

## Decisión

La API ASP.NET Core es un cliente OIDC confidencial público/multitenant, que usa la autoridad `common`
y authorization code flow con PKCE. El registro acepta cuentas de cualquier directorio organizacional
y cuentas Microsoft personales. El middleware valida firma, audiencia y emisor tenant-specific mediante
el validador oficial; nunca se desactiva `ValidateIssuer`. Después crea una cookie externa temporal,
HttpOnly y Secure. FundingPlatform no persiste access tokens ni refresh tokens de Microsoft.

Tras validar la identidad, la API genera un handoff aleatorio de vida breve, guarda solo SHA-256 y
lo redirige una vez a la SPA. La SPA canjea el handoff por la sesión propia. El consumo es atómico y
verifica estado y `SecurityVersion` del usuario.

Una coincidencia de correo con una cuenta local no autoriza auto-link. La vinculación requiere una
sesión completa previa y un intento corto protegido por Data Protection. El secreto OIDC vive en
Key Vault/Managed Identity en Azure y nunca en el bundle React.

## Consecuencias

- El proveedor se mantiene deshabilitado hasta configurar `common`, Client ID, redirect URI y secreto.
- Los usuarios públicos no son invitados ni administrados dentro del tenant propietario de la aplicación.
- El login local sigue funcionando sin Entra.
- La revocación de sesiones propias continúa bajo control de FundingPlatform.
- Agregar otro proveedor requiere un issuer validado, nueva configuración y el mismo protocolo de
  handoff/link explícito; no se reutiliza el correo como prueba de propiedad.
