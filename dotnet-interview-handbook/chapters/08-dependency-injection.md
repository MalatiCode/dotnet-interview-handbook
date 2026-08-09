# Chapter 8: Dependency Injection

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** Why DI, lifetimes (transient/scoped/singleton) and their traps, the built-in container vs. third-party containers, composition root, captive dependencies, `IOptions<T>`, factory patterns, decorators, DI in tests, and common mistakes (service locator, disposal, captive singletons).

---

## 8.1 Dependency Injection Fundamentals

### Interview Answer (30–45 seconds)

> "Dependency Injection is the mechanism that realizes the Dependency Inversion Principle: a class receives its dependencies (via constructor, property, or method) instead of creating them. In ASP.NET Core, the container builds the object graph from the composition root in `Program.cs`; a service's constructor parameters are resolved recursively. The payoff: testability (swap fakes), decoupling (swap implementations without touching consumers), and central lifecycle management. My rule: constructor injection for required collaborators, `IOptions<T>` for configuration, and an explicit composition root — never a service locator scattered through the code."

### Detailed Explanation

**The three injection styles:**

- **Constructor injection (preferred):** dependencies as constructor parameters. Required, explicit, testable.
- **Property injection:** settable properties for *optional* dependencies (rare; needs container support).
- **Method injection:** passing a dependency into a specific method (e.g., `HttpContext` into an action).

**The container:**

- Registration: `builder.Services.AddScoped<IPatientRepository, SqlPatientRepository>();`.
- Resolution: at the composition root, the container instantiates the requested type, resolving its constructor dependencies recursively.
- The *composition root* is the single place where the wiring happens (in `Program.cs`/`Startup`). Everything above it only *uses* the graph.

**Why DI wins:**

- Testability: constructor injection + interfaces = mocks/fakes without touching the class.
- Loose coupling: swap `SqlRepository` → `InMemoryRepository` by changing one registration.
- Lifecycle: the container tracks and disposes registered `IDisposable`s per lifetime.
- Discoverability: constructor signatures are the dependency contract.

**DI vs DIP vs IoC:**

- DIP — the *principle* (depend on abstractions).
- IoC (Inversion of Control) — the *concept* (the framework calls your code; you don't wire yourself).
- DI — the *technique* delivering DIP.
- A DI *container* — the tool that automates wiring.

**Anti-patterns:**

- **Service locator** — `ServiceProvider.GetService<T>()` scattered in code → hidden dependencies, hard to test, hard to reason about.
- **Ambient context** — static service access (`Current`, `Logger.Instance`).
- **`new` everywhere** — manually constructing dependencies in classes (breaking the pattern).

### Real World Example (Healthcare)

```csharp
// Dependency inverted: high-level processor depends on abstractions
public sealed class OrderProcessor
{
    private readonly IMedicationValidation _validation;
    private readonly IOrderRepository _repository;
    private readonly IAuditLogger _audit;

    public OrderProcessor(IMedicationValidation validation,
                          IOrderRepository repository,
                          IAuditLogger audit)
    {
        _validation = validation;
        _repository = repository;
        _audit = audit;
    }
}
```

Registered in `Program.cs`, replaced in tests with fakes — zero changes to `OrderProcessor`.

### Production Code Example

```csharp
// Composition root (Program.cs / web builder)
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddScoped<IPatientRepository, SqlPatientRepository>();
builder.Services.AddScoped<IMedicationValidation, MedicationValidationService>();
builder.Services.AddSingleton<IAuditLogger, SerilogAuditLogger>();
builder.Services.AddSingleton<ITimeProvider, TimeProvider.System>();   // testable clock

var app = builder.Build();
// ... pipeline ...
app.Run();
```

**Key lines explained:**

- Registrations map interface → implementation; lifetimes chosen deliberately (see 8.2).
- `ITimeProvider` injected — deterministic time in tests.
- This is the *only* place wiring happens; handlers/controllers just declare constructor params.

### Internal Working

- The built-in container (`ServiceProvider`) walks the constructor (longest by default) and resolves each parameter by consulting the registration table, constructing dependencies recursively.
- It builds a compiled `CallSiteFactory` + `CallSite` tree on first resolve (fast path after warm-up).
- Validation (`ValidateOnBuild`/`ValidateScopes`) catches misconfiguration at startup in Development.

### Advantages

- Testability, decoupling, central lifecycle/disposal, explicit dependencies.

### Disadvantages

- Indirection (extra abstractions); misconfig surfaces at runtime; over-engineering risk; container complexity.

### Best Practices

- Constructor injection as the default; `IOptions<T>` for config; explicit composition root.
- Register by abstraction, resolve by abstraction.
- Keep dependencies visible: no service locator, no ambient singletons.
- Use `ValidateOnBuild`/`ValidateScopes` in Development.

### Common Mistakes

- Service locator everywhere (hard to test).
- Property injection for required dependencies.
- Resolving from the container mid-request (should use `IServiceScopeFactory`).
- Registering a dependency with the wrong lifetime (see captive dependency, 8.3).

### Interview Follow-up Questions

1. Constructor vs. property injection? (Constructor for required; property for optional.)
2. What is the composition root? (The single wiring point.)
3. Service locator vs. DI — why is the locator an anti-pattern? (Hidden deps, testability.)
4. What does the container do at startup in Development? (ValidateOnBuild/ValidateScopes.)

### Senior Level Talking Points

> "DI is where architecture meets operational reality: the container is not magic, it's a *registry of lifetimes*. The senior discipline is the composition root — if I see `GetService` inside business code, I know a refactor is coming. And the killer question is always 'what lifetime and why?' because a wrong lifetime is a subtle production bug: a captive `DbContext`, a singleton that captured a scoped logger, a transient that keeps a giant cache alive."

### Memory Trick

**"Give the class its tools at the door (constructor), not by rummaging the whole building (locator)."**

---

## 8.2 Lifetimes: Transient, Scoped, Singleton

### Interview Answer (30–45 seconds)

> "Transient is created *every time it's requested* — a new instance per injection; cheapest to think about, but no sharing. Scoped is one instance per request scope — the default for `DbContext` and request-bound services; it lives for the request's lifetime and is disposed at its end. Singleton is one instance for the app's lifetime — shared and disposed at shutdown; great for stateless services and caches. The traps: a *captive dependency* — a longer-lived service holding a shorter-lived one (a singleton holding a scoped `DbContext`) — freezes the scoped service's state forever; and singletons with state need thread-safety. My rule: stateless services → singleton; per-request state/DbContext → scoped; cheap throwaway utilities → transient."

### Detailed Explanation

**The three lifetimes:**

| Lifetime | Instances | Disposal | Use for |
|---|---|---|---|
| Transient | 1 per resolve | each | cheap stateless, no sharing |
| Scoped | 1 per scope | scope end | DbContext, per-request state |
| Singleton | 1 per app | shutdown | stateless services, caches, clients |

**Transient:**

- `AddTransient<T>()` — every resolution constructs a new instance.
- Stateless = safe; holding per-request data = useless.
- Disposal: every resolved instance is tracked & disposed when the scope dies.
- Overhead: more allocations.

**Scoped:**

- One instance per `IServiceScope` — in a web request, per request.
- `DbContext` MUST be scoped (per-request) for change-tracking correctness.
- Disposed at the end of the request/scope.
- Registered as `AddScoped<T>()`.

**Singleton:**

- One instance for the lifetime of the container/application.
- **Thread-safety required** if it holds mutable state (concurrent access from all requests).
- Constructed once (lazily on first use by default, or eagerly via options).
- Disposed when the app shuts down.
- `HttpClient` via `IHttpClientFactory` is effectively a managed singleton-per-named-client — reuse connections, avoid socket exhaustion.

**Captive dependency (the big trap):**

- A singleton that injects a scoped service, or a scoped that injects a transient it keeps forever.
- The singleton captures one scoped instance → it's frozen: state from the first request persists for all requests (e.g., a `DbContext` shared across all requests = corrupt change tracking + thread-safety disaster).
- The container *can't always* detect this at runtime (scoped-from-singleton is a common silent bug; .NET 8 added detection via `ValidateScopes` in Development and warnings for some cases).
- Fix: inject `IServiceScopeFactory` and create a scope per operation, or change the design.

**Other patterns:**

- `AddKeyedSingleton/AddKeyedScoped/AddKeyedTransient` (.NET 8) — `[FromKeyedServices("sql")]` selection.
- Factory registration: `AddSingleton<IFactory>(sp => new Factory(sp.GetRequiredService<...>()))` — explicit factory func.
- `AddSingleton<ITimeProvider, TimeProvider.System>()` — stateless singleton.

### Real World Example (Healthcare)

```csharp
builder.Services.AddScoped<AppDbContext>();                    // per-request context
builder.Services.AddScoped<IPatientRepository, SqlPatientRepository>();
builder.Services.AddSingleton<IAlertRulesRegistry, AlertRulesRegistry>();   // stateless rules
builder.Services.AddSingleton<ILoggerFactory, ...>();          // framework singleton
```

### Production Code Example

```csharp
// CORRECT: singleton service using a scoped DB per operation
public sealed class PatientAuditService
{
    private readonly IServiceScopeFactory _scopeFactory;

    public PatientAuditService(IServiceScopeFactory scopeFactory)
        => _scopeFactory = scopeFactory;

    public async Task AuditAsync(Guid patientId, string action, CancellationToken ct)
    {
        // a singleton MUST NOT hold a scoped DbContext — create a scope per op
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        db.AuditLogs.Add(new AuditLog(patientId, action, DateTimeOffset.UtcNow));
        await db.SaveChangesAsync(ct);
    }
}
```

**Key lines explained:**

- Singleton `PatientAuditService` injects `IServiceScopeFactory` (a singleton).
- Each operation creates a fresh scope → a fresh `DbContext` → no captivity, correct change tracking, disposed after use.

### Internal Working

- Scopes are nested `IServiceScope` trees; disposal disposes scoped + transient `IDisposable`s bottom-up.
- Singletons live in the root scope (`ServiceProvider.RootProvider`); they're disposed at `app` shutdown.
- The container tracks disposable instances per scope to dispose them correctly.

### Advantages

- Lifetime = semantics: request-bound state, shared stateless, fresh-per-use.
- Centralized disposal.

### Disadvantages

- Wrong lifetime = subtle bugs (captivity, thread-safety, state pollution).
- Container tracking overhead.

### Best Practices

- Scoped for anything request-bound (`DbContext`, per-request services).
- Singleton for stateless services and managed clients.
- Transient for cheap utilities with no sharing.
- Never inject a scoped into a singleton (unless via `IServiceScopeFactory`).
- Validate scopes in Development.

### Common Mistakes

- **Captive dependency:** singleton → scoped.
- Singleton with mutable state without locks.
- `DbContext` registered singleton (thread-unsafe, change-tracking corruption).
- Transient for something that must be shared (e.g., a cache).
- Disposing manually a service the container also disposes (double-dispose must still be safe).

### Interview Follow-up Questions

1. What's a captive dependency and how do you fix it? (Scoped-in-singleton; `IServiceScopeFactory` per op.)
2. Why is `DbContext` scoped? (Change tracking is per-context; not thread-safe.)
3. When is a singleton OK? (Stateless or safely synchronized.)
4. How does the container dispose services? (Per scope; singletons at shutdown.)
5. What's `IServiceScopeFactory` for? (Creating scopes inside singletons/background services.)

### Senior Level Talking Points

> "Lifetimes are the *concurrency contract* of your app: a singleton is shared across all requests, so it must be either stateless or internally synchronized; a scoped service carries request state; a transient is per-use. The bug I review hardest for is captivity — a singleton that grabbed a `DbContext` at startup. In a healthcare API, that's a change-tracker shared by every concurrent request, which produces exactly the kind of corrupt saves you can't reproduce in dev. `ValidateScopes` catches it in Development; discipline catches it in Production."

### Diagram

```
                    ┌──────────────────────────────────────────┐
        Singleton   │  one instance, app lifetime              │
                    └───────────────┬──────────────────────────┘
                                    │  (cannot inject scoped)
Request 1 ──► scope ──► Scoped (one) ──► Transient (many)
Request 2 ──► scope ──► Scoped (one) ──► Transient (many)
Request 3 ──► scope ──► Scoped (one) ──► Transient (many)
                    disposal: scoped+transient at request end
                    singletons at shutdown
```

### Memory Trick

**"Transient = disposable cup, Scoped = table setting per request, Singleton = the restaurant's cook."**

---

## 8.3 Configuration: `IOptions<T>`, `IOptionsSnapshot<T>`, `IOptionsMonitor<T>`

### Interview Answer (30–45 seconds)

> "`IOptions<T>` binds configuration sections to typed options — loaded once at startup and cached (a singleton wrapper). `IOptionsSnapshot<T>` is per-request: it re-reads configuration on each request, so changes (and per-scope overrides) are seen immediately; it's scoped. `IOptionsMonitor<T>` is the singleton that *observes* changes — `OnChange` events fire when the config changes, and `CurrentValue` always reflects the latest. My rule: `IOptions` for static startup config, `IOptionsMonitor` when config may hot-reload and you want change events, `IOptionsSnapshot` for request-scoped reads (e.g., per-tenant config)."

### Detailed Explanation

**Binding:**

```csharp
builder.Services.Configure<FhirOptions>(builder.Configuration.GetSection("Fhir"));
```

```json
{ "Fhir": { "BaseUrl": "https://fhir.example.org", "TimeoutSeconds": 10 } }
```

```csharp
public sealed class FhirOptions
{
    public string BaseUrl { get; set; } = "";
    public int TimeoutSeconds { get; set; } = 10;
}
```

- `Configure<T>` registers an `IConfigureOptions<T>` that binds on first use.
- `OptionsBuilder<T>` + `ValidateDataAnnotations()`/`Validate` for startup validation; `ValidateOnStart`.
- Required keys: `RequiredMember`/data annotations.

**The three interfaces:**

| Interface | Lifetime | Behavior |
|---|---|---|
| `IOptions<T>` | singleton wrapper | bound once; no change detection |
| `IOptionsSnapshot<T>` | scoped | re-bound per scope/request |
| `IOptionsMonitor<T>` | singleton | tracks changes; `CurrentValue` + `OnChange` |

**Key nuance — `IOptionsMonitor` in a singleton:**

- A singleton can inject `IOptionsMonitor<T>` and always read the *current* value (`monitor.CurrentValue`) — solving the "captive options" problem (a singleton capturing stale `IOptions<T>.Value`).

**Validation:**

- `ValidateDataAnnotations()` — DataAnnotations at startup.
- `Validate(options => ...)` custom; `ValidateOnStart()` — throws at startup for invalid config (fail fast — critical in healthcare).
- `OptionsBuilder.Bind(configuration)`.

**Post-configure:** `PostConfigure` for derived values.

### Real World Example (Healthcare)

```csharp
// Hot-reloadable FHIR gateway config
builder.Services.Configure<FhirOptions>(builder.Configuration.GetSection("Fhir"));

builder.Services.AddSingleton<IFhirGateway>(sp =>
{
    var monitor = sp.GetRequiredService<IOptionsMonitor<FhirOptions>>();
    return new FhirGateway(monitor);   // gateway reads CurrentValue + OnChange
});
```

### Production Code Example

```csharp
public sealed class FhirGateway : IFhirGateway
{
    private readonly IOptionsMonitor<FhirOptions> _options;
    private readonly HttpClient _http;

    public FhirGateway(IOptionsMonitor<FhirOptions> options, IHttpClientFactory http)
    {
        _options = options;
        _http = http.CreateClient("fhir");
        _options.OnChange(_ => ReconfigureBaseAddress());   // react to hot reload
    }

    private void ReconfigureBaseAddress()
        => _http.BaseAddress = new Uri(_options.CurrentValue.BaseUrl);

    public async Task<Patient> GetAsync(string id, CancellationToken ct)
    {
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(_options.CurrentValue.TimeoutSeconds));
        return await _http.GetFromJsonAsync<Patient>($"/Patient/{id}", timeoutCts.Token) ?? throw new KeyNotFoundException();
    }
}
```

**Key lines explained:**

- `IOptionsMonitor<T>` — the singleton-safe way to read config that may reload.
- `OnChange` — react to config updates (rebase the client).
- `CurrentValue` — always-latest read.

### Internal Working

- `Configure<T>` registers a binding `IConfigureOptions<T>`.
- `IOptions<T>.Value` is lazily evaluated once and cached per `OptionsFactory` in the singleton.
- `IOptionsMonitor<T>` registers a change-token listener on the config provider; `OnChange` fires async.
- `IOptionsSnapshot<T>` re-runs the factory per scope.

### Best Practices

- Use `IOptions<T>` for static config; `IOptionsMonitor<T>` for hot-reload + change events; `IOptionsSnapshot<T>` for per-request.
- Validate at startup (`ValidateOnStart`) — fail fast on bad config (healthcare: no silent misconfig).
- In singletons, prefer `IOptionsMonitor<T>` (avoid stale options).
- Never pass `IConfiguration` into domain services — bind to typed options at the edge.

### Common Mistakes

- `IOptions<T>` in a singleton that should react to config changes (stale).
- `IOptionsSnapshot` injected into a singleton (it's scoped → captive dependency error).
- No validation → a typo'd `TimeoutSeconds` becomes a silent 0-timeout.
- Binding unvalidated data into domain config.

### Interview Follow-up Questions

1. `IOptions` vs `IOptionsSnapshot` vs `IOptionsMonitor`? (Once / per-request / change-aware.)
2. Why is `IOptionsSnapshot` scoped? (It re-reads per scope.)
3. How do you validate options at startup? (`ValidateOnStart` + `Validate`/`ValidateDataAnnotations`.)
4. Can a singleton use `IOptionsMonitor`? (Yes — that's the point.)

### Senior Level Talking Points

> "Options are a *boundary* concern: raw `IConfiguration` should never reach domain code — bind typed options at the edge, validate them at startup, and choose the interface by lifetime. `ValidateOnStart` is non-negotiable in healthcare: a bad timeout config silently killing every downstream call is worse than a failed boot. And I use `IOptionsMonitor` in singletons specifically to avoid the classic stale-options captive bug."

### Memory Trick

**"IOptions = a photo; Snapshot = new photo per request; Monitor = a live webcam."**

---

## 8.4 Factories, Delegates, and Keyed Services

### Interview Answer (30–45 seconds)

> "Sometimes constructor injection isn't enough: you need *runtime choice* or *many instances*. Patterns: register a factory delegate (`sp => new Something(sp.GetRequiredService<X>())`) for custom construction; inject `Func<T>`/factory interfaces for creating instances at runtime; use `IHttpClientFactory` for managed, named, resilient `HttpClient`s; and .NET 8's *keyed services* let you register multiple implementations and select by key (`[FromKeyedServices("sql")]`). These keep the composition root central while giving flexibility at runtime."

### Detailed Explanation

**Factory registration:**

```csharp
builder.Services.AddSingleton<ICache>(sp =>
{
    var opts = sp.GetRequiredService<IOptions<CacheOptions>>().Value;
    return new RedisCache(opts.ConnectionString);   // custom construction
});
```

- The factory lambda is the constructor — full control (custom args, side effects).
- The container still owns the lifecycle.

**Runtime creation via delegate/factory interface:**

```csharp
builder.Services.AddTransient<IClientConnector>(sp =>
    new ClientConnector(sp.GetRequiredService<IClientRegistry>()));

// or inject a factory interface you define
public interface IReportBuilderFactory { ReportBuilder Create(ReportType type); }
```

- `Func<T>` injection is supported by the container — but a *factory interface* is more explicit and testable.

**`IHttpClientFactory`:**

- `AddHttpClient("fhir")` → named client; pool of `HttpMessageHandler`s reused (avoids socket exhaustion).
- `.AddTypedClient<TClient>()` → typed client resolving through DI.
- Resilience via `AddPolicyHandler` (Polly) / `AddResilienceHandler` (net8) — see Chapter 37.
- `HttpClient` lifetime: the factory creates short-lived clients wrapping long-lived handlers — the "don't new HttpClient" guidance.

**Keyed services (.NET 8):**

```csharp
builder.Services.AddKeyedSingleton<INotifier, EmailNotifier>("email");
builder.Services.AddKeyedSingleton<INotifier, SmsNotifier>("sms");

// consumption
public class AlertDispatcher([FromKeyedServices("email")] INotifier email) { ... }
```

- Selection by key at injection sites (`[FromKeyedServices]`, `KeyedService.AnyKey`).
- Good for strategy selection at the composition root.

**Scopes inside factories:** if the factory creates scoped work, it should create a scope (`IServiceScopeFactory`) per unit — same rule as singletons.

### Real World Example (Healthcare)

```csharp
// Notification channels as keyed services (net8)
builder.Services.AddKeyedTransient<INotifier, EmailNotifier>("email");
builder.Services.AddKeyedTransient<INotifier, SmsNotifier>("sms");
builder.Services.AddKeyedTransient<INotifier, PagerNotifier>("pager");

// Named HTTP clients with resilience
builder.Services.AddHttpClient("fhir")
    .AddPolicyHandler(Policy.TimeoutAsync<HttpResponseMessage>(TimeSpan.FromSeconds(10)));
```

### Production Code Example

```csharp
// Typed client via IHttpClientFactory
public interface IFhirClient { Task<Patient> GetPatientAsync(string id, CancellationToken ct); }

public sealed class FhirClient : IFhirClient
{
    private readonly HttpClient _http;
    public FhirClient(HttpClient http) => _http = http;   // factory-injected
    public Task<Patient> GetPatientAsync(string id, CancellationToken ct)
        => _http.GetFromJsonAsync<Patient>($"/Patient/{id}", ct)!;
}

builder.Services.AddHttpClient<IFhirClient, FhirClient>(c =>
    c.BaseAddress = new Uri("https://fhir.example.org"))
    .AddPolicyHandler(Policy.TimeoutAsync<HttpResponseMessage>(TimeSpan.FromSeconds(10)));

// Factory for runtime-created report builders
public sealed class ReportBuilderFactory : IReportBuilderFactory
{
    private readonly IServiceProvider _provider;
    public ReportBuilderFactory(IServiceProvider provider) => _provider = provider;

    public ReportBuilder Create(ReportType type)
    {
        using var scope = _provider.CreateScope();      // scoped deps per report
        return new ReportBuilder(type,
            scope.ServiceProvider.GetRequiredService<IPatientRepository>());
    }
}
```

**Key lines explained:**

- `AddHttpClient<IFhirClient, FhirClient>` — typed client with factory-managed handler pooling.
- The factory creates a scope so per-operation scoped dependencies (e.g., `DbContext`) are fresh and disposed.

### Advantages

- Runtime flexibility with central wiring; resource management (handler pools); strategy selection.

### Disadvantages

- Extra abstraction; factories can hide lifecycle; keyed services are new (net8) so teammates may not know them.

### Best Practices

- Use `IHttpClientFactory` for all `HttpClient`s (never `new HttpClient()` long-lived).
- Prefer typed clients over raw named clients in app code.
- Use keyed services for strategy registrations; `[FromKeyedServices]` at injection points.
- Create scopes for scoped work in factories/singletons.

### Common Mistakes

- `new HttpClient()` per call (socket exhaustion) or one static `HttpClient` with DNS-stale handlers.
- Factory that holds scoped services (captivity).
- Over-using service locator instead of factory patterns.

### Interview Follow-up Questions

1. Why not `new HttpClient()`? (Socket exhaustion, DNS caching, handler pool reuse.)
2. What are keyed services (net8)? (Multiple registrations per abstraction, selected by key.)
3. When do you create a scope in a factory? (Scoped deps needed per operation from a singleton context.)
4. Typed vs named clients? (Typed = DI-friendly wrapper; named = config-by-name.)

### Senior Level Talking Points

> "Factories are where DI meets *runtime reality*: a clinical report needs a fresh `DbContext` per execution, so its factory opens a scope per call — not one captured at startup. And `IHttpClientFactory` is non-negotiable: handler pooling + Polly resilience is how a downstream FHIR flap doesn't melt our sockets. Keyed services (.NET 8) finally gave us clean strategy selection at the composition root — but I still keep the *selection logic* visible in code, not buried in a container config."

### Memory Trick

**"Factory = the container can't guess, so we show it the recipe at runtime."**

---

## 8.5 DI in Tests and Background Services

### Interview Answer (30–45 seconds)

> "In tests, DI means I can replace collaborators with fakes without touching the code under test. For unit tests I construct the SUT with fakes directly (or use the container with test registrations). For integration tests I use `WebApplicationFactory` to spin up the real pipeline with overridden registrations — e.g., swap the `DbContext` for a SQLite/in-memory provider or the FHIR client for a stub. Background services inject singletons + `IServiceScopeFactory` and create a scope per work item so scoped dependencies are fresh. The golden rules: never test the container wiring in unit tests (that's an integration concern), and keep fakes at the interfaces."

### Detailed Explanation

**Unit testing with DI:**

```csharp
var repo = new FakePatientRepository();        // fake
var svc = new PatientService(repo, _clock);    // constructor injection = direct construction
```

- The class is testable because dependencies are constructor parameters.
- Fakes: hand-written, mocking library (Moq/NSubstitute), or lightweight in-memory impls.

**Integration testing with `WebApplicationFactory`:**

```csharp
public class ApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<AppDbContext>();                  // remove real
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(o => o.UseSqlite("Data Source=:memory:"));
        });
    }
}
```

- The app boots the full pipeline (middleware, controllers, DI) with overridden services.
- Overrides happen after the real registrations → order matters (RemoveAll then re-add).

**Background services (Chapter 25) + DI:**

- `BackgroundService` is a singleton-ish long-running task. It injects singletons only.
- For scoped work (a `DbContext` per message), create a scope per item:

```csharp
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    while (!stoppingToken.IsCancellationRequested)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        // ... one unit of work
    }
}
```

**`ValidateOnBuild`/`ValidateScopes`:**

- In Development, `ValidateScopes` catches captive dependencies and scope misuse at first resolve.
- `ValidateOnBuild` resolves every registered type at startup → catches constructor errors early (but resolves singletons eagerly).

### Real World Example (Healthcare)

```csharp
// Integration test: override the FHIR gateway with a stub
var client = factory.WithWebHostBuilder(b =>
    b.ConfigureServices(services =>
        services.AddSingleton<IFhirGateway, StubFhirGateway>()))
    .CreateClient();

var response = await client.GetAsync("/api/patients/123");
```

### Production Code Example

```csharp
// Clean test seams via interfaces
public interface ITimeProvider { DateTimeOffset UtcNow { get; } }

public sealed class FixedTimeProvider : ITimeProvider
{
    public DateTimeOffset UtcNow { get; init; } = DateTimeOffset.UtcNow;
}

[Fact]
public async Task Medication_Overdue_When_Outside_Window()
{
    var clock = new FixedTimeProvider { UtcNow = new DateTimeOffset(2026, 1, 15, 10, 0, 0, TimeSpan.Zero) };
    var service = new MedicationReminderService(new FakePatientRepository(), clock);

    var overdue = await service.FindOverdueAsync();

    Assert.Single(overdue);
}
```

**Key lines explained:**

- `ITimeProvider` + `FixedTimeProvider` — deterministic tests without touching logic.
- Constructor injection means direct construction in tests.
- Fakes at interfaces — no DB, no HTTP.

### Internal Working

- `WebApplicationFactory<Program>` builds the app host in-process, runs the pipeline, and lets tests override registrations.
- `IServiceScopeFactory` in background services gives per-item scopes.
- `ValidateScopes`/`ValidateOnBuild` are DI-container-level safety nets.

### Best Practices

- Fakes at interfaces; don't mock sealed/static where interfaces exist.
- Integration tests override at the edge (DbContext, HTTP clients, queues).
- Background workers: inject singletons + `IServiceScopeFactory`, scope per work item.
- Keep the "sut construction" explicit.

### Common Mistakes

- Testing container wiring in unit tests.
- A singleton background service holding a scoped `DbContext`.
- Overriding registrations in the wrong order in `ConfigureServices`.
- Fakes that leak implementation details (fake `DbContext` behavior ≠ real provider).

### Interview Follow-up Questions

1. How do you override DI in integration tests? (`WebApplicationFactory.ConfigureServices`; RemoveAll then re-add.)
2. Why does a `BackgroundService` create scopes per item? (Singleton context; scoped DbContext must be fresh per unit of work.)
3. Unit test DI — do you need a container? (No — direct construction.)
4. What do `ValidateScopes`/`ValidateOnBuild` catch? (Captive deps; constructor errors.)

### Senior Level Talking Points

> "DI's real payoff is *test seams* — but only if the seams are at the right place. I put interfaces at the infrastructure edge (DB, HTTP, queues, clock) and keep domain logic behind pure, constructible classes. In integration tests, `WebApplicationFactory` with a swapped `DbContext` gives me the whole pipeline minus the real database — which is where translation bugs (Chapter 4) and middleware misconfiguration actually get caught. And I never let a background worker cheat the lifetime rules: scope per message, always."

### Memory Trick

**"Interfaces at the edges, fakes at the seams, scopes per unit of work."**

---

## Chapter 8 Wrap-Up

### Top 10 Interview Questions From This Chapter

1. What is DI and why is it better than `new`? (Testability, decoupling, lifecycle.)
2. Explain the three lifetimes and give a use for each.
3. What is a captive dependency? How do you fix it?
4. Why is `DbContext` registered scoped?
5. `IOptions` vs `IOptionsSnapshot` vs `IOptionsMonitor`?
6. What is the composition root?
7. Why not `new HttpClient()`? What does `IHttpClientFactory` do?
8. What are keyed services (net8)?
9. How do you set up DI for a `BackgroundService`?
10. How do you override registrations in integration tests?

### Revision Notes (1 page)

- **Why DI:** constructor injection + interfaces → testability, decoupling, centralized lifecycle. Composition root = single wiring point.
- **Lifetimes:** Transient (per resolve, no share), Scoped (per scope/request — DbContext), Singleton (per app — stateless/caches). **Captive dependency** = singleton→scoped injection (freezes state); fix with `IServiceScopeFactory` per op.
- **Options:** `IOptions` (once), `IOptionsSnapshot` (per request), `IOptionsMonitor` (change-aware singleton, `OnChange`). Validate with `ValidateOnStart`.
- **Factories/clients:** `IHttpClientFactory` (handler pooling, resilience, typed clients); keyed services (net8, `[FromKeyedServices]`); create scopes for scoped work in factories.
- **Tests:** unit = construct with fakes; integration = `WebApplicationFactory` + `ConfigureServices` overrides (RemoveAll then re-add); background services = singleton + scope per item.
- **Safety:** `ValidateScopes`/`ValidateOnBuild` in Development.

### Things Interviewers Expect From 5+ Years Experience

- Lifetime choice explained with consequences, not just definitions.
- Immediate identification of captivity and stale-options bugs.
- Awareness of disposal and thread-safety implications.
- Modern features: `IOptionsMonitor`, keyed services, `WebApplicationFactory`, typed clients.
- A "no service locator" discipline.

### Cheat Sheet

```
LIFETIMES:
  Transient  = new per resolve (cheap stateless)
  Scoped     = per request (DbContext!)   → dispose at request end
  Singleton  = per app (stateless, caches, clients) → dispose at shutdown
  TRAP: singleton injecting scoped = captive dependency (frozen state)
  FIX:  IServiceScopeFactory.CreateScope() per operation

OPTIONS:
  IOptions<T>          = once, cached (static config)
  IOptionsSnapshot<T>  = per request/scope (tenant config)
  IOptionsMonitor<T>   = change-aware singleton (CurrentValue, OnChange)
  ValidateOnStart + Validate = fail fast

CLIENTS:
  NEVER new HttpClient() → IHttpClientFactory (handler pooling)
  typed clients: AddHttpClient<IFhirClient, FhirClient>
  keyed services (net8): AddKeyedSingleton<INotifier, EmailNotifier>("email")
                          [FromKeyedServices("email")]

TESTS:
  unit      → construct SUT with fakes (no container)
  integration → WebApplicationFactory + ConfigureServices (RemoveAll → re-add)
  background → singleton + IServiceScopeFactory, scope per work item

NO: service locator, ambient singletons, new in services
```

### Flash Cards

**Q1:** Singleton → scoped injection? **A:** Captive dependency — the scoped service is frozen for the app's life. Use `IServiceScopeFactory`.

**Q2:** DbContext lifetime? **A:** Scoped (per request) — change tracking isn't thread-safe.

**Q3:** IOptionsMonitor in a singleton? **A:** Yes — that's its purpose (change-aware reads).

**Q4:** Composition root? **A:** The single wiring point (Program.cs).

**Q5:** Why pooled HttpClient? **A:** Handler reuse → no socket exhaustion, DNS caching issues, resilience via Polly.

**Q6:** Keyed services purpose? **A:** Multiple implementations per abstraction, selected by key.

**Q7:** BackgroundService + scoped DbContext? **A:** Create a scope per work item via `IServiceScopeFactory`.

**Q8:** ValidateScopes catches? **A:** Captive dependencies at resolve time (Development).

**Q9:** IOptionsSnapshot lifetime? **A:** Scoped.

**Q10:** Unit tests need a container? **A:** No — constructor injection → direct fake construction.

### Interview Confidence Score

**Medium.** DI is asked in nearly every ASP.NET Core interview. The senior signals: lifetime reasoning, captive dependency awareness, `IOptionsMonitor`/keyed services fluency, `IHttpClientFactory` usage, and integration-test override patterns.

---

*Continue → Chapter 9: ASP.NET Core*
