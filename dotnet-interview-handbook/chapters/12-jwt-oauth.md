# Chapter 12: JWT & OAuth

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** The anatomy of JWTs, signing algorithms (RS256 vs. HS256), the OAuth 2.0 grants (authorization code + PKCE, client credentials, refresh tokens), OpenID Connect, building and validating JWTs in .NET (`System.IdentityModel.Tokens.Jwt`, `OpenIddict`, Duende IdentityServer), token storage, revocation, refresh-token rotation, and how these power FHIR / SMART-on-FHIR healthcare integrations.

---

## 12.1 JWT Anatomy and Structure

### Interview Answer (30–45 seconds)

> "A JWT is a compact, self-contained, signed token made of three base64url-encoded segments — header, payload, and signature — separated by dots. The header declares the algorithm (`alg`) and key ID (`kid`); the payload carries claims like `iss`, `aud`, `exp`, `nbf`, `sub`, and custom claims; the signature is the first two segments signed with the algorithm in the header, using the key identified by `kid`. The signature is what makes it trustworthy: it lets a stateless API verify authenticity without calling back to the issuer. In healthcare, the same JWT pattern carries SMART-on-FHIR scopes so third-party apps get least-privilege access to clinical data."

### Detailed Explanation

**Structure:**

```
header.payload.signature
```

- **Header:** `{"alg":"RS256","typ":"JWT","kid":"key-123"}`
- **Payload (claims):**
  - Registered: `iss` (issuer), `sub` (subject), `aud` (audience), `exp` (expiry, Unix time), `nbf` (not before), `iat` (issued at), `jti` (unique ID).
  - Custom: `scope`, `role`, `tenant`, `fhirUser`, `patient`.
- **Signature:** `HMACSHA256(base64url(header) + "." + base64url(payload), secret)` for HS256; RSA-SHA256 with private key for RS256.

**Encoding:** base64url (no `+`, `/`, `=`; `-` and `_` instead) — URL-safe, compact.

**Self-contained:** all claims travel in the token — the API trusts them only *after* signature verification. No session state needed server-side (stateless), which is both the advantage and the revocation problem.

**Signing algorithms:**
- **HS256** (symmetric): single shared secret signs *and* verifies. Fast, but anyone with the secret can forge tokens. Same trust domain only.
- **RS256** (asymmetric): private key signs; public key verifies (distributed via JWKS). Enables multiple resource servers to validate without sharing secrets. **Standard for OAuth/OIDC providers.**
- Others: ES256 (ECDSA), EdDSA, and the *deprecated/insecure* `alg: none` and HS256 misuse against RSA public keys (algorithm-confusion attacks).

### Real World Example (Healthcare)

A hospital FHIR API receives `Authorization: Bearer eyJhbGciOiJSUzI1NiIs...` from a partner lab. The API's JWT bearer scheme fetches the IdP's JWKS, uses the `kid` to pick the RSA public key, verifies RS256 signature, checks `aud == fhir base URL`, and enforces the `scope` claim. The token never required a server session — the stateless check is the whole trust story.

### Production Code Example

```csharp
// Issuing side (authorization server, e.g., OpenIddict)
var token = new JwtSecurityToken(
    issuer: "https://auth.example.com",
    audience: "fhir-api",
    claims: new[]
    {
        new Claim(JwtRegisteredClaimNames.Sub, clinicianId),
        new Claim("scope", "patient/Observation.read patient/Condition.read"),
        new Claim("fhirUser", "https://fhir.example.com/Practitioner/123")
    },
    notBefore: DateTime.UtcNow,
    expires: DateTime.UtcNow.AddHours(1),
    signingCredentials: rsaCredentials);        // RS256 private key

string jwt = new JwtSecurityTokenHandler().WriteToken(token);

// Validation side (resource server) — Chapter 11.4
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://auth.example.com";
        options.Audience = "fhir-api";
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });
```

**Key lines explained:**

- `kid` + JWKS makes RS256 key rotation seamless.
- Issuer/audience/lifetime validation happens on every request, statelessly.
- SMART scopes travel as a claim but are *enforced* as authorization (Chapter 11).

### Internal Working

- Signing (HS256): `HMACSHA256` over `base64url(header).base64url(payload)` with a shared secret.
- Signing (RS256): RSA private key signs the SHA-256 digest; verification uses the public key from JWKS matched by `kid`.
- Validation: recompute signature → compare; then check `nbf`/`exp` against `DateTime.UtcNow` (± `ClockSkew`); then issuer/audience.
- The token handler (`JwtSecurityTokenHandler`/`JsonWebTokenHandler`) caches key material and validation parameters for performance.

### Advantages

- Stateless, horizontally scalable verification.
- Compact, URL-safe, self-contained claims.
- Industry-standard interop (OAuth/OIDC/SMART).

### Disadvantages

- No built-in revocation — a leaked token lives until `exp`.
- Payload is only *signed*, not encrypted — never put PHI in claims.
- Algorithm/`kid` confusion attacks if validation is sloppy.

### Best Practices

- Use RS256 (or ES256) for anything OAuth; keep HS256 secrets out of public clients.
- Never put PHI or sensitive data in the payload.
- Enforce `kid`/algorithm allow-lists (`TokenValidationParameters.ValidAlgorithms`).
- Keep tokens short-lived; rely on refresh tokens for renewals.

### Common Mistakes

- Storing PHI in the JWT payload (it's readable).
- HS256 with the RSA public key (algorithm-confusion) — fix by allow-listing algorithms.
- Accepting `alg: none` or not validating `kid`.
- Base64-decoding and trusting the payload without verifying the signature.

### Interview Follow-up Questions

1. What does the `kid` header let you do?
2. Why not put PHI in a JWT?
3. What is an algorithm-confusion attack?

### Senior Level Talking Points

- "A JWT is a signed assertion, not a secret box: integrity via signature, confidentiality only if encrypted. For FHIR, scopes and IDs go in claims; PHI stays behind the API."
- "The `kid` + JWKS dance is how key rotation works without downtime — the validation layer resolves the key by `kid`, so old and new keys coexist during rotation."

### Diagram

```mermaid
flowchart LR
    H["Header: alg=RS256, kid=key-123"] --> S["Signature = RSA-sign(header.payload)"]
    P["Payload: iss, aud, exp, scope, sub"] --> S
    S --> J["Header.payload.signature (JWT)"]
    J --> V["Validation: verify sig via JWKS kid → check iss/aud/exp → enforce scope"]
```

### Comparison Table

| Algorithm | Symmetric? | Key mgmt | Use |
|---|---|---|---|
| HS256 | Yes (shared secret) | Simple | Same-trust services |
| RS256 | No (pub/priv) | JWKS | OAuth/OIDC standard |
| ES256 | No (ECDSA) | JWKS | Modern, smaller sigs |
| none | — | — | Deprecated, never |

### Memory Trick

**"Header, Payload, Signature — signed, not secret"** — three parts; only the signature protects.

### Summary

A JWT is a signed, stateless, three-part token. Know its claims, the RS256-vs-HS256 choice, and that the payload is readable — that shapes every healthcare design decision.

### Interview Confidence Score

**High.** JWT anatomy is a guaranteed topic; the security nuances (no PHI, algorithm confusion, `kid`) set seniors apart.

---

## 12.2 OAuth 2.0 Grants and OIDC

### Interview Answer (30–45 seconds)

> "OAuth 2.0 is an *authorization* framework: it lets a client obtain limited-scope access tokens on behalf of a user or itself, without sharing the user's password. The main grants I use are the **authorization code with PKCE** for interactive apps (SPAs, mobile), **client credentials** for machine-to-machine services, and **refresh tokens** for long-lived sessions. OpenID Connect (OIDC) is OAuth plus an identity layer — it adds the `id_token` (a JWT about the user) and the `/userinfo` endpoint, so you get *who you are* (`id_token`) on top of *what you can do* (`access_token`). SMART-on-FHIR prescribes this exact stack for EHR integrations."

### Detailed Explanation

**The actors:**
- **Resource owner** — the user (e.g., a patient).
- **Resource server** — the API that holds the data (FHIR server).
- **Client** — the app requesting access (mobile, SPA, backend).
- **Authorization server** — issues tokens (IdP).

**Grants:**

1. **Authorization code + PKCE** (interactive):
   - Client redirects user to `/authorize?client_id&scope&code_challenge`.
   - User authenticates and consents; server redirects back with a one-time `code`.
   - Client exchanges `code` + `code_verifier` (PKCE proof) at `/token` for tokens.
   - PKCE prevents code interception even on public clients.
2. **Client credentials** (backend-to-backend):
   - Client sends `client_id` + `client_secret` to `/token` and gets a token directly.
   - No user involved; `system/` scopes in SMART.
3. **Refresh token** (session renewal):
   - A longer-lived token exchanged at `/token` for new access tokens.
   - With **rotation**: each refresh returns a new refresh token and invalidates the old — detecting token replay.
   - Held server-side (or in secure storage), never in the SPA bundle.

**OIDC additions:**
- `id_token` — JWT proving the user's identity (`sub`, name, email, `nonce`).
- `authorization_endpoint` discovery, `UserInfo` endpoint, `nonce` to bind token to the request.

**Flows compared to SMART-on-FHIR:**
- Interactive clinical/patient app → authorization code + PKCE → `patient/` or `user/` scopes.
- Backend lab integration → client credentials → `system/` scopes.

### Real World Example (Healthcare)

A patient portal mobile app uses authorization code + PKCE against the hospital's authorization server. The patient logs in, consents to `patient/Observation.read`, and the app exchanges the code. The token server issues an access token (1 hour) and a rotating refresh token (14 days). On refresh, the app posts the refresh token and gets a new pair; a stolen, already-used refresh token fails — alerting the server to replay.

### Production Code Example

```csharp
// Client-side (minimal API acting as a confidential client) — token acquisition
var client = new HttpClient();

var tokenResponse = await client.RequestAuthorizationCodeTokenAsync(new()
{
    Address = "https://auth.example.com/connect/token",
    ClientId = "lab-system",
    ClientSecret = secret,                       // stored in vault, never in source
    Code = authorizationCode,
    RedirectUri = "https://lab.example.com/callback",
    CodeVerifier = verifier                     // PKCE proof
});

var accessToken = tokenResponse.AccessToken;     // cache until near-expiry

// Server-side validation of an id_token (OIDC) is handled by
// AddOpenIdConnect / Microsoft.Identity.Web or AddJwtBearer for access tokens.
```

**Key lines explained:**

- `CodeVerifier` is the PKCE proof of possession.
- `ClientSecret` comes from the vault (Chapter 9 secret hygiene).
- The access token is cached and refreshed only when near expiry.

### Internal Working

- `/authorize` establishes the user's consent and issues an authorization code bound to `code_challenge`.
- `/token` exchanges the code: validates `code_verifier` (PKCE), `redirect_uri`, client credentials, and mints `access_token` (+ `refresh_token`, `id_token` for OIDC).
- Refresh: `/token` with `grant_type=refresh_token`; rotation issues a new pair and revokes the presented token.
- OIDC discovery (`/.well-known/openid-configuration`) exposes endpoints so clients auto-configure.

### Advantages

- Users never share passwords with third-party apps.
- Scoped, least-privilege access.
- Standardized, interoperable (SMART-on-FHIR builds on it).

### Disadvantages

- Complex to implement correctly (must handle PKCE, redirects, rotation).
- Refresh tokens are high-value targets needing secure storage + rotation.
- Multiple grants to master.

### Best Practices

- Always use PKCE for public clients; never a client secret in a SPA.
- Store refresh tokens server-side; enable rotation with replay detection.
- Keep access tokens short-lived (minutes to an hour).
- Validate `nonce` for OIDC `id_token`s.

### Common Mistakes

- Using the implicit grant (deprecated) for SPAs.
- Embedding client secrets in client-side code.
- Ignoring refresh-token rotation → leaked refresh tokens stay valid.
- Accepting an `id_token` as the API access credential (it's identity, not authorization).

### Interview Follow-up Questions

1. Why is PKCE needed for public clients?
2. When do you use client credentials vs authorization code?
3. What does refresh-token rotation protect against?

### Senior Level Talking Points

- "PKCE is non-negotiable for anything a browser or app bundle ships — a client secret there is already compromised."
- "For SMART-on-FHIR, interactive apps get `patient/`/`user/` scopes via code+PKCE; trusted backends get `system/` scopes via client credentials. The grant type *is* the trust boundary."

### Diagram

```mermaid
flowchart LR
    U["User"] --> A["/authorize + code_challenge"]
    A --> LOGIN["Login + consent"]
    LOGIN --> CB["redirect: ?code="]
    CB --> T["/token: code + code_verifier"]
    T --> AT["access_token + refresh_token (rotating)"]
    AT --> API["FHIR API (scopes enforced)"]
    API --> U
```

### Comparison Table

| Grant | Who | Client type | SMART prefix |
|---|---|---|---|
| Auth code + PKCE | User consents | SPA/mobile/native | `patient/`, `user/` |
| Client credentials | No user | Confidential backend | `system/` |
| Refresh token | Renewal | Any (server-held) | same as original |
| Implicit | — | Deprecated | never |

### Memory Trick

**"Code+PKCE for people, client-credentials for machines, refresh for renewal"** — match the grant to the actor.

### Summary

OAuth 2.0 grants define how clients get scoped tokens; OIDC adds identity on top. Authorization code + PKCE (users), client credentials (services), and rotating refresh tokens cover virtually every healthcare integration.

### Interview Confidence Score

**High.** Grants and OIDC are core identity interview topics, and mapping them to SMART-on-FHIR shows applied understanding.

---

## 12.3 Refresh Tokens and Revocation

### Interview Answer (30–45 seconds)

> "Access tokens are short-lived for security; refresh tokens are the long-lived credential that renews them. The modern pattern is **rotation**: every refresh call returns a new access token *and* a new refresh token while invalidating the old one, so a stolen refresh token can only be used once — the second use exposes the replay and the session can be revoked. Revocation itself needs a store: a blacklist of revoked token IDs (`jti`) checked on sensitive operations, or IdP-side revocation endpoints for refresh tokens. For a healthcare API, that means a leaked token is contained within minutes, not hours."

### Detailed Explanation

**Why short access tokens:**
- A stolen access token is valid until `exp` — stateless validation has no recall.
- Shorter lifetime shrinks the blast radius.

**Refresh-token flow with rotation:**

```
client → POST /token (grant_type=refresh_token, refresh_token=T1)
server → validate T1, revoke T1, issue access_token A2 + refresh_token T2
```

- `T1` is invalidated as soon as it's used.
- Replay detection: if `T1` is presented again, it's already revoked → alert (possible theft) → revoke the whole family/session.
- **Refresh-token family:** all descendants of one original token; replay detection terminates the family.

**Where they live:**
- Access tokens: in-memory client; never in persistent browser storage for high-risk apps.
- Refresh tokens: server-side (confidential client) or secure OS keychain (mobile).
- For backend services: stored encrypted in DB or a secure cache, rotated on use.

**Revocation mechanics:**
- **Access tokens:** can't be un-issued once signed; mitigate with short lifetimes + an optional *token-blacklist* (Redis of `jti` values checked by a middleware) for high-risk actions.
- **Refresh tokens:** revoked server-side by design (the token store removes them on use/revocation).

### Real World Example (Healthcare)

A patient portal API issues 15-minute access tokens and 30-day rotating refresh tokens. The FHIR write endpoints (`Observation.write`) additionally check a Redis blacklist of revoked `jti`s, so a compromised session can be cut off immediately rather than waiting out the 15-minute window. Refresh rotation means a replayed refresh token triggers an alert and family revocation.

### Production Code Example

```csharp
// Refresh handler with rotation (authorization server side)
public async Task<RefreshResult> RotateRefreshTokenAsync(string presentedRefreshToken)
{
    var stored = await _tokenStore.FindAsync(presentedRefreshToken);   // hash lookup
    if (stored is null || stored.RevokedAt is not null)
        return RefreshResult.Rejected;                  // unknown or already used

    if (stored.UsedAt is not null)
    {
        // Replay! Revoke the whole family and alert.
        await _tokenStore.RevokeFamilyAsync(stored.FamilyId);
        _logger.LogWarning("Refresh token replay detected for family {FamilyId}", stored.FamilyId);
        return RefreshResult.Rejected;
    }

    var nextToken = GenerateRefreshToken(stored.FamilyId);
    await _tokenStore.MarkUsedAsync(stored, DateTime.UtcNow);          // rotate
    await _tokenStore.SaveAsync(nextToken);

    var accessToken = MintAccessToken(TimeSpan.FromMinutes(15));
    return new RefreshResult(accessToken, nextToken);
}

// Client-side revocation for high-risk operations: blacklist check
public sealed class RevocationCheckMiddleware : IMiddleware
{
    public async Task InvokeAsync(HttpContext context, RequestDelegate next)
    {
        var jti = context.User.FindFirstValue(JwtRegisteredClaimNames.Jti);
        if (jti is not null && await _revocationStore.IsRevokedAsync(jti))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }
        await next(context);
    }
}
```

**Key lines explained:**

- Rotation marks the presented token used and issues a fresh pair.
- Replay detection triggers family revocation + alert — the theft signal.
- Access-token blacklist (checked middleware-side) provides near-real-time revocation for sensitive endpoints.

### Internal Working

- Refresh tokens are opaque (random, high-entropy) and stored hashed — never sent or stored as plaintext-equivalent to the client's own knowledge.
- Rotation requires a token store (Redis/DB) that supports atomic mark-used (compare-and-set to avoid race conditions).
- Access-token blacklists trade statelessness for immediacy — acceptable on sensitive paths only.

### Advantages

- Short-lived access tokens contain leaks.
- Rotation + replay detection surfaces stolen sessions.
- Server-side refresh-token revocation is immediate.

### Disadvantages

- Token stores and atomic rotation add infrastructure and complexity.
- Blacklist checks reintroduce statefulness on chosen paths.
- Replay false-positives (retries) need careful handling (idempotency of refresh).

### Best Practices

- Rotate refresh tokens on every use; revoke the family on replay.
- Store refresh tokens hashed; use atomic updates.
- Blacklist `jti` for high-risk operations only; prefer short lifetimes elsewhere.
- Never persist refresh tokens in browser localStorage.

### Common Mistakes

- Long-lived access tokens (hours) with no revocation path.
- Non-rotating refresh tokens → leaked refresh token works forever.
- Blacklisting every request → scalability hit for marginal benefit.
- Storing refresh tokens in plaintext.

### Interview Follow-up Questions

1. What is refresh-token rotation protecting against?
2. How do you revoke an already-issued access token?
3. Why store refresh tokens hashed?

### Senior Level Talking Points

- "The security model is: stateless for throughput, stateful where it matters. Access tokens stay stateless; rotation gives refresh tokens a short, detectable life; a targeted blacklist covers the rare immediate-revoke need."
- "Replay detection isn't just a guard — it's an intrusion signal. A replayed refresh token is how we learn a session was stolen."

### Diagram

```mermaid
flowchart LR
    C["Client"] --> R["POST /token (refresh_token=T1)"]
    R --> S["Validate + atomically revoke T1"]
    S --> D{"Replayed?"}
    D -- yes --> FAM["Revoke family + alert"]
    D -- no --> ISSUE["Issue A2 (15min) + T2"]
    FAM --> REJ["Rejected"]
    ISSUE --> C
```

### Comparison Table

| Concern | Access token | Refresh token |
|---|---|---|
| Lifetime | Minutes | Days/weeks |
| Validation | Stateless (signature) | Stateful (store) |
| Rotation | N/A | Every use |
| Revocation | Blacklist only | Native/instant |
| Storage | In-memory client | Server-side/secure |

### Memory Trick

**"Short access, rotating refresh, blacklist the extreme"** — the token lifecycle triad.

### Summary

Access tokens are short-lived and stateless; refresh tokens are long-lived, stateful, and must rotate with replay detection. Add targeted `jti` blacklists for immediate revocation on high-risk operations.

### Interview Confidence Score

**High.** Refresh-token rotation is a favorite senior security topic; the replay-detection-as-intrusion-signal insight is memorable.

---

## 12.4 Building and Validating JWTs in .NET

### Interview Answer (30–45 seconds)

> "For validation I use `AddJwtBearer` with `TokenValidationParameters` and `JsonWebTokenHandler` — signature via JWKS, plus issuer/audience/lifetime. For issuing, the modern, supportable approach is not hand-rolling `JwtSecurityTokenHandler` in a random service but standing up a real authorization server: **OpenIddict** (free/open-source) or Duende IdentityServer. That gives you `/token`, `/authorize`, client registration, scopes, refresh-token rotation, and OIDC out of the box. Hand-building JWTs is fine for internal service-to-service tokens, but for anything external, use a real IdP component."

### Detailed Explanation

**Validation stack (.NET):**
- `Microsoft.AspNetCore.Authentication.JwtBearer` — the middleware/scheme.
- `System.IdentityModel.Tokens.Jwt` / `Microsoft.IdentityModel.JsonWebTokens` — token handlers.
- `TokenValidationParameters` — all the switches (Chapter 11.4).
- JWKS via `Authority` auto-discovery, or manual `JwtSecurityTokenHandler` + `JsonWebKeySet`.

**Issuing options:**
1. **OpenIddict** — free, OSS, ASP.NET Core; implements OAuth2/OIDC (authorize, token, userinfo, introspection, revocation), flexible EF Core stores, no license fees. *The pragmatic choice for most .NET teams.*
2. **Duende IdentityServer** — commercial successor to IdentityServer4 (license required), full-featured enterprise.
3. **Hand-rolled `JwtSecurityTokenHandler`** — fine only for internal microservice tokens with a shared signing key; lacks revocation, rotation, client management.

**Hand-rolled validation example (no middleware):**

```csharp
var handler = new JsonWebTokenHandler();
var validationParams = new TokenValidationParameters
{
    ValidIssuer = "https://auth.example.com",
    ValidAudience = "fhir-api",
    IssuerSigningKeys = new[] { rsaPublicKey },
    ValidateLifetime = true,
    ClockSkew = TimeSpan.FromSeconds(30),
    ValidAlgorithms = new[] { SecurityAlgorithms.RsaSha256 }   // algorithm allow-list
};

var result = handler.ValidateToken(jwt, validationParams);
if (result.IsValid)
    var principal = result.ClaimsIdentity;
```

**OpenIddict minimal setup:**

```csharp
builder.Services.AddOpenIddict()
    .AddCore(o => o.UseEntityFrameworkCore().UseDbContext<AuthDbContext>())
    .AddServer(o =>
    {
        o.AllowAuthorizationCodeFlow().RequirePkce();
        o.AllowClientCredentialsFlow();
        o.SetTokenEndpointUris("/connect/token");
        o.AddEphemeralSigningKey();              // dev; persist a real key in prod
        o.UseAspNetCore().EnableTokenEndpointPassthrough();
    })
    .AddValidation();
```

### Real World Example (Healthcare)

A hospital's FHIR authorization server is an ASP.NET Core service using OpenIddict: it registers SMART client apps, enforces PKCE, mints RS256 tokens with `patient/` scopes, rotates refresh tokens, and exposes OIDC discovery — everything the FHIR resource server's JWT bearer scheme needs. A separate lab integration uses the same server's client-credentials grant with `system/` scopes.

### Production Code Example

```csharp
// Validation with explicit algorithm allow-list (defends algorithm confusion)
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://auth.example.com";
        options.Audience = "fhir-api";
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            ValidAlgorithms = new[] { SecurityAlgorithms.RsaSha256 }
        };
    });
```

**Key lines explained:**

- `ValidAlgorithms` allow-lists RS256 — blocks HS256 confusion attacks.
- Everything else (JWKS fetch, key caching) comes from `Authority`.
- This is the resource-server side; the issuer is OpenIddict/IdP.

### Internal Working

- The bearer scheme uses `JsonWebTokenHandler` (net6+ default) for validation — faster than the older `JwtSecurityTokenHandler`.
- JWKS keys are cached and refreshed via `ConfigurationManager` when the `kid` is unknown.
- OpenIddict stores clients, scopes, and tokens in EF Core; token endpoints are OIDC-conformant.

### Advantages

- Battle-tested validation; automatic key discovery/rotation.
- OpenIddict gives a full OAuth2/OIDC server without reinventing it.
- Algorithm allow-listing closes real attack classes.

### Disadvantages

- OpenIddict has a learning curve (server vs validation vs core APIs).
- Hand-rolled tokens lack lifecycle features — not for external use.
- Token library surface has legacy and modern APIs to keep straight.

### Best Practices

- Use `JsonWebTokenHandler`/`ValidAlgorithms` (modern, hardened).
- Prefer OpenIddict/Duende for issuing; never hand-roll for external clients.
- Persist OpenIddict signing keys in prod; use ephemeral only in dev.
- Validate everything, allow-list algorithms.

### Common Mistakes

- Using the legacy `JwtSecurityTokenHandler` path when the modern one is available.
- No `ValidAlgorithms` → algorithm-confusion exposure.
- Hand-rolling JWTs for third-party/partner clients (no rotation/revocation).
- Ephemeral signing keys in production → tokens invalid on restart.

### Interview Follow-up Questions

1. OpenIddict vs hand-rolled tokens — when is each right?
2. What does `ValidAlgorithms` protect against?
3. `JsonWebTokenHandler` vs `JwtSecurityTokenHandler`?

### Senior Level Talking Points

- "Issuing tokens is an identity-platform responsibility; I reach for OpenIddict before any hand-rolled token code because the lifecycle features — rotation, revocation, client management — are where the security actually lives."
- "The modern handler plus algorithm allow-listing is the minimum viable token defense; everything else is lifecycle management."

### Diagram

```mermaid
flowchart LR
    ISSUER["OpenIddict server"] --> TOK["JWT RS256 (kid, iss, aud, exp, scope)"]
    TOK --> RES["Resource server: AddJwtBearer"]
    RES --> P1["Validate sig via JWKS (kid)"]
    RES --> P2["Validate iss/aud/lifetime"]
    RES --> P3["Allow-list algorithms"]
    RES --> AZ["Authorization: scope policies"]
```

### Comparison Table

| Approach | Rotation/revoke | Client mgmt | License | Use |
|---|---|---|---|---|
| OpenIddict | Yes | Yes | OSS | Recommended default |
| Duende IdentityServer | Yes | Yes | Commercial | Enterprise needs |
| Hand-rolled | No | No | — | Internal microservice tokens only |

### Memory Trick

**"Validate with the modern handler, issue with a real server"** — the .NET token toolkit rule.

### Summary

Validate with `JsonWebTokenHandler` + full `TokenValidationParameters` + algorithm allow-list; issue via OpenIddict/Duende, not hand-rolled tokens, except for internal-only microservice tokens.

### Interview Confidence Score

**Medium-High.** Expect "how would you implement JWT auth" — the validation details plus the OpenIddict choice show production judgment.

---

## 12.5 Token Storage, Cookie vs. Header, and Client Security

### Interview Answer (30–45 seconds)

> "Where tokens live is a security decision. For SPAs, the safest place for an access token is memory only — an `Authorization: Bearer` header on API calls, never `localStorage` (XSS can read it). The common alternative is a SameSite `HttpOnly` cookie session (via BFF — backend for frontend) where the browser never sees the token at all. Refresh tokens never belong in the browser: they live server-side or in a device keychain. For .NET APIs I always read the bearer header; the classic exception is SignalR/gRPC where the header isn't available, and I read the token from the query string via `OnMessageReceived` — knowing it leaks into logs, so it's mitigated by short lifetimes and careful logging."

### Detailed Explanation

**Token storage options:**

| Location | XSS risk | CSRF risk | Suitable for |
|---|---|---|---|
| `localStorage` | High (JS-readable) | Low | Not recommended |
| `sessionStorage` | High | Low | Not recommended |
| In-memory (JS var) | Low (not persisted) | Low | SPAs (tokens die on reload) |
| `HttpOnly` cookie (BFF) | None (JS can't read) | Medium (mitigate SameSite) | SPA + BFF pattern |
| Server/keychain | None | n/a | Refresh tokens, native apps |

**The BFF (Backend for Frontend) pattern:**
- SPA talks to its own backend; the backend holds the OAuth tokens and forwards API calls with them.
- The browser only holds a session cookie; access/refresh tokens never touch JS.
- Recommended by the .NET team (`Microsoft.AspNetCore.Bff` middleware) for secure SPAs.

**SignalR/gRPC token transport:**
- Headers aren't settable from the browser WebSocket/SSE → token via query string (`access_token=...`).
- Mitigations: `OnMessageReceived` reads it, log it carefully (URLs appear in logs), keep lifetime short, require the endpoint to be HTTPS, and consider cookies/BFF instead.

**Access token handling in .NET:**

```csharp
// SignalR: token in query string, via OnMessageReceived
options.Events = new JwtBearerEvents
{
    OnMessageReceived = ctx =>
    {
        var accessToken = ctx.Request.Query["access_token"];
        if (!string.IsNullOrEmpty(accessToken) &&
            ctx.HttpContext.Request.Path.StartsWithSegments("/hubs/clinical"))
        {
            ctx.Token = accessToken;
        }
        return Task.CompletedTask;
    }
};
```

### Real World Example (Healthcare)

A clinical dashboard SPA uses the BFF pattern: the user authenticates with the IdP through the .NET backend, which stores tokens server-side and sets an `HttpOnly` SameSite cookie. The browser sends the cookie on every API call; the BFF injects the bearer token. Clinician tokens never exist in JavaScript memory or storage — the XSS surface on PHI-bearing data is minimal.

### Production Code Example

```csharp
// BFF: forward the user's access token on outbound calls
public sealed class TokenForwardingHandler : DelegatingHandler
{
    private readonly IUserAccessTokenStore _tokens;
    public TokenForwardingHandler(IUserAccessTokenStore tokens) => _tokens = tokens;

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken ct)
    {
        var accessToken = await _tokens.GetTokenAsync();
        if (!string.IsNullOrEmpty(accessToken))
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", accessToken);
        return await base.SendAsync(request, ct);
    }
}

// Registered as a typed-client handler
builder.Services.AddHttpClient<IClinicalApiClient, ClinicalApiClient>()
    .AddHttpMessageHandler<TokenForwardingHandler>();
```

**Key lines explained:**

- The BFF holds the token; the browser holds only the session cookie.
- Token forwarding is centralized in one handler — no token handling in the SPA.
- The `HttpClient` handler pattern reuses this across all API calls.

### Internal Working

- BFF middleware (`Microsoft.AspNetCore.Bff`) manages session management and token storage server-side.
- `HttpOnly` + `SameSite=Strict/Lax` cookies block JS reads and cross-site sends.
- Query-string token reads (SignalR) risk log leakage — hence short lifetimes and scrubbed request logging (Chapter 10).

### Advantages

- BFF removes the XSS token-theft class for SPAs.
- Header-based API auth is clean and standard.
- Centralized forwarding is testable and auditable.

### Disadvantages

- BFF adds a hop (browser → BFF → API) and server-side token storage.
- SignalR/gRPC query-string tokens are inherently leak-prone.
- Cookie + API hybrid needs careful CSRF handling.

### Best Practices

- Never store tokens in `localStorage`/`sessionStorage` for PHI apps.
- Prefer BFF + `HttpOnly` cookie for SPAs.
- Read tokens from headers; use `OnMessageReceived` only where needed (SignalR/gRPC) with mitigations.
- Store refresh tokens server-side or in a secure keychain.

### Common Mistakes

- `localStorage` tokens → XSS exfiltration of PHI.
- Refresh token in the SPA bundle.
- Query-string tokens without scrubbing request logs.
- Forgetting CSRF mitigation when mixing cookies with APIs.

### Interview Follow-up Questions

1. Why is `localStorage` risky for tokens?
2. What is the BFF pattern and why does it exist?
3. How do you authenticate a SignalR hub?

### Senior Level Talking Points

- "For PHI-bearing apps, the browser should never see the token: BFF + HttpOnly cookie is the answer, because XSS defenses are not a strategy."
- "Every token transport has a risk profile; header is cleanest, query string for real-time is leak-prone, so I pair it with short lifetimes and scrubbed logging."

### Diagram

```mermaid
flowchart LR
    SPA["SPA (no tokens)"] -->|HttpOnly cookie| BFF["BFF (holds tokens)"]
    BFF -->|Bearer header| API["FHIR API"]
    IDP["IdP"] --> BFF
```

### Comparison Table

| Storage | XSS risk | CSRF risk | Where |
|---|---|---|---|
| In-memory (SPA) | Low | Low | Browser JS |
| HttpOnly cookie (BFF) | None | Low–med | Browser + backend |
| localStorage | High | Low | Avoid |
| Server / keychain | None | n/a | Refresh tokens |

### Memory Trick

**"BFF keeps tokens out of the browser"** — the one-line SPA security story.

### Summary

Token storage determines the attack surface: memory or BFF cookies for SPAs, headers for APIs, server/keychain for refresh tokens, and `OnMessageReceived` only where headers aren't possible. Never `localStorage`.

### Interview Confidence Score

**High.** Token-storage and BFF questions are increasingly common, especially for PHI apps. The security reasoning is the differentiator.

---

## 12.6 Common JWT/OAuth Attacks and Defenses

### Interview Answer (30–45 seconds)

> "The attacks I defend against: **algorithm confusion** (forcing HS256 with a public key), **token replay** (reusing a stolen token), **token theft via XSS** (localStorage), **CSRF** (browser sending the cookie), **weak signing secrets**, and **overly long lifetimes**. Defenses map directly: allow-list algorithms, validate `kid`/issuer/audience, short lifetimes + rotation + blacklists, BFF/HttpOnly cookies, strong secrets from vaults, and constant-time verification (which the libraries do). In healthcare the stakes are PHI exposure and compliance findings, so I treat each as a review checklist item."

### Detailed Explanation

**The attacks:**

1. **Algorithm confusion (RS256→HS256):**
   - Attacker swaps `alg` to `HS256` and signs with the *public* key (which everyone knows) as the HMAC secret.
   - Defense: `ValidAlgorithms` allow-list; reject `alg: none`; validate `kid`.

2. **Token replay:**
   - Reusing a valid captured token.
   - Defense: short `exp`, `jti`, refresh rotation, optional blacklist for sensitive ops.

3. **Token theft (XSS):**
   - JS steals tokens from `localStorage`.
   - Defense: never store tokens in JS-accessible storage; BFF + HttpOnly cookie.

4. **CSRF:**
   - Browser auto-sends cookies → cross-site request with the victim's session.
   - Defense: `SameSite`, anti-forgery tokens, `Origin` checks; bearer headers are immune (not auto-sent).

5. **Weak/leaked signing secrets:**
   - HS256 with a guessable secret → forge any token.
   - Defense: high-entropy secrets in vaults, rotation, prefer asymmetric for external.

6. **Lifetime abuse:**
   - Long-lived access tokens enlarge the theft window.
   - Defense: minutes-scale access tokens, rotating refresh tokens.

**Verification hygiene:**
- Use constant-time comparison (handled by `Microsoft.IdentityModel`).
- Validate `nbf`/`exp`; reject clock-skew abuse.
- Scope claims enforced as authorization, never trusted blindly.

### Real World Example (Healthcare)

During a review, a security team flags that a FHIR integration accepts tokens with any `alg` and a 2-hour lifetime, stored by the SPA in `localStorage`. The fixes: `ValidAlgorithms = ["RS256"]`, access-token lifetime cut to 15 minutes with rotating refresh tokens, SPA moved to BFF + HttpOnly cookie, and the signing key moved from a config file to the vault.

### Production Code Example

```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = "https://auth.example.com";
        options.Audience = "fhir-api";
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuers = new[] { "https://auth.example.com" },
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.FromSeconds(30),
            ValidAlgorithms = new[] { SecurityAlgorithms.RsaSha256 },   // block HS256 confusion
            NameClaimType = ClaimTypes.Name,
            RoleClaimType = ClaimTypes.Role
        };
    });
```

**Key lines explained:**

- `ValidAlgorithms` closes the confusion attack.
- Explicit `ValidIssuers` prevents cross-tenant tokens.
- `NameClaimType`/`RoleClaimType` make `User.Identity.Name`/`IsInRole` work from the token claims.

### Internal Working

- The token handler enforces allowed algorithms during signature verification, so a forged `alg: HS256` header fails immediately.
- `kid` mismatches trigger JWKS refresh (not key fallback) — closing key-confusion.
- Clock-skew is bounded; `nbf` and `exp` are both validated.

### Advantages

- Each defense is cheap to configure and testable.
- The checklist covers OWASP-relevant token issues.
- Libraries provide constant-time crypto natively.

### Disadvantages

- Configuration errors (one switch off) silently reopen an attack.
- Rotation/blacklists add state and complexity.
- BFF adds architecture weight.

### Best Practices

- Allow-list algorithms; reject `alg: none`.
- Validate all claims; keep `ClockSkew` small.
- Short access tokens; rotating refresh tokens.
- Vault-managed secrets; rotate keys; use asymmetric for external.

### Common Mistakes

- `ValidateAudience = false` (cross-API replay).
- No `ValidAlgorithms` (confusion attacks).
- Tokens in `localStorage` (XSS exfiltration).
- Reusing the same symmetric secret across services.

### Interview Follow-up Questions

1. Walk me through an algorithm-confusion attack and its fix.
2. How do you defend against token replay?
3. Why do bearer tokens not have the CSRF problem cookies do?

### Senior Level Talking Points

- "Security reviews of token code are checklist-driven: algorithms allow-listed, claims all validated, lifetimes short, storage BFF-only, secrets in vaults. I audit those five things on every integration."
- "The most damaging token bugs aren't crypto — they're configuration and storage. The fix is architecture (BFF), not a stronger hash."

### Diagram

```mermaid
flowchart LR
    A1["Alg confusion"] --> D1["ValidAlgorithms allow-list"]
    A2["Replay"] --> D2["Short exp + rotation + blacklist"]
    A3["XSS theft"] --> D3["BFF + HttpOnly cookie"]
    A4["CSRF"] --> D4["SameSite / anti-forgery"]
    A5["Weak secret"] --> D5["Vault + rotation + asymmetric"]
    A6["Long lifetime"] --> D6["Minutes + rotating refresh"]
```

### Comparison Table

| Attack | Vector | Primary defense |
|---|---|---|
| Algorithm confusion | Forged `alg` | `ValidAlgorithms` |
| Replay | Stolen token reuse | Short life + rotation |
| XSS theft | JS reads storage | BFF/HttpOnly cookie |
| CSRF | Auto-sent cookie | SameSite/anti-forgery |
| Weak secret | Forge with guess | Vault, high entropy |
| Lifetime | Extended window | Short access tokens |

### Memory Trick

**"Allow, validate, short, BFF, vault"** — the five-part token defense: algorithms, claims, lifetimes, storage, secrets.

### Summary

Token security is mostly configuration and architecture: allow-list algorithms, validate all claims, keep lifetimes short with rotation, store tokens out of JS reach, and protect secrets in vaults.

### Interview Confidence Score

**High.** Attack/defense questions are a senior staple and map beautifully onto healthcare security requirements.

---

## 12.7 OAuth 2.0 / OIDC in Practice for Healthcare (SMART + B2B)

### Interview Answer (30–45 seconds)

> "In practice, healthcare integrations split into two worlds: **patient/clinical apps** (SMART-on-FHIR) using authorization code + PKCE with `patient/`/`user/` scopes, and **B2B system integrations** (lab, pharmacy, payer) using client credentials with `system/` scopes. The .NET implementation has three layers: a token *issuer* (OpenIddict/Duende), a token *validator* on each FHIR resource server (JWT bearer + scope policies), and an *enforcement* layer that maps SMART scopes to FHIR operations. I also design for auditability: every token grant, scope, and revocation is logged, because interoperability reviews and HIPAA audits both demand a defensible access trail."

### Detailed Explanation

**The three layers:**

1. **Issuer (authorization server):** OpenIddict service — registers clients, grants consent, mints RS256 tokens, rotates refresh tokens, exposes discovery.
2. **Validator:** `AddJwtBearer` on FHIR servers — cryptographically verifies and binds `aud` to the FHIR base URL.
3. **Enforcement:** SMART scope handler (Chapter 11.8) — maps `patient/Observation.read` to the actual endpoint permission.

**B2B specifics (client credentials):**
- Register each partner system as a confidential client with a `client_secret` (or client certificate/mTLS).
- Grant narrow `system/` scopes; rotate secrets.
- `aud` still the FHIR base URL; the token's `sub` identifies the partner system.

**Auditability:**
- Log: client ID, grant type, scopes granted, token issuance, refresh events, revocations.
- Retain per compliance policy; correlation with access logs (Chapter 10).
- Optionally use token introspection (`/introspect`) for coarse "is this token still valid" checks.

**Discovery and registration:**
- OIDC discovery metadata for clients to auto-configure.
- SMART app registration: register `redirect_uris`, scopes, launch contexts.

### Real World Example (Healthcare)

The hospital runs OpenIddict as its FHIR authorization server. A patient app registers via SMART, gets `patient/Observation.read`, uses code+PKCE. A reference-lab integration registers as a confidential client with `system/Observation.write system/Patient.read` via client credentials. The FHIR resource server's scope handler enforces both; every grant and refresh is audit-logged. A payer integration review asks "who can write observations and how?" — the answer is one query of the authorization server's audit trail.

### Production Code Example

```csharp
// Client-credentials token acquisition for a B2B integration (lab system)
var response = await client.RequestClientCredentialsTokenAsync(new()
{
    Address = "https://auth.example.com/connect/token",
    ClientId = "reference-lab",
    ClientSecret = await vault.GetSecretAsync("reference-lab-secret"),
    Scope = "system/Observation.write system/Patient.read"
});

// The FHIR server enforces via SMART scope handler (Chapter 11.8)
app.MapPost("/fhir/Observation", CreateObservation)
   .RequireAuthorization("SmartObservationWrite");

options.AddPolicy("SmartObservationWrite", policy =>
    policy.AddRequirements(new SmartScopeRequirement("Observation", "write")));
```

**Key lines explained:**

- Client secret fetched from the vault at runtime — never baked into the lab client config.
- Scopes are narrow (`Observation.write`, `Patient.read`), least privilege.
- Enforcement is declarative per endpoint — reviewable against the partner's contract.

### Internal Working

- The authorization server authenticates the confidential client, checks scope entitlements, and mints a token with `aud = FHIR base URL` and `scope` claim.
- FHIR servers validate the token and enforce scopes; introspection available for coarse validity checks.
- Audit events are written by the issuer and resource servers and correlated by `jti`/correlation ID.

### Advantages

- One standards-based access model for all partners.
- Least-privilege scopes per partner contract.
- Full audit trail supports reviews and HIPAA-style accountability.

### Disadvantages

- Operating an authorization server is a real platform responsibility.
- Partner onboarding (registration, scope negotiation) needs process.
- Debugging cross-organization token issues requires good tooling.

### Best Practices

- Register partners as confidential clients with narrow scopes; rotate secrets.
- Bind `aud` to the FHIR base URL everywhere.
- Audit every grant/refresh/revocation; correlate with resource access logs.
- Use discovery documents for client onboarding.

### Common Mistakes

- Over-broad `system/*.*` scopes "to keep it simple."
- No audit trail for token issuance → can't answer "who could access what."
- Skipping secret rotation for long-lived partner clients.

### Interview Follow-up Questions

1. How do you onboard a new partner system securely?
2. What belongs in the authorization audit trail?
3. `system/` vs `patient/` scopes — when is each appropriate?

### Senior Level Talking Points

- "The authorization server's audit trail is the answer to every 'who can access PHI and how' question — I design for that before I design for anything else."
- "Least privilege is a contract, not a default: each partner's scopes are negotiated and enforced at both the token layer and the endpoint layer."

### Diagram

```mermaid
flowchart LR
    IDP["OpenIddict (issuer)"] -->|tokens| RS["FHIR resource servers (validator)"]
    RS --> ENF["Scope enforcement (policies)"]
    APP["Patient app (code+PKCE, patient/*)"] --> IDP
    LAB["Lab system (client creds, system/*)"] --> IDP
    IDP --> AUD["Audit trail (grants, refreshes, revocations)"]
```

### Comparison Table

| Integration | Grant | Scopes | Trust |
|---|---|---|---|
| Patient app | Code + PKCE | `patient/`, `user/` | User consent |
| Clinician app | Code + PKCE | `user/` | User consent |
| Lab/partner | Client credentials | `system/` | Registered secret/mTLS |
| Payer/analytics | Client credentials | `system/` read-only | Registered secret |

### Memory Trick

**"Issuer, validator, enforcer — and audit everything"** — the healthcare token architecture.

### Summary

Production healthcare auth is a three-layer stack — issuer (OpenIddict), validator (JWT bearer), enforcer (SMART scope policies) — with scopes as per-partner contracts and a complete audit trail. Speak this architecture fluently.

### Interview Confidence Score

**High (healthcare).** The SMART + B2B integration architecture, with audit, is the most valuable senior answer in this chapter for a healthcare role.

---

## Chapter 12 Wrap-Up

### Top 10 Questions You Should Be Ready For

1. What is a JWT and what's inside it?
2. RS256 vs HS256 — when do you use which?
3. What are the OAuth 2.0 grants and when do you use each?
4. How does OpenID Connect extend OAuth?
5. Why is PKCE required for public clients?
6. What is refresh-token rotation and what does it protect?
7. How do you revoke an access token?
8. How do you build and validate JWTs in .NET?
9. Where should tokens be stored (and why not localStorage)?
10. What are the common JWT/OAuth attacks and defenses?

### Revision Notes (1 page)

- **JWT:** header.payload.signature; signed not encrypted; claims `iss/aud/exp/nbf/sub` + custom (`scope`, `fhirUser`); never PHI in payload; base64url.
- **Algorithms:** RS256 = asymmetric, JWKS, standard for OAuth/OIDC; HS256 = shared secret, same-trust only; allow-list algorithms to block confusion.
- **Grants:** auth code + PKCE for interactive (users), client credentials for machines, refresh for renewal. OIDC adds `id_token` + userinfo (identity on top of access).
- **Rotation:** every refresh issues a new pair and revokes the old; replay detection → family revocation + alert. Access tokens short-lived; targeted `jti` blacklist for immediate revoke on sensitive ops.
- **.NET:** validate with `AddJwtBearer` + `TokenValidationParameters` + `ValidAlgorithms`; issue with OpenIddict/Duende, not hand-rolled (except internal-only).
- **Storage:** BFF + HttpOnly cookie for SPAs; header for APIs; server/keychain for refresh; never localStorage; SignalR/gRPC query-string tokens need short lifetimes + scrubbed logging.
- **Attacks/defenses:** algorithm confusion → allow-list; replay → short life + rotation; XSS theft → BFF; CSRF → SameSite/anti-forgery; weak secrets → vault; long lifetime → minutes.
- **Healthcare:** issuer (OpenIddict) → validator (JWT bearer) → enforcer (SMART scope policies); `system/` for B2B via client credentials; audit every grant/refresh/revocation.

### Things Interviewers Expect From 5+ Years Experience

- JWT internals explained precisely (not just "it's a token").
- Grant selection justified per actor (user vs machine).
- Refresh rotation + replay detection as the *default* design.
- Real .NET specifics: `ValidAlgorithms`, `JsonWebTokenHandler`, OpenIddict.
- Token storage security reasoning (BFF over localStorage).
- The healthcare architecture: issuer → validator → enforcer + audit trail.

### Cheat Sheet

```
JWT = header.payload.signature  (signed, NOT encrypted → no PHI)
CLAIMS: iss, aud, exp, nbf, sub, iat, jti + custom (scope, fhirUser)

ALGORITHMS:
  RS256 → asymmetric, JWKS, external/OAuth standard
  HS256 → shared secret, internal same-trust only
  ALWAYS: ValidAlgorithms = ["RS256"] (kills alg-confusion)

GRANTS:
  Auth code + PKCE → interactive apps (patient/, user/)
  Client credentials → B2B services (system/)
  Refresh token → renewal, ROTATE + replay-detect → revoke family

.NET:
  Validate: AddJwtBearer + TokenValidationParameters (S.I.A.L + allow-list)
  Issue:    OpenIddict (OSS) or Duende (commercial)
  Hand-roll JWTs ONLY for internal service-to-service

STORAGE:
  SPA   → BFF + HttpOnly SameSite cookie (never localStorage!)
  API   → Authorization: Bearer header
  Refresh → server-side / keychain
  SignalR/gRPC → OnMessageReceived (short life + scrub logs)

ATTACKS → DEFENSES:
  alg confusion → allow-list      replay → short life + rotation
  XSS theft → BFF                 CSRF → SameSite/anti-forgery
  weak secret → vault             long lifetime → minutes

HEALTHCARE STACK: issuer(OpenIddict) → validator(bearer)
  → enforcer(SMART scopes) + AUDIT everything
```

### Flash Cards

**Q1:** Three JWT segments? **A:** header, payload, signature.

**Q2:** RS256 vs HS256? **A:** Asymmetric (JWKS, standard) vs shared secret (internal only).

**Q3:** Why no PHI in JWT? **A:** Payload is signed, not encrypted — readable by anyone.

**Q4:** Auth code + PKCE for whom? **A:** Interactive user-facing apps.

**Q5:** Client credentials for whom? **A:** Machine-to-machine (B2B, `system/` scopes).

**Q6:** What does rotation detect? **A:** Refresh-token replay → family revocation + alert.

**Q7:** How to revoke an access token? **A:** Short lifetime + `jti` blacklist on sensitive ops (stateless tokens can't be recalled).

**Q8:** SPA token storage? **A:** BFF + HttpOnly cookie; never localStorage.

**Q9:** Algorithm-confusion fix? **A:** `ValidAlgorithms` allow-list (e.g., `["RS256"]`).

**Q10:** OpenIddict is what? **A:** OSS OAuth2/OIDC server for .NET.

**Q11:** `aud` in SMART tokens? **A:** The FHIR base URL.

**Q12:** B2B SMART scope example? **A:** `system/Observation.write system/Patient.read`.

**Q13:** Why short access tokens? **A:** Stateless = no recall; shorter window shrinks theft blast radius.

**Q14:** What makes bearer tokens CSRF-resistant? **A:** They're not auto-sent by the browser like cookies.

### Interview Confidence Score

**High.** JWT/OAuth topics are universally asked and this chapter covers the full arc — token anatomy, grants, rotation, .NET implementation, storage security, attacks, and the healthcare (SMART/B2B) architecture. Expect 2–4 questions from this chapter in most interviews.

---

*Continue → Chapter 13: Entity Framework Core*
