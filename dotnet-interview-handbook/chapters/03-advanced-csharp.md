# Chapter 3: Advanced C#

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** Delegates, events, lambdas and closures, `Func`/`Action`/`Predicate`, generics and variance, async/await internals, `ValueTask`, iterators and `yield`, reflection and attributes, expression trees, advanced pattern matching, extension methods, tuples, `Span<T>`/`Memory<T>`, and cancellation tokens.

---

## 3.1 Delegates and Events

### Interview Answer (30–45 seconds)

> "A delegate is a type-safe method reference — it's a class that wraps a method pointer plus the target instance, so you can pass methods around like values. An event is a *delegate field with a subscription contract*: the compiler generates `add`/`remove` accessors and (for field-like events) a backing delegate, and it protects the delegate from being overwritten from outside the declaring class — external code can only `+=` and `-=`. The key difference: outside code cannot invoke a class's event (only `add`/`remove`), but it *can* invoke a delegate field directly. The runtime uses multicast delegates, where one delegate holds an invocation list; that's how multiple subscribers get notified. In modern code, the `EventHandler<T>` pattern is standard, and I use events for notification contracts while using `Task`-based flows or `Channel<T>` where backpressure matters."

### Detailed Explanation

**Delegate basics:**

- `delegate void NotifyHandler(string message);`
- A delegate is a reference type derived from `System.Delegate`/`MulticastDelegate` with: an `Invoke` method, `BeginInvoke` (legacy async, obsolete), and a target+method pair.
- Instantiation: `NotifyHandler h = methodName;` or lambda `NotifyHandler h = m => ...`.
- **Multicast:** `+=` chains handlers into an invocation list; invoking calls them in order. `-=` removes one.

**Events:**

- `public event NotifyHandler? Notified;`
- Field-like events: compiler synthesizes a private delegate field + public `add_`/`remove_` accessors. The *event* is the accessor pair; the *field* is private.
- Outside the class: only `+=`/`-=` allowed (invoking it is a compile error: "the event can only be invoked from within the declaring class").
- Custom `add`/`remove` accessors let you intercept subscriptions (e.g., `WeakEventManager`, thread safety).
- Standard BCL pattern: `EventHandler` / `EventHandler<TEventArgs>` — event args should derive from `EventArgs`.

**When to use which:**

- **Event** when you need a *notification contract* that only the declaring type may raise, with multiple subscribers, and "fire and forget" semantics.
- **Delegate** when you pass a *single callback* (e.g., `Func<T>` to LINQ, `IComparer` replacement).
- **Modern .NET** prefers: `Func`/`Action` delegates, `IProgress<T>`, `TaskCompletionSource`, `Channel<T>`, or `IObservable<T>` over raw events in new APIs. Events remain for UI and framework patterns.

**Thread-safety caveat:** a field-like event raises `NullReferenceException` if no subscribers unless you copy first: `var handler = Notified; handler?.Invoke(...)`. Subscriber races (someone `-=` mid-raise) are the classic bug.

### Real World Example (Healthcare)

A `VitalSignsMonitor` raises `event EventHandler<VitalsAlertEventArgs>? AlertRaised;`. The alarm service, the pager service, and the audit log all subscribe. When the monitor raises, each subscriber runs — that's the multicast delegation model. Careful: if a subscriber throws, subsequent subscribers are skipped (the exception propagates) — a production hazard that often gets you into structured dispatch instead.

### Production Code Example

```csharp
public sealed class VitalsAlertEventArgs : EventArgs
{
    public required string PatientId { get; init; }
    public required string AlertType { get; init; }   // "SpO2 low", "HR high"
    public required DateTimeOffset OccurredAt { get; init; }
}

public sealed class VitalsMonitor : IDisposable
{
    public event EventHandler<VitalsAlertEventArgs>? AlertRaised;

    private void RaiseAlert(VitalsAlertEventArgs args)
    {
        var handler = AlertRaised;      // copy — avoids NRE and torn lists
        handler?.Invoke(this, args);
    }

    // elsewhere: on a new reading
    private void OnReading(Reading r)
    {
        if (r.SpO2 < 90m)
            RaiseAlert(new VitalsAlertEventArgs { PatientId = r.PatientId, AlertType = "SpO2 low", OccurredAt = DateTimeOffset.UtcNow });
    }

    public void Dispose() => AlertRaised = null;   // detach all subscribers
}
```

**Key lines explained:**

- `event EventHandler<...>?` — standard pattern; nullability annotation.
- `var handler = AlertRaised; handler?.Invoke(...)` — snapshot the delegate to avoid the classic race/NRE.
- `Dispose` clears subscribers — prevents the "event keeps object alive" leak (the event source holding references to subscribers keeps them in memory).

### Internal Working

1. `delegate` → compiles to a class deriving `MulticastDelegate` with `_target`, `_methodPtr`, `_invocationList` (null for single, array for multi).
2. `+=` → `Delegate.Combine` creates a new multicast delegate with a combined invocation list (delegates are immutable — combining returns a new one).
3. `Invoke` → walks the invocation list calling each entry (the runtime optimizes single-target into a direct call).
4. Field-like event → `add_`/`remove_` methods doing `Interlocked.CompareExchange` on the backing field (thread-safe add/remove in the generated code).

### Comparison Table: Delegate vs. Event

| Aspect | Delegate | Event |
|---|---|---|
| Outside invoke | Allowed | Compile error |
| Subscriber add | `=`, `+=`, `-=` | `+=`/`-=` only |
| Backing storage | public field | private field + accessors |
| Multicast | Yes | Yes |
| Encapsulation | open | closed (protected `add`/`remove`) |
| Typical use | callback/passing method | notification contract |

### Best Practices

- Use `EventHandler<T>` for events; derive args from `EventArgs`.
- Always snapshot the delegate before invoking (`var h = E; h?.Invoke(...)`).
- Raise on a copied list to tolerate subscriber mutation.
- Consider `Channel<T>`/`IObservable<T>` for streaming; `IProgress<T>` for async progress.
- Unsubscribe in `Dispose` to avoid leaks.

### Common Mistakes

- Invoking the event outside the class (compile error — then "fixing" by exposing a public delegate, losing the safety).
- Race/NRE without snapshotting.
- A throwing subscriber killing later subscribers.
- Event-subscription memory leaks (subscriber held alive by publisher).

### Interview Follow-up Questions

1. Why can't you invoke an event from outside the class? (Design intent; only the owner raises.)
2. What is a multicast delegate and how does `+=` work? (`Delegate.Combine`, immutable.)
3. What's the difference between a field-like event and a custom-add event?
4. How do you make an event thread-safe? (Interlocked compare-exchange; `add`/`remove` accessors.)
5. When would you choose `Channel<T>` over an event? (Backpressure, async consumers.)

### Senior Level Talking Points

> "Events are a notification *mechanism* with real footguns: the invocation list is a snapshot at raise-time, exceptions abort the chain, and publisher/subscriber lifetimes couple objects. In a healthcare alert pipeline I don't let domain logic ride on raw events — I treat them as an edge concern (UI, legacy SDKs) and use `Channel<T>` or message buses for reliability, exactly because an exception in one subscriber must not silence the code-blue page to another."

### Diagram

```
Publisher (VitalsMonitor)                      Subscribers
┌────────────────────────┐
│ event AlertRaised      │──add──► [AlarmService]
│    backing delegate ────────┼──► [PagerService]
└────────────────────────┘     └──► [AuditLogger]
           │
      RaiseAlert() ──► invocation list: AlarmService → PagerService → AuditLogger
                       (each runs in registration order; one throw = chain aborts)
```

### Memory Trick

**"Delegate is a method in a variable; an event is a delegate behind a velvet rope."**

---

## 3.2 `Func`, `Action`, `Predicate`, and Lambdas

### Interview Answer (30–45 seconds)

> "`Func<T1,...,TResult>` is a generic delegate that returns a value, `Action<T...>` returns void, and `Predicate<T>` is the legacy name for `Func<T,bool>`. Lambdas `(x) => x > 5` are just *expression-syntax* for creating these delegates (or expression trees when assigned to `Expression<...>`). There's no runtime difference between `Func<T,bool>` and `Predicate<T>` — the framework kept `Predicate` for API compat. I use these everywhere LINQ does: filtering, mapping, callbacks, and passing behavior into algorithms. Closures — lambdas that capture local variables — are the important gotcha: the compiler hoists captured variables into a heap object, which changes both performance and semantics."

### Detailed Explanation

**The three generic delegate shapes:**

| Delegate | Signature | Returns |
|---|---|---|
| `Action` | `void()` | void |
| `Action<T1,T2,...>` | `void(T1,T2,...)` | void |
| `Func<TResult>` | `TResult()` | TResult |
| `Func<T1,...,TResult>` | `TResult(T1,...)` | TResult |
| `Predicate<T>` | `bool(T)` | bool |

- `Func` up to 16 inputs (0–16); `Action` 0–16.
- These are *generic delegate types* — instantiate with `Func<int,int> square = x => x * x;`.

**Lambda syntax forms:**

- Expression lambda: `x => x * 2`.
- Statement lambda: `x => { Console.WriteLine(x); return x * 2; }`.
- Parameter-less: `() => Guid.NewGuid()`.
- Explicit types: `(int x) => x * 2`.
- With discard: `(_, y) => y`.
- `ref`/`out` params in lambdas? Not allowed in lambda syntax (C# 13 added some support for `ref` params in certain cases — be cautious).

**What a lambda compiles to:**

- **Delegate:** either a static method (no capture), a *closure object* method (captures), or a cached static delegate reused for stateless lambdas.
- **Expression tree:** `Expression<Func<int,int>>` — compiles to a tree object, not a method. Used by EF Core to translate to SQL, and by frameworks for dynamic behavior.

**Closures:**

- A lambda referencing a local variable captures it by reference into a compiler-generated class (the "display class").
- Consequence 1 (semantics): the loop-index capture bug — `for` loops before C# 5 captured one shared variable.
- Consequence 2 (performance): the closure class is heap-allocated; per-iteration closures create garbage.

### Real World Example (Healthcare)

```csharp
var critical = patients
    .Where(p => p.LatestSpO2 < 90m)          // Predicate via lambda
    .Select(p => new AlertDto(p.Id, "SpO2 low"))  // Func mapping
    .ToList();

Action logAlert = () => _logger.LogWarning("critical spO2 count: {Count}", critical.Count);
logAlert();
```

And the danger of closures in a loop:

```csharp
var actions = new List<Action>();
for (int i = 0; i < 3; i++)
    actions.Add(() => Console.WriteLine(i));   // C# 5+: prints 0,1,2 (fixed); pre-C#5: 3,3,3
```

### Production Code Example

```csharp
// Passing behavior into a reusable pipeline
public sealed class RetryPolicy
{
    public static async Task<T> WithRetriesAsync<T>(
        Func<Task<T>> operation,
        int attempts,
        Action<int> onRetry)                 // Action for side-effect callback
    {
        for (var attempt = 1; attempt <= attempts; attempt++)
        {
            try { return await operation(); }
            catch (Exception) when (attempt < attempts)
            {
                onRetry(attempt);
            }
        }
        throw new InvalidOperationException("unreachable");
    }
}

// Usage
var result = await RetryPolicy.WithRetriesAsync(
    () => fhirClient.GetPatientAsync(id),      // Func<Task<Patient>>
    attempts: 3,
    onRetry: a => _logger.LogWarning("retrying, attempt {Attempt}", a));  // Action<int>
```

**Key lines explained:**

- `Func<Task<T>>` — a "factory" of work, awaited inside the generic loop.
- `Action<int>` — side-effect callback (logging), decoupled from the policy.
- Lambda → delegate; the JIT caches stateless lambdas (no allocation per call).

### Internal Working

1. Stateless lambda → compiler emits a static method + a cached static delegate instance. Zero per-call allocation.
2. Capturing lambda → a display class instance per *scope* (not per invocation, unless the scope is per-iteration); the delegate holds a reference to it.
3. Assignment to `Expression<...>` → compiler builds `Expression.Call`/`Expression.Multiply` nodes instead.

### Advantages

- Concise, inline behavior; higher-order functions; LINQ's engine.
- Stateless lambdas are free (cached).

### Disadvantages

- Closures allocate; captured loop variables confuse (less so since C# 5).
- Delegates have indirection; over-lambdafication can hurt readability.
- Expression trees for non-SQL providers add runtime cost.

### Best Practices

- Use `Func`/`Action` over custom delegate types in new APIs (unless named semantics matter).
- Hoist stateless lambdas out of hot loops where measurable.
- Watch for accidentally capturing loop variables / disposable resources.
- Prefer `Expression<Func<...>>` only where a provider (EF) consumes it.

### Common Mistakes

- The classic loop-capture bug.
- Lambdas capturing `Dispose`d resources (connection/context) and using them later.
- `Func<int,bool>` vs `Predicate<int>` confusion in overload resolution (they're distinct types — a method can't be assigned to both without ambiguity... actually it can; but overloads may be ambiguous).

### Interview Follow-up Questions

1. What's the difference between `Predicate<T>` and `Func<T,bool>`? (None functionally; legacy compat.)
2. When does a lambda become a closure? (When it captures variables.)
3. What does the compiler generate for a stateless lambda? (Static method + cached delegate.)
4. `Expression<Func<...>>` vs `Func<...>` — what's the compile-time difference? (Tree vs method.)

### Senior Level Talking Points

> "Lambdas are the standard vocabulary for passing behavior — the real design question is *where* you pass behavior: callbacks that run inline (fine), callbacks that outlive the method (closure lifetime hazard), or queries meant for translation (need expression trees). In a healthcare gateway I audit every lambda that captures a request-scoped service — capturing `DbContext` into a background task is a classic 'context disposed' production incident."

### Memory Trick

**"Func returns, Action acts, Predicate judges."**

---

## 3.3 Generics: Constraints and Variance

### Interview Answer (30–45 seconds)

> "Generics defer the type until usage — `List<T>` is a *generic type definition* that the runtime specializes per closed type `List<int>`, `List<Patient>`, giving type safety without boxing and without per-type source duplication. Constraints (`where T : class, IComparable<T>, new()`) declare the contract the type parameter must satisfy. Variance controls assignability: `IEnumerable<T>` is *covariant* (`IEnumerable<Animal>` accepts `IEnumerable<Dog>`), `Action<T>` is *contravariant* (`Action<Dog>` accepts `Action<Animal>`), and `List<T>` is invariant. The runtime creates shared generic instantiations for reference types (`List<string>` and `List<Patient>` share code) and specialized ones for value types (`List<int>` is its own)."

### Detailed Explanation

**Why generics exist:**

- Type safety at compile time: `List<int>` won't accept a string.
- No boxing: `List<int>` stores `int[]`.
- No code duplication: you don't write `IntList`, `PatientList`, `StringList`.
- The tradeoff historically was JIT time and code size (generic instantiations).

**Constraints:**

```csharp
public static T Max<T>(IEnumerable<T> items) where T : IComparable<T>
```

| Constraint | Meaning |
|---|---|
| `where T : class` | reference type (or `class?` nullable) |
| `where T : struct` | value type |
| `where T : new()` | parameterless ctor |
| `where T : SomeClass` | derives from type |
| `where T : ISomeInterface` | implements interface |
| `where T : notnull` | not nullable |
| `where T : unmanaged` | unmanaged value type (for pointers/span) |
| `where T : Enum` / `where T : Delegate` | enum/delegate (C# 7.3+) |

- `default(T)` is the zero/null for T.

**Variance (only for interfaces and delegates, not classes):**

- **Covariance (`out T`):** `IEnumerable<out T>`, `Func<out TResult>`. Can treat `IEnumerable<Dog>` as `IEnumerable<Animal>` (upcast in the read direction). Safe because T only appears in output positions.
- **Contravariance (`in T`):** `Action<in T>`, `IComparer<in T>`, `Comparison<in T>`. Can treat `Action<Animal>` as `Action<Dog>` (downcast in the input direction). Safe because T only appears in input positions.
- **Invariance:** `List<T>`, `IList<T>`, arrays (`Dog[]` is "covariant" at runtime but with `ArrayTypeMismatchException` risk — a legacy hole).
- The compiler enforces that `out` T never appears as a method parameter and `in` T never as a return type.

**Internal: shared vs. specialized instantiations.**

- Reference type argument → one shared "generic" instantiation with `object`-slots (method table pointers) reused across all reference-type closed types (`List<string>` and `List<Stream>` share code).
- Value type argument → a distinct instantiation per value type (`List<int>`, `List<decimal>` are separate compiled code paths).
- Since .NET Core 2.0+, the JIT supports "generic virtual method devirtualization" and faster dynamic instantiation.

### Real World Example (Healthcare)

```csharp
// A validated value wrapper reused across lab codes
public readonly record struct Code<T> where T : struct, Enum
{
    public T Value { get; }
    public Code(T value) => Value = value;
    public static Code<T> Parse(string text) => new(Enum.Parse<T>(text, ignoreCase: true));
}
```

And covariance in action:

```csharp
IEnumerable<Observation> observations = new List<LabResult>();  // covariant upcast
Func<Observation, string> fmt = o => o.Id;
Func<LabResult, string> fmtLab = fmt;   // Func<in Observation> is contravariant: works
```

### Production Code Example

```csharp
public interface IRepository<T> where T : IEntity
{
    Task<T?> GetAsync(Guid id, CancellationToken ct);
    Task AddAsync(T entity, CancellationToken ct);
}

public sealed class PatientRepository : IRepository<Patient> { /* ... */ }

// Unmanaged constraint enables Span/pointer-friendly code
public static Span<T> AsSpan<T>(T[] array) where T : unmanaged
    => array;   // only for unmanaged T (no GC references inside)

// Enum constraint gives typed flags helpers
public static bool Has<TFlags>(this TFlags flags, TFlags flag)
    where TFlags : struct, Enum
    => flags.HasFlag(flag);
```

**Key lines explained:**

- `where T : IEntity` — the repository contract only needs the entity's identity contract.
- `where T : unmanaged` — restricts to blittable types so memory access is safe.
- `where T : struct, Enum` — typed enum helpers without boxing.

### Advantages

- Type safety, no boxing, no duplication, reusable algorithms.

### Disadvantages

- JIT specialization cost for value types (mitigated by modern JIT).
- Variance is only supported on interfaces/delegates, not classes.
- Generic type constraints don't let you use operators (`+`) without tricks (`INumber<T>` in .NET 7+ fixes this).

### Best Practices

- Constrain only what you need (over-constraining hurts reuse).
- Prefer `INumber<T>`/`IParsable<T>` generic math (`.NET 7+`) over reflection hacks.
- Mark interface `out`/`in` when semantically valid — it's part of the API contract.
- Don't create `List<object>` to work around generics — define the closed type.

### Common Mistakes

- Forgetting variance when it's needed (passing `List<Dog>` to a method wanting `IEnumerable<Animal>` works; wanting `IList<Animal>` doesn't — `IList<T>` is invariant).
- Covariant arrays (`Dog[]` assigned to `Animal[]`) → runtime `ArrayTypeMismatchException`.
- Constraints that block valid use (`where T : struct` then passing a string).

### Interview Follow-up Questions

1. Why can't classes be covariant like interfaces? (Assignability of a whole type requires invariance in fields.)
2. What's the `INumber<T>` feature? (Generic math, .NET 7+.)
3. Do `List<int>` and `List<string>` share generated code? (No — value types specialize; reference types share.)
4. What does `where T : unmanaged` enable? (Blittable memory, spans, pointers.)

### Senior Level Talking Points

> "Variance is where seniors earn their keep: it's easy to know `IEnumerable<out T>` exists and hard to know *when it's safe* — the rule is 'output positions only.' In a healthcare platform, contracts like `IQueryable<T>` and `IReadOnlyList<T>` should be designed with variance in mind so that `IEnumerable<LabResult>` naturally flows into code typed against `IEnumerable<Observation>` without casting. And the `INumber<T>` generic-math feature is a genuinely modern answer to the old 'generics can't do arithmetic' complaint."

### Diagram

```
COVARIANCE (out T):            CONTRAVARIANCE (in T):
  IEnumerable<Dog>               Action<Animal>
      │  upcast                       │  downcast (input)
      ▼                              ▼
  IEnumerable<Animal>             Action<Dog>
  (read direction, safe)         (write direction, safe)

INVARIANCE: List<T> — Dog[]→Animal[] legal at compile time, throws at runtime.
```

### Memory Trick

**"out comes out (covariant), in goes in (contravariant); lists are locked (invariant)."**

---

## 3.4 Async/Await Internals and the State Machine

### Interview Answer (30–45 seconds)

> "`async`/`await` is a compiler transformation, not a thread — `await` returns control to the caller and resumes when the awaited operation completes, on whatever synchronization context is current (or a thread-pool thread if none). The compiler generates a *state machine struct* implementing `IAsyncStateMachine` with fields for captured locals, the continuation, and a `MoveNext()` that re-enters where it left off. The important nuances: the state machine object is usually boxed (heap-allocated) unless it's a `ValueTask`-based async method with a successful-first-path, awaiting a completed `Task` short-circuits synchronously, and exceptions are captured and rethrown on the resuming thread — that's why you *can* await in `try/catch`. SynchronizationContext matters: ASP.NET Core has none (it doesn't marshal back), WPF/WinForms do; that's why `ConfigureAwait(false)` is mostly a library-libraries question, not a web-API question."

### Detailed Explanation

**What `await` does (the pipeline):**

1. Method runs synchronously to the first incomplete `await`.
2. Returns a `Task`/`Task<T>`/`ValueTask` to the caller (incomplete).
3. Registers a continuation: `awaiter.OnCompleted(continuation)`.
4. When the awaited op completes, the continuation is posted via the `SynchronizationContext`/`TaskScheduler`.
5. `MoveNext()` restores locals, may resume on a different thread, runs to the next `await` or completes the task.

**The state machine:**

- The compiler turns the method body into a struct with: a state `int`, the builder (`AsyncTaskMethodBuilder`), captured locals/args as fields, an `awaiter` field for the current await, and `MoveNext()`.
- Boxing: the builder holds a reference; usually the struct is boxed once (to the heap) on first suspension unless the result is synchronous — that's why short async methods with completed-awaits can avoid allocation.
- `AsyncTaskMethodBuilder` (in `System.Runtime.CompilerServices`) drives `Task` completion; `AsyncValueTaskMethodBuilder` drives `ValueTask`.

**SynchronizationContext and `ConfigureAwait(false)`:**

- On `await`, the continuation is posted to the current `SynchronizationContext` (if non-null) or `TaskScheduler`.
- ASP.NET Core (since 2.0) has *no* default `SynchronizationContext` — continuations run on the thread pool directly; `ConfigureAwait(false)` is therefore a no-op there. It matters in library code (used by UI apps / older frameworks) and reduces overhead in libraries.
- The rule: library code → `ConfigureAwait(false)`; app code (UI, or code that must touch `HttpContext`) → don't use it (it can break context propagation).

**Async gotchas at senior level:**

- `async void` — only for event handlers; exceptions escape to the sync context and can crash apps.
- No `try/catch` around a sync throw inside an `async` method before first await (it's captured in the task).
- `Task.WhenAll`/`WhenAny`; avoid `Task.Wait()`/`.Result` (deadlock risk in UI contexts; thread-blocking in web).
- `await` in `finally`/`catch` (C# 6+, fine); `await using` for `IAsyncDisposable`.
- The DTO of async: return `Task<T>`, never `async` a method that just returns `Task.FromResult` (unless you need exception-capture semantics).
- Cancellation: pass `CancellationToken`; check `ThrowIfCancellationRequested`.

### Real World Example (Healthcare)

A clinical API handler fetching a patient + their recent labs concurrently:

```csharp
public async Task<PatientChart> GetChartAsync(string patientId, CancellationToken ct)
{
    var patientTask = _patients.GetAsync(patientId, ct);   // start both
    var labsTask = _labs.GetRecentAsync(patientId, ct);
    await Task.WhenAll(patientTask, labsTask);              // no thread blocked
    return new PatientChart(await patientTask, await labsTask);
}
```

No threads blocked during the two network calls — that's the whole point of async on a web server: a 10k-concurrent request load uses ~1 thread per active request, not per connection.

### Production Code Example

```csharp
public sealed class OrderPipeline
{
    public async Task<OrderResult> ProcessAsync(MedicationOrder order, CancellationToken ct)
    {
        // synchronous warm-up to first await: runs on caller thread
        var check = _ruleEngine.PreCheck(order);            // quick, sync

        // true async point — thread released back to pool
        var saved = await _repository.SaveAsync(order, ct).ConfigureAwait(false);

        try
        {
            var publish = await _bus.PublishAsync(saved, ct).ConfigureAwait(false);
            return OrderResult.Success(publish.MessageId);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // exceptions thrown by MoveNext are rethrown here on the resuming thread
            _logger.LogError(ex, "publish failed for order {OrderId}", order.Id);
            throw;
        }
    }
}
```

**Key lines explained:**

- `ConfigureAwait(false)` in library code — no UI context; safe and marginally cheaper.
- The `try/catch` *wraps the await* — the compiler rethrows captured exceptions at the resume point, so the catch works across threads.
- Sync prefix (`PreCheck`) runs on the caller — cheap work stays on the requesting thread.

### Internal Working (the boxed state machine)

1. Compiler emits `<ProcessAsync>d__0` struct with fields: `<>1__state`, `<>t__builder`, `<>u__1` (awaiter), captured `order`, `saved`, `check`.
2. `MoveNext()` is a big `switch (state)` — each `await` is a state boundary; the continuation re-enters `MoveNext` with the stored state.
3. First incomplete await → `builder.AwaitUnsafeOnCompleted(...)` → posts continuation to sync context/pool.
4. On completion → `MoveNext` resumes → sets result or captures exception → `builder.SetResult/SetException`.

### Advantages

- Scales web servers (no thread-per-request blocking).
- Cleaner code than callbacks/`BeginInvoke`.
- Cooperative: releases the thread during I/O wait.

### Disadvantages

- Allocation (state machine box) per suspension — mitigated by `ValueTask` + sync fast paths.
- Complexity: exception semantics, context, debugging, subtle ordering.
- `async` doesn't make the *operation* faster — only more efficient under concurrency.

### Best Practices

- All async by default in I/O-heavy apps; never block with `.Wait()`/`.Result`.
- Return `Task`/`Task<T>`; avoid `async void` except event handlers.
- Pass `CancellationToken` everywhere.
- Library code: `ConfigureAwait(false)`; app code: skip it.
- Use `ValueTask` for hot paths with sync-success (see 3.5).

### Common Mistakes

- `.Result`/`.Wait()` → thread-pool starvation under load and potential deadlocks in UI contexts.
- `async void` exceptions crashing processes.
- `await Task.Run(...)` to "make it async" for CPU work (that's parallelism, and it hogs a pool thread).
- Not passing `CancellationToken` → unresponsive shutdown.
- Deadlocks from mixing sync-wait with async code.

### Interview Follow-up Questions

1. Does `await` block a thread? (No — it returns to caller and resumes later.)
2. What's the difference between `async` methods in ASP.NET Core vs. WPF? (SynchronizationContext.)
3. What does the compiler generate for `async`? (State machine struct + builder.)
4. When does an async method allocate? (When it actually suspends — completes synchronously = no allocation.)
5. `Task.Run` vs `async/await` — when is each right? (I/O → async/await; CPU-bound background work → Task.Run.)

### Senior Level Talking Points

> "The senior mental model is *not* 'async = faster' — it's 'async = fewer blocked threads = more throughput per box, at the cost of heap allocations and complexity.' In a healthcare API the SLA you defend is the p99 latency and the connection count under a spike; async/await with `CancellationToken` and a bounded concurrency limiter is how you survive a 10x traffic spike without 500s. And I treat `ConfigureAwait(false)` as a library-convention, not a web-app requirement — misapplying it in app code can silently break `HttpContext` access."

### Diagram

```
Caller          async method                     Thread Pool
 ──► ProcessAsync(order)
        │ precheck (sync, caller thread)
        ├── await SaveAsync ──────────────► I/O in flight
        │      │ return Task (incomplete)      (no thread held)
        │      ▼ control back to caller
        │  (caller may await elsewhere)
        │                          I/O completes ──► continuation posted to pool
        │                                             │
        ◄─────────────────────────────────────────────┘
        │ MoveNext resumes on a pool thread, state restored
        │ try/catch, return result → task completes
```

### Memory Trick

**"await = 'park the method, come back when the work's done' — not 'block the thread.'"**

---

## 3.5 `Task` vs `ValueTask`

### Interview Answer (30–45 seconds)

> "`Task` is a heap-allocated, reusable-asynchronous-operations object; it can be awaited many times and is the general-purpose type. `ValueTask` is a *struct union* — either a completed `Task` or a result value — designed for hot paths where the operation often completes synchronously: it avoids the allocation in the sync-success case. The catch: `ValueTask` can only be awaited once, you can't block on it, and you shouldn't store it or await it multiple times, because its contract is single-use. My rule: return `Task` for public APIs, caching, and multi-await scenarios; return `ValueTask` for performance-critical internal paths where most calls complete synchronously or with a cached result."

### Detailed Explanation

**`Task`:**
- Reference type; one allocation per operation (unless completed/cached).
- Can be awaited multiple times; `.Result`/`.Wait()` allowed (but avoid); can be cached (e.g., `Task.CompletedTask`, a cached `Task<int>` per value).
- Works with `Task.WhenAll`/`WhenAny` semantics on the *task* itself.

**`ValueTask`:**
- Struct wrapping either: a result value (`T`), or a `Task`, or an `IValueTaskSource<T>` (pooled operation). Note: `ValueTask` (non-generic) wraps a `Task` or an `IValueTaskSource`.
- Allocation-free on the sync-success path.
- Single-await contract — `ValueTask` is meant to be consumed once (it may wrap a pooled `IValueTaskSource`).
- No blocking API (`GetAwaiter().GetResult()` is supported but discouraged).
- Not usable as the return of a long-lived queued job; not cacheable.

**When `ValueTask` is the wrong call:**

- The method is expected to *usually* complete asynchronously (then you've saved nothing and added contract restrictions).
- The result will be awaited multiple times / cached / used with `WhenAll` (multiple awaits are allowed if the underlying source supports it, but it's fragile).
- Simplicity and robustness matter more than a micro-optimization.

**Implementation detail:** `IValueTaskSource<T>` allows pooled, reusable awaitables — used internally by Socket/`Pipelines`. `ValueTask` + source pooling = zero-alloc reads in high-throughput code.

### Real World Example (Healthcare)

A `CodeSystemCache` that returns a value synchronously when cached:

```csharp
public ValueTask<CodingDefinition?> ResolveAsync(string code, CancellationToken ct)
{
    if (_cache.TryGet(code, out var def)) return new(def);   // sync, no allocation
    return new ValueTask<CodingDefinition?>(LoadAsync(code, ct));  // fall back to Task
}
```

Every cache-hit request avoids a heap allocation — meaningful in a high-QPS FHIR terminology service.

### Production Code Example

```csharp
public sealed class TerminologyCache
{
    private readonly ConcurrentDictionary<string, CodingDefinition> _cache = new();

    public ValueTask<CodingDefinition?> ResolveAsync(string code, CancellationToken ct)
    {
        // FAST PATH: cache hit → wrap the value, no Task allocation
        if (_cache.TryGetValue(code, out var definition))
            return new ValueTask<CodingDefinition?>(definition);

        // SLOW PATH: miss → a real async load
        return new ValueTask<CodingDefinition?>(LoadAsync(code, ct));
    }

    private async Task<CodingDefinition?> LoadAsync(string code, CancellationToken ct)
    {
        var def = await _remote.FetchAsync(code, ct);
        if (def is not null) _cache[code] = def;
        return def;
    }
}
```

**Key lines explained:**

- The method *statically* returns `ValueTask<T>`; the sync hit constructs it from a value — zero heap alloc.
- The miss path constructs it from a `Task<T>` — the allocation is unavoidable there.
- Consumers `await` it once — respecting the single-use contract.

### Comparison Table: `Task<T>` vs `ValueTask<T>`

| Aspect | `Task<T>` | `ValueTask<T>` |
|---|---|---|
| Type | reference | struct |
| Heap allocation | per op (usually) | only on async path |
| Await count | many | one (by contract) |
| Blocking `.Result` | yes | discouraged/no |
| Cache/multi-store | yes | no |
| Best for | general APIs, caching | hot paths, sync-success |

### Best Practices

- Default: `Task`. Upgrade to `ValueTask` only after measuring allocation pressure.
- If you return `ValueTask`, document the single-await contract.
- Don't hold `ValueTask` in a field; await it immediately or convert to `Task` (`AsTask()`).
- Never mix `.AsTask()` calls per-await on the same instance.

### Common Mistakes

- Awaiting a `ValueTask` twice (may throw or return wrong data with pooled sources).
- Using `ValueTask` for methods that are usually async (no benefit, added restrictions).
- Storing `ValueTask` in a collection/field.

### Interview Follow-up Questions

1. When is `ValueTask` allocation-free? (Sync-success, or wrapped in `IValueTaskSource`.)
2. Can you await a `ValueTask` multiple times? (Contract: no.)
3. Why is `Task` the safer default? (Robustness, cacheability, multi-await.)
4. What is `IValueTaskSource<T>`? (Poolable awaitable backend.)

### Senior Level Talking Points

> "`ValueTask` is an optimization with a *contract tax*: single use, no blocking, no caching. I tell teams to reach for it only when dotnet-counters shows allocation in an 80/20 hot path — a terminology cache is a perfect fit; a public SDK method returning search results is not. The interview one-liner that impresses: 'I choose ValueTask when the operation has a common synchronous path and the call site can guarantee single-await.'"

### Memory Trick

**"Task is a reusable mailbox; ValueTask is a one-time envelope."**

---

## 3.6 Iterators and `yield`

### Interview Answer (30–45 seconds)

> "`yield return` builds a *lazy iterator* — the method compiles into a state machine that implements `IEnumerable<T>`/`IEnumerator<T>`, producing values on demand as the consumer pulls. Nothing runs until `MoveNext()` is called, and the sequence is computed incrementally, so `Take(5)` on an infinite generator costs five steps. This laziness is what powers LINQ's streaming operators. The tradeoffs: each iteration is a state-machine allocation, exceptions thrown inside the iterator only surface when iterated (not at method call), and you can't `yield` inside `try/catch` (only inside `try/finally`). I use `yield` for pipelines, lazy materialization, and wrappers — but I eagerly materialize when the consumer needs the whole set anyway or when exceptions must surface immediately."

### Detailed Explanation

**The transformation:**

- `IEnumerable<int> CountTo(int n)` with `yield return` → compiler generates a nested class implementing `IEnumerable<int>` + `IEnumerator<int>`.
- The `IEnumerator` holds state (the current index), `MoveNext()` advances; `Current` is the last yielded value.
- The first `MoveNext()` call runs the body until the first `yield`; each subsequent `MoveNext()` resumes.

**Key properties:**

- **Deferred execution:** the body doesn't run at method invocation; only during enumeration.
- **Streaming:** values produced one at a time — memory is O(1) for generated sequences.
- **One-pass:** enumerators are forward-only.
- **`yield break`** ends the iteration (like a `return` for the sequence).

**Exception semantics:**

- `throw` before the first `yield return` executes only when `MoveNext()` is first called — so validating arguments in an iterator is a *lazy* throw.
- The workaround: a *wrapper* — an eager method that validates, then a private iterator.

**Why LINQ uses this:** operators like `Where`/`Select` are iterators. Deferred execution + streaming is why `source.Where(...).First()` short-circuits and doesn't enumerate the whole collection.

**Costs:**

- Each enumeration allocates a new iterator object (the state machine box).
- Cross-`yield` overhead (the state machine dispatch) is measurable but small.

### Real World Example (Healthcare)

Streaming a huge patient cohort instead of materializing:

```csharp
IEnumerable<PatientId> StreamCohort(IQueryable<Patient> query)
{
    foreach (var p in query)               // DB rows streamed
        yield return new PatientId(p.Id);
}
```

`foreach (var id in StreamCohort(query).Take(1000))` — only 1000 rows pulled, memory bounded.

### Production Code Example

```csharp
// Eager validation wrapper + lazy core (avoids the lazy-throw trap)
public IEnumerable<FhirObservation> Enrich(IEnumerable<FhirObservation> input)
{
    ArgumentNullException.ThrowIfNull(input);          // EAGER: throws now

    return EnrichCore(input);                          // deferred
}

private static IEnumerable<FhirObservation> EnrichCore(IEnumerable<FhirObservation> input)
{
    foreach (var obs in input)
    {
        // streaming transformation — one item in flight at a time
        yield return obs with { Status = NormalizeStatus(obs.Status) };
    }
}

// Manual iterator usage (rarely needed, but know the surface)
public IEnumerable<Day> DaysOfWeek()
{
    yield return Day.Monday;
    yield return Day.Tuesday;
    yield break;                       // stops iteration
}
```

**Key lines explained:**

- `ArgumentNullException.ThrowIfNull` runs *immediately* at `Enrich(...)` — because the method body is eager and only `EnrichCore` is lazy.
- `yield return obs with {...}` — a `record` `with` per item; streaming, no full-list copy.
- `yield break` — explicit termination.

### Internal Working

- The compiler generates `<EnrichCore>d__1` implementing `IEnumerable<T>`, `IEnumerator<T>`, `IDisposable`.
- `GetEnumerator()` returns a fresh state machine instance (`<>2__current`, `<>1__state`, captured params).
- `MoveNext()` switches on state; `Dispose()` runs `finally` blocks (that's why `using` inside an iterator works, and why `foreach` calls `Dispose`).

### Advantages

- Lazy, streaming, low memory, compositional (LINQ).
- Enables infinite sequences (`Fibonacci()`), short-circuiting, and pipelines.

### Disadvantages

- State-machine allocation per enumeration.
- Deferred exceptions (validation trap).
- Debugging is less linear (state machine).
- One-pass only.

### Best Practices

- Validate parameters in an eager wrapper.
- Use `yield` for transformations of large/streaming data.
- Don't `yield` inside `try/catch`; use `try/finally` for cleanup.
- Materialize with `.ToList()` when you need to iterate multiple times.

### Common Mistakes

- Argument validation inside the iterator → NRE-like surprise at first enumeration.
- Iterating the same lazy sequence twice and wondering why it "re-runs" (it does — that's deferred execution).
- `yield` inside `catch` (compile error).

### Interview Follow-up Questions

1. When does an iterator's body execute? (On `MoveNext`, i.e., first enumeration.)
2. Why can't you `yield` in a `try/catch`? (The generated state machine can't preserve the catch across resumption.)
3. How do you validate arguments with an iterator? (Eager wrapper method.)
4. `IEnumerable<T>` vs `IEnumerator<T>` — which does `yield return` generate? (Both — GetEnumerator returns an IEnumerator.)
5. How does LINQ's `Take` short-circuit? (Enumerable iterator stops calling MoveNext.)

### Senior Level Talking Points

> "The senior framing: `yield` is deferred-execution *responsibility*. If the consumer enumerates twice, the work runs twice — so caching or `.ToList()` matters. And in healthcare, lazily evaluating a query *while the `DbContext` is alive* vs. after disposal is the difference between a working report and an ObjectDisposedException — I always materialize before crossing the persistence boundary. That's the 'when does it run?' question that distinguishes mid from senior."

### Memory Trick

**"yield = a vending machine that only makes snacks when you press the button."**

---

## 3.7 Reflection and Attributes

### Interview Answer (30–45 seconds)

> "Reflection is the CLR's runtime metadata API — inspecting types, members, attributes, and invoking them dynamically via `Type`, `MethodInfo`, `PropertyInfo`, and friends. Attributes are declarative metadata tags (`[Serializable]`, `[JsonIgnore]`, custom attributes) that code, frameworks, and reflection read. Reflection is powerful — it's what serializers, DI containers, EF Core, and source generators replace — but it's slow (method invokes are orders of magnitude slower than direct calls, though caching `MethodInfo`/delegates mitigates it) and it's a correctness hazard (runtime errors instead of compile errors). The modern message: prefer *source generators* for code that reads metadata at build time, and use reflection only where dynamic behavior is unavoidable."

### Detailed Explanation

**Reflection surface:**

- `typeof(T)`, `obj.GetType()`, `Assembly.GetType(name)`, `typeof(T).GetMembers()`.
- `Activator.CreateInstance` (slow, reflection); `ConstructorInfo.Invoke`.
- `MethodInfo.Invoke` — the slow path (parameter array marshaling). Fast path: build a delegate via `CreateDelegate` / expression trees and cache it.
- Attribute lookup: `member.GetCustomAttribute<T>()`, `typeof(T).GetCustomAttributes()`.
- `Assembly` enumeration: scan types, load assemblies dynamically (`Assembly.LoadFrom`).
- Metadata tokens, `RuntimeTypeHandle`.

**Attributes:**

- Built-in: `[Serializable]`, `[Obsolete]`, `[Conditional]`, `[Flags]`, `[StructLayout]`, `[JsonIgnore]`, `[Authorize]`, `[ApiController]`.
- Custom attribute: class deriving `Attribute`; `AttributeUsage` declares targets (`[AttributeUsage(AttributeTargets.Property, AllowMultiple=false)]`).
- Reading: via reflection (runtime) or source generators (build time).

**Why source generators changed the game:**

- Roslyn source generators run at *compile time*, emitting code — so "reflection-like" functionality (e.g., `System.Text.Json`'s source-gen serializer, EF Core compiled models, DTO mappers) is resolved at build time: no runtime reflection, no JIT cost, compile-time correctness.
- The guidance: if your metadata-based logic is known at compile time (JSON serialization of a record), use the source generator; keep reflection for genuinely dynamic plugin scenarios.

**Reflection performance:**

- `GetProperty("X")` — cached type metadata is fast-ish (the reflection cache).
- `Invoke` — ~10–100x slower than a direct call; the JIT can't inline.
- Fixes: `Expression.Compile` → delegate; `DynamicMethod`; `MarshalByRef`-style dispatch; `UnsafeAccessor` (`.NET 8`).

### Real World Example (Healthcare)

Custom `[AuditKey]` attribute marking properties that must be included in audit logs:

```csharp
[AttributeUsage(AttributeTargets.Property)]
public sealed class AuditKeyAttribute : Attribute { }

// Reading at runtime (fine for a low-frequency audit operation)
foreach (var prop in patient.GetType().GetProperties())
{
    if (prop.GetCustomAttribute<AuditKeyAttribute>() is not null)
        entry.Fields[prop.Name] = prop.GetValue(patient);
}
```

The senior improvement: cache the list of `[AuditKey]` properties per type (dictionary keyed by `Type`) to avoid re-scanning every audit.

### Production Code Example

```csharp
public static class ReflectiveHydrator<T>
{
    // Cache a compiled setter delegate per property: fast, no Invoke()
    private static readonly IReadOnlyDictionary<string, Action<T, object?>> Setters =
        typeof(T)
            .GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .ToDictionary(
                p => p.Name,
                p => BuildSetter(p));

    private static Action<T, object?> BuildSetter(PropertyInfo prop)
    {
        var param = Expression.Parameter(typeof(T));
        var value = Expression.Parameter(typeof(object));
        // (target, value) => target.Prop = (PropType)value
        return Expression.Lambda<Action<T, object?>>(
            Expression.Assign(
                Expression.Property(param, prop),
                Expression.Convert(value, prop.PropertyType)),
            param, value).Compile();
    }

    public static void Set(T target, string propertyName, object? value)
        => Setters[propertyName](target, value);
}

// Use (avoiding per-call reflection):
ReflectiveHydrator<PatientDto>.Set(dto, "GivenName", "Ana");
```

**Key lines explained:**

- `Expression.Lambda(...).Compile()` turns the property assignment into a compiled delegate — cached once, ~as fast as a direct call afterward.
- This is the classic "fast reflection" technique (what AutoMapper-like tools do).

### Advantages

- Dynamic dispatch for plugins, serializers, ORMs.
- Metadata-driven behavior (attributes) declarative and discoverable.

### Disadvantages

- Slow when uncached (`Invoke`); can't be JIT-inlined.
- Runtime errors instead of compile-time errors.
- Code security surface (loading untrusted assemblies).
- Trimming/AOT-hostile (reflection-based code breaks with `ILTrimmed`).

### Best Practices

- Prefer source generators / `JsonSerializerContext` for static serialization.
- Cache `MethodInfo`/delegates for hot reflective paths.
- Prefer `Enum.Parse<T>` (generic) over reflection-based enum parsing.
- Respect `NativeAOT`/trimming: if you ship AOT, avoid dynamic reflection (or use `DynamicallyAccessedMembers` annotations).

### Common Mistakes

- `Activator.CreateInstance` in hot paths.
- Not caching `GetProperties()` results.
- Using reflection where `switch`/virtual dispatch/source-gen would do.
- Not considering trimming/AOT when reflection is used in libraries.

### Interview Follow-up Questions

1. Why is reflection slow, and how do you fix it? (Delegate-compilation + caching.)
2. What's a source generator and how does it compare to reflection? (Compile-time codegen vs runtime metadata.)
3. `typeof(T)` vs `GetType()` — difference? (Compile-time-known type vs runtime instance type.)
4. What happens to reflection under NativeAOT trimming? (Members may be removed.)
5. Name built-in attributes you use daily. (`[Obsolete]`, `[JsonIgnore]`, `[Authorize]`...)

### Senior Level Talking Points

> "Reflection is a *last resort* in modern .NET. When I see a `switch` over `GetType()` or `GetCustomAttribute` inside a hot loop, I reach for a cached compiled delegate or a source generator — `System.Text.Json`'s reflection serializer vs its source-gen serializer is the canonical before/after. But reflection still shines for genuinely dynamic systems — plugin hosts, policy engines — where the type graph isn't known until runtime. The senior discipline is knowing *which* of those you're in."

### Diagram

```
Compile-time (source generators)          Runtime (reflection)
  [JsonSerializable(typeof(Patient))]       typeof(Patient)
        │                                        │
   Roslyn emits serialization code          Type metadata + reflection cache
        │                                        │
   ┌────▼─────┐   vs   ┌─────────────────────────▼────────────────────┐
   │ Direct calls     │  GetProperty → Invoke (slow) → compiled delegate (fast)
   │ (AOT-friendly)   │  Scan attributes per call → cache per type
   └──────────────────┘  └────────────────────────────────────────────┘
```

### Memory Trick

**"Reflection = reading the runtime's instruction manual while the program runs."**

---

## 3.8 Expression Trees and `IQueryable`

### Interview Answer (30–45 seconds)

> "An expression tree is a runtime *representation of code* — `Expression<Func<T,bool>>` is a data structure (nodes for `Call`, `Equal`, `PropertyAccess`) instead of a compiled method. That's what lets EF Core translate LINQ to SQL: it walks the tree and builds a parameterized `SELECT`. The practical consequences: in-memory LINQ compiles the delegate and runs it, but `IQueryable` builds a query *provider*-specific tree that executes remotely — so when I pass a predicate into a repository I use `Expression<Func<T,bool>>`, not `Func<T,bool>`, or EF will pull the whole table and filter client-side. The gotchas: expression trees can't contain statements (no `if`, no assignment, no `await`), they can't be compiled in all frameworks (AOT), and user-defined methods inside a tree become `Invoke` nodes that the provider may not translate."

### Detailed Explanation

**Two worlds:**

- `Func<T,bool>` → compiled IL, executes in-process. Used with `IEnumerable<T>` (LINQ-to-Objects).
- `Expression<Func<T,bool>>` → tree of nodes, inspected by a provider. Used with `IQueryable<T>` (LINQ-to-SQL/EF).

**What the compiler does:**

- Lambda assigned to an expression type → builds nodes (`Expression.Parameter`, `Expression.Property`, `Expression.Equal`, ...) rather than emitting a method.
- You can inspect and *rewrite* the tree (that's what EF does: it matches node patterns to SQL constructs).
- `expr.Compile()` converts a tree back to a delegate (expensive; used by fast-reflection tricks).

**Why this matters in repositories:**

```csharp
// BAD: pulls all patients, filters in memory
IEnumerable<Patient> All(Predicate<Patient> filter) { ... }
// GOOD: translated to WHERE
IQueryable<Patient> Where(Expression<Func<Patient, bool>> predicate) { ... }
```

**Expression tree limitations:**

- No statements: `Expression<Func<int,int>> e = x => { var y = x*2; return y; };` — compile error.
- No `await` inside; async lambda-to-expression isn't allowed.
- Calling a method inside (`x => MyHelper(x)`) — the provider either translates it (EF can translate some known methods) or throws "not translatable."
- `.Compile()` isn't available in all contexts (NativeAOT can't compile expressions to IL at runtime).

**Query splitting / plan caching:**

- EF translates each distinct tree; the *query cache* keys on the tree shape → repeated identical queries reuse compiled SQL. New predicate shapes = new SQL plans (the "parameter vs literal" issue for caching).

### Real World Example (Healthcare)

A repository exposing a *searchable* patient store:

```csharp
public interface IPatientSearch
{
    IQueryable<Patient> Filter(Expression<Func<Patient, bool>> predicate);
}
```

Callers write `search.Filter(p => p.Mrn == mrn && p.Status == Status.Active)`, and EF Core translates to `WHERE [p].[Mrn] = @__mrn AND [p].[Status] = 1` — with parameters, safe from SQL injection.

### Production Code Example

```csharp
// Provider-consumed predicate (translated, parameterized)
public async Task<IReadOnlyList<Patient>> FindByCriteriaAsync(
    Expression<Func<Patient, bool>> predicate,
    CancellationToken ct)
{
    return await _db.Patients
        .AsNoTracking()
        .Where(predicate)                       // tree goes to EF → SQL
        .OrderBy(p => p.FamilyName)
        .ToListAsync(ct);
}

// In-memory use of the same lambda shape (LINQ-to-Objects)
public IEnumerable<AlertDto> AlertsInMemory(IEnumerable<Patient> patients)
    => patients.Where(p => p.LatestSpO2 < 90m)  // compiled delegate, in process
        .Select(p => new AlertDto(p.Id, "low SpO2"));
```

**Key lines explained:**

- Same lambda syntax; the *target type* decides the path — `Expression<>` → provider translation; `Func<>` → in-memory execution.
- `AsNoTracking()` + `ToArray/ToList` before leaving the `DbContext` scope.
- This is the canonical distinction interviewers probe.

### Internal Working

1. `Expression<Func<Patient,bool>>` tree → EF's `QueryTranslationPreprocessor` normalizes → `SqlTranslator` maps nodes to SQL fragments → parameterizes literals → sends to the provider (SQL Server).
2. Provider returns rows → `QueryShaping` materializes entities.
3. The query cache stores the *parameterized* SQL text keyed by tree shape, so repeated calls reuse the compiled query.

### Comparison Table

| Aspect | `Func<T,bool>` | `Expression<Func<T,bool>>` |
|---|---|---|
| Representation | IL method | data tree |
| Execution | in-process | provider-defined (often remote) |
| Used by | `IEnumerable` LINQ | `IQueryable` LINQ |
| Statements allowed | yes | no |
| Translates to SQL | no | yes (EF) |
| Compile | native | `Compile()` opt-in, no AOT |

### Best Practices

- Repositories: take `Expression<Func<...>>` for queries that must reach the DB.
- Keep predicates translatable: use EF-supported operators, avoid arbitrary method calls.
- Materialize before crossing layers (`ToListAsync`).
- Don't compile expression trees in AOT apps.

### Common Mistakes

- Passing `Func` to an `IQueryable` → client-side evaluation (silent perf disaster, N+1s).
- Translating `x => MyMethod(x)` → `NotSupportedException`.
- Building expression trees by hand with string concatenation (injection vector) instead of parameters.
- `IEnumerable` vs `IQueryable` confused in the same pipeline.

### Interview Follow-up Questions

1. Why does EF need `Expression<>` instead of `Func<>`? (To translate to SQL, not execute.)
2. What can't expression trees do? (Statements, `await`.)
3. What happens when EF can't translate part of a query? (Client evaluation warning/error.)
4. How do you build an expression tree dynamically? (Visitor pattern / `Expression.*` factories.)
5. Query caching in EF — what's cached? (Parameterized SQL keyed on tree shape.)

### Senior Level Talking Points

> "The senior skill isn't writing expression trees — it's *protecting the translation boundary*. I ensure every filter a controller can express reaches EF as a tree, and I ban 'expression soup' where developers inject raw methods. The failure mode is brutal in healthcare reporting: a query that works in dev (small data, in-memory) and silently becomes a 40-second full-table client-side filter in prod. That's exactly the kind of bug that costs a 99th-percentile SLA."

### Memory Trick

**"Func executes; Expression translates."**

---

## 3.9 Advanced Pattern Matching

### Interview Answer (30–45 seconds)

> "Pattern matching lets me express *shape* checks declaratively: type patterns (`x is Patient`), property patterns (`x is { Status: "final" }`), relational patterns (`x is > 100`), list patterns (`x is [_, ..]`), and `switch` expressions with guards. The compiler exhaustiveness-checks `switch` over enums and with `var`, so adding a case can be a compile error if the match isn't exhaustive. It replaces chains of `if/else` and `is/as` casts, and — important for healthcare — it lets me model domain rules as readable, testable pattern code."

### Detailed Explanation

**Pattern vocabulary:**

```csharp
// Type + declaration pattern
if (resource is Observation { ValueQuantity.Value: > 100m } obs) { }

// Property + relational + logical patterns
string category = obs.Category switch
{
    "lab" or "vitals"          => "measurement",
    { Length: > 5 }            => "custom",      // relational on string length
    _                          => "other"
};

// List patterns (C# 11)
int[] ids = { 1, 2, 3 };
if (ids is [1, .., 3]) { }        // first=1, last=3, anything between
if (ids is [var first, .. var rest]) { }

// Logical negation
if (value is not null) { }
if (kind is not Severity.Low) { }

// Nested property + `var` capture
if (patient is { Chart: { Open: true } }) { }
```

**`switch` expression vs `switch` statement:**

- Expression: returns a value, uses `=>`, requires exhaustiveness (`_` or exhaustive patterns), no fall-through.
- Statement: actions per case, supports guards (`when`), fall-through is banned.

**Exhaustiveness & `var`:**

- With `switch` expressions, the compiler warns/errors if you miss an enum case or `bool` case — that's a compile-time safety net.
- Adding an enum value can break compilation — a feature, not a bug.

**Guards (`when`):**

- `case var p when p.Age >= 65:` — order matters; first match wins.
- Guard ordering + `when` is where senior logic lives.

### Real World Example (Healthcare)

A clinical severity classifier:

```csharp
public static Severity Classify(VitalsSnapshot v) => v switch
{
    { SpO2: < 90 } or { HR: > 140 }                     => Severity.Critical,
    { SpO2: >= 90 and < 94 } or { HR: > 110 }           => Severity.High,
    { HR: > 90 } or { Temperature: >= 38.0m }           => Severity.Medium,
    _                                                   => Severity.Normal
};
```

Readable, exhaustive-by-`_`, and the guards encode clinical ranges clearly.

### Production Code Example

```csharp
public sealed record VitalsSnapshot(int HR, decimal SpO2, decimal? Temperature);

public static AlertLevel Evaluate(VitalsSnapshot v) => v switch
{
    // property + relational + capture in one
    { SpO2: < 90 } => AlertLevel.Red,
    { SpO2: < 94, HR: > 110 } => AlertLevel.Orange,
    { Temperature: > 38.0m, HR: > 100 } => AlertLevel.Yellow,
    var snapshot when snapshot.HR > 140 => AlertLevel.Red,     // guard
    _ => AlertLevel.Green
};

// List pattern: find the "next lab result after the last glucose"
public static LabResult? NextAfterLastGlucose(IReadOnlyList<LabResult> labs)
    => labs switch
    {
        [.., { TestCode: "GLU" }, var next, ..] => next,       // anything, GLU, then one
        _ => null
    };
```

**Key lines explained:**

- Property patterns + relational (`< 90`) read like clinical rules.
- `when` guards let you express conditions that aren't just member tests.
- List pattern with `..` slicing — matches "element right after the last GLU."

### Advantages

- Expressive, readable domain logic; removes `if/else` chains and cast-check-cast noise.
- Compile-time exhaustiveness for enums/bools.
- Can be faster than repeated `is`+`as`.

### Disadvantages

- Over-nesting hurts readability.
- Guard ordering bugs (unreachable cases) aren't always warned.
- Not everything is expressible (no easy range-of-date matching without helpers).

### Best Practices

- Use patterns for shape-based decisions; keep them shallow (extract helpers if deep).
- Prefer exhaustive `switch` over enums so new enum values break the build.
- Name `var` captures meaningfully.
- Combine with `record` deconstruction (`p is Patient { Address: { } a }`).

### Common Mistakes

- Forgetting `_` and getting CS8510 exhaustiveness warnings.
- Ordering guards so a broad pattern swallows a specific one.
- Pattern-matching against mutable state in hot loops (it's fine; just be aware of re-evaluation).

### Interview Follow-up Questions

1. `switch` expression vs statement — differences? (Value-returning, exhaustiveness, no fall-through.)
2. What are list patterns for? (Slicing/matching sequences; C# 11.)
3. What is `not` in pattern matching? (Logical negation: `is not null`.)
4. How does exhaustiveness checking help? (Compile-time safety on enum additions.)

### Senior Level Talking Points

> "Pattern matching lets me encode clinical triage logic as *data-shaped code* — the match arms mirror the rule sheet, which makes domain review actually possible. The senior habit is guarding against pattern *rot*: when a new severity band is added, the compiler tells me where to update. That's the difference between a rule engine that's a `switch` statement nobody dares touch and one that's an extensible, tested rule set."

### Memory Trick

**"Patterns are `is` on steroids: type, shape, value, and position all in one."**

---

## 3.10 `Span<T>` and `Memory<T>`

### Interview Answer (30–45 seconds)

> "`Span<T>` is a `ref struct` that's a safe, allocation-free *view* over contiguous memory — arrays, stack memory, or unmanaged buffers — with slicing and bounds-checked indexers. Because it's a `ref struct`, it can only live on the stack: no boxing, no heap fields, no use in async/iterators/`yield`. `Memory<T>` is its heap-safe counterpart — it can be stored in fields, passed to async methods, and backed by arrays or `MemoryManager<T>`. These are the backbone of low-allocation parsing and high-throughput processing. In practice, `ReadOnlySpan<char>` for string parsing and `Span<byte>` for buffers replace both `Substring` allocations and unsafe pointer code."

### Detailed Explanation

**Why spans exist:**

- `string.Substring` allocates. `ReadOnlySpan<char>` slices without allocating.
- `byte[]` copies — spans alias the original buffer.
- Unsafe `char*` pointers — spans add bounds checking (safety) while keeping zero-copy performance.
- They're the foundation of `System.Text.Json`, `StringBuilder.GetChunks`, `Pipelines`, and UTF-8 parsing.

**Span vs Memory placement rules:**

- `Span<T>` = `ref struct` → stack-only: can't be a class field, can't be boxed, can't be captured in a closure/lambda/async state machine, can't be a static field (with a few exceptions via `ReadOnlySpan` static-ish caches).
- `Memory<T>` = normal struct → heap-safe: class fields, async, storing in collections.
- Conversion: `memory.Span` → a span; `span` cannot become `Memory<T>` without copying (by design).

**Slices:**

- `span[2..]`, `span.Slice(start, length)`, `stackalloc` for stack buffers.
- `AsSpan()` on arrays, `AsMemory()`, `string.AsSpan()`.

**Hot-path guidance:**

- Parsing numbers from UTF-8: `int.TryParse(span, out int v)` (no strings allocated).
- `Encoding.UTF8.GetString(span)` vs `GetString(byte[])`.

**`stackalloc`:** allocate a small stack buffer (must be `unmanaged`, and typically `< ~1 KB to avoid stack overflow), e.g., `Span<char> buffer = stackalloc char[256];`.

### Real World Example (Healthcare)

Parsing an HL7 segment string without allocating substrings:

```csharp
ReadOnlySpan<char> line = hl7Line.AsSpan();
var fieldSeparator = line.IndexOf('|');
var mshSegment = line[..fieldSeparator];          // "MSH" — zero allocation
var rest = line[(fieldSeparator + 1)..];
```

Processing 1M HL7 messages: this turns MB of GC garbage into none.

### Production Code Example

```csharp
public static DateOnly? TryParseFhirDate(ReadOnlySpan<char> s)
{
    // FHIR date: YYYY, YYYY-MM, or YYYY-MM-DD
    if (s.Length is < 4 or > 10) return null;
    if (s.Length >= 8 && s[4] == '-' && s[7] == '-')
        return DateOnly.TryParseExact(s, "yyyy-MM-dd", CultureInfo.InvariantCulture, out var d) ? d : null;
    // ... other formats
    return null;
}

// High-throughput buffer processing with Memory<T> (heap-safe, async-friendly)
public async ValueTask ProcessAsync(Memory<byte> buffer, CancellationToken ct)
{
    var slice = buffer[..64];                       // view — no copy
    await ProcessChunkAsync(slice, ct);             // Memory survives the await
    slice.Span.Clear();                             // in-place write
}

private readonly record struct Slice(ReadOnlyMemory<byte> Data);  // field-safe
```

**Key lines explained:**

- `TryParseExact` on a `ReadOnlySpan<char>` — parses directly, no `string` created.
- `Memory<byte>` is stored/awaited across `await` — `Span` couldn't survive that.
- Slicing is O(1) — a length+offset view, no copy.

### Internal Working

- `Span<T>` fields: `ref T _reference` (or pointer) + `int _length`. On stack — no heap object.
- Array-backed span: indexer does `ref T fromArray = ref Unsafe.Add(ref MemoryMarshal.GetArrayDataReference(array), index)` — bounds-checked, no copy.
- Slice: new span = same reference + adjusted length/offset.
- `Memory<T>`: `object? _object` (array/string/managed manager) + index + length; `Span` property re-derives the reference.
- JIT recognizes span access patterns for vectorization (`Vector<T>`), giving SIMD speed-ups.

### Comparison Table: `Span<T>` vs `Memory<T>` vs `ArraySegment<T>`

| Aspect | `Span<T>` | `Memory<T>` | `ArraySegment<T>` |
|---|---|---|---|
| Stack-only | Yes | No | No |
| Heap field/async | No | Yes | Yes |
| Slices without copy | Yes | Yes | Yes |
| Unmanaged memory | Yes | via MemoryManager | No |
| Bounds checks | Yes | Yes | Yes |
| Typical use | hot parsing | async I/O, storage | legacy |

### Best Practices

- Use `ReadOnlySpan<char>`/`Span<byte>` for parsing and hot processing; `Memory<T>` when crossing async/field boundaries.
- Avoid large `stackalloc` (>1 KB) — stack overflow risk.
- Keep spans short-lived (they're stack-scoped anyway).
- Convert to `Memory<T>` at the API boundary of async code.

### Common Mistakes

- Returning a `Span<T>` from a method that can't prove the backing memory outlives it (compile error by design — good).
- `stackalloc` of huge buffers → `StackOverflowException`.
- Boxing a span (implicit `object` conversion is banned — compile error).
- Storing `Span` in a class field (compile error; use `Memory<T>`).

### Interview Follow-up Questions

1. Why can't `Span<T>` be used in `async` methods? (It's a `ref struct`; the state machine would need to heap-store it.)
2. `Span<T>` vs `Memory<T>` — when do you switch? (Async/fields → Memory.)
3. What is `stackalloc` and its limits? (Stack buffer, `unmanaged`, keep small.)
4. How does slicing avoid copying? (Length+offset view, same reference.)
5. How do `Pipelines`/`System.IO.Pipelines` use spans? (Pooled buffers + `Memory<byte>`.)

### Senior Level Talking Points

> "Span/Memory is the 'fast code without unsafe' story. In a healthcare ingestion service parsing HL7 or FHIR JSON, moving hot paths to `ReadOnlySpan<char>` + `Utf8Parser` cut allocations by an order of magnitude — and it's *safe*, so it survives code review and security review, unlike pointer juggling. The discipline is boundary design: spans at the hot core, `Memory<T>` at async seams, arrays at the persistence edges."

### Diagram

```
string/array (heap)   ──AsSpan()──►   Span<T> (stack view)
  [ | | | | | | | | ]                  ┌─ref─┐ ┌───────────┐
  0 1 2 3 4 5 6 7                      │ * ──► │ len=8      │
       slice span[2..5] ─────────────► │ +2    │ len=3      │
                                       └──────┘ └───────────┘
   zero copies; the view points into the original buffer
```

### Memory Trick

**"Span = stack glasses over shared data; Memory = same glasses that fit in a pocket."**

---

## 3.11 Tuples and Deconstruction

### Interview Answer (30–45 seconds)

> "Tuples are lightweight value types for grouping related values: `(int Id, string Name)`. They're `ValueTuple<T1,T2>` under the hood — no heap allocation. Deconstruction (`var (id, name) = tuple`) unpacks them; `_` discards elements. Tuples are great for *local* multi-returns, but I prefer a named `record` or a small DTO once a shape crosses method/API boundaries — tuples lose meaning and can't carry methods or validation."

### Detailed Explanation

- `(int, string)` vs named `(int Id, string Name)` — names are compiler sugar (`Item1`, `Item2` in metadata, with `TupleElementNamesAttribute`).
- `ValueTuple` is a struct: equality is structural (`==`/`Equals` compare fields), mutable by default.
- Deconstruction: `var (a, b) = pair;` requires the type to expose `Deconstruct` (tuples do; records do; you can implement it).
- Discards: `var (_, age) = person;`.
- Tuple comparison: `(asOf.Year, asOf.Month) >= (18, dob.Month)` — lexicographic.
- `Tuple<...>` (reference) is the *legacy* type; `ValueTuple` is the modern one.

### Real World Example (Healthcare)

```csharp
(int Year, int Month) SplitFhirDate(DateOnly d) => (d.Year, d.Month);

// deconstruction + discard
var (_, month) = SplitFhirDate(DateTime.Today);
```

And the classic age check without tuple comparison bugs:

```csharp
bool IsMinor(DateOnly dob, DateOnly asOf)
    => (asOf.Year - dob.Year, asOf.Month, asOf.Day) < (18, dob.Month, dob.Day);
```

### Production Code Example

```csharp
// Local multi-return: fine for internal use
public (bool Ok, string? Error, Guid Id) TryCreatePatient(string mrn, string name)
{
    if (string.IsNullOrWhiteSpace(mrn)) return (false, "MRN required", default);
    var id = Guid.NewGuid();
    return (true, null, id);
}

// Caller deconstructs + uses discards
var (ok, error, id) = TryCreatePatient("MRN-123", "Ana");
if (!ok) { _logger.LogWarning("create failed: {Error}", error); return; }

// Prefer a record once it crosses boundaries:
public sealed record CreateResult(bool Ok, string? Error, Guid? Id);
```

**Key lines explained:**

- Tuples for internal plumbing; `record` for the public contract.
- Discard `_` for unneeded elements.
- `ValueTuple` structural equality useful in comparisons.

### Advantages / Disadvantages

| | Tuples | record DTO |
|---|---|---|
| Allocation | none (struct) | heap |
| Named members | compiler sugar | real properties |
| Methods | no | yes |
| Cross-layer clarity | weak | strong |

### Best Practices

- Use tuples for local, short-lived grouping; use records/DTOs across boundaries.
- Always name tuple elements for readability.
- Prefer `record` when you'd pass a tuple to a method with a `(string, string)` signature.

### Common Mistakes

- Tuple names lost at method boundaries (caller sees `Item1`).
- Using `Tuple<...>` (boxed) instead of `ValueTuple`.
- Returning unnamed tuples from public APIs.

### Interview Follow-up Questions

1. `Tuple<T>` vs `ValueTuple<T>`? (Reference vs value; legacy vs modern.)
2. How do you deconstruct a tuple? (`var (a,b) = t;`)
3. Can you name tuple elements? (Yes — `(int Id, string Name)`.)
4. Why are records better than tuples across layers? (Named, typed, extensible.)

### Memory Trick

**"Tuples are throwaway packing tape; records are labeled boxes."**

---

## 3.12 Extension Methods

### Interview Answer (30–45 seconds)

> "Extension methods add methods to types without modifying them: a static class with `this T receiver` parameters. They're pure syntactic sugar — the compiler rewrites `obj.Foo()` into `Extensions.Foo(obj)`. They power LINQ and let me add fluent helpers to sealed types. The caveats: they can't access private state, they resolve at compile time (a real instance method always wins), and they can silently conflict or hide intent — so I use them for utility reads and fluent pipelines, not for domain behavior that should live on the type."

### Detailed Explanation

- Signature: `public static class StringExtensions { public static bool IsNullOrEmpty(this string? s) => string.IsNullOrEmpty(s); }`
- Compile-time rewrite; no runtime feature.
- Resolution: instance method beats extension method; *namespace* matters — extensions only apply when the namespace is imported.
- Can extend interfaces (e.g., `this IEnumerable<T>`) and generic types.
- `null` receivers allowed (extension on `string?` can handle null).
- Chaining: `.Where().Select().ToList()` — all extensions.

### Real World Example (Healthcare)

```csharp
public static class FhirStringExtensions
{
    public static string? TrimToNull(this string? s)
        => string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    public static bool HasAny(this string? s) => !string.IsNullOrWhiteSpace(s);
}

// Usage
string? note = input.TrimToNull();       // "   " → null
```

### Production Code Example

```csharp
public static class DateOnlyExtensions
{
    // Age in completed years as of a reference date
    public static int AgeInYears(this DateOnly dob, DateOnly asOf)
    {
        var years = asOf.Year - dob.Year;
        if (asOf < dob.AddYears(years)) years--;
        return years;
    }

    public static bool IsInWindow(this DateOnly d, DateOnly start, DateOnly end)
        => d >= start && d <= end;
}

// Usage (fluent)
var age = patient.DateOfBirth.AgeInYears(DateOnly.FromDateTime(DateTime.Today));
var eligible = claim.ServiceDate.IsInWindow(windowStart, windowEnd);
```

**Key lines explained:**

- `this DateOnly dob` — receiver; `AgeInYears` reads like an instance method.
- No access to private state — works on the public surface only.
- The compiler emits `DateOnlyExtensions.AgeInYears(dob, asOf)`.

### Advantages

- Extend sealed/BCL types; fluent readable pipelines; LINQ.
- Null-safe receivers possible.

### Disadvantages

- Can't touch private state; discoverability (hidden in namespaces); resolution surprises; can "shadow" intent; IDE must know the namespace.

### Best Practices

- Keep extension classes in namespaces that make sense (`Microsoft.Extensions...`).
- Use for read-only utilities/transformations; not for mutating business logic.
- Prefer instance methods when you own the type.

### Common Mistakes

- Extensions that duplicate instance members (never called — instance wins).
- Too many small extension classes scattered (namespace pollution).
- Extending with behavior that should live on the domain type.

### Interview Follow-up Questions

1. Can an extension method be called on `null`? (Yes — receiver is just a param.)
2. If a type has both an instance method and an extension with the same signature, which wins? (Instance.)
3. How do extension methods interact with interfaces? (You can extend interfaces — e.g., LINQ on `IEnumerable<T>`.)
4. Are extension methods a runtime feature? (No — compiler rewrite.)

### Memory Trick

**"Extension methods are sugary static calls wearing an instance-method costume."**

---

## 3.13 Cancellation Tokens

### Interview Answer (30–45 seconds)

> "`CancellationToken` is the cooperative cancellation contract: a source (`CancellationTokenSource`) signals, and long-running operations *observe* the token via `ThrowIfCancellationRequested()`, `Register`, or by passing it down to `await`-able calls. It's cooperative — nothing is force-killed; if a token is canceled, whoever checks reacts. The patterns I rely on: `CancellationTokenSource.CreateLinkedTokenSource` to combine a request abort with an app timeout, `CancelAfter` for timeouts, `OperationCanceledException`/`TaskCanceledException` handling, and the ASP.NET Core `HttpContext.RequestAborted` token wired through controllers. The senior rule: every `async` method that can block on I/O takes a token and passes it to the I/O, so shutdowns and client disconnects stop work instead of leaking it."

### Detailed Explanation

**The API surface:**

- `CancellationTokenSource` — owns the state; `Cancel()`, `CancelAfter(ms)`, `CancelAfter(TimeSpan)`.
- `CancellationToken` — a cheap struct passed around; `IsCancellationRequested`, `CanBeCanceled`, `ThrowIfCancellationRequested()`, `Register(Action)`, `WaitHandle`.
- `CreateLinkedTokenSource(token1, token2)` — combine multiple signals.
- `OperationCanceledException` / `TaskCanceledException` (subclass) — the cancellation channel; `TaskCanceledException` often signals a timeout (its `CancellationToken`).

**Cooperative contract:**

- The caller requests cancellation; the callee must *check*. Nothing interrupts a blocked synchronous call (except `WaitAsync` with timeout).
- `await someTask.WaitAsync(cancellationToken)` — .NET 6+ adds cancellation to tasks that don't natively support it (with a timeout or explicit token).
- Registered callbacks run on the thread that cancels (or a queued context) — keep them fast.

**Timeout patterns:**

- `using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));`
- `WaitAsync(TimeSpan.FromSeconds(5))`.
- Distinguish *timeout* from *cancellation* in logs: `catch (OperationCanceledException) when (token.IsCancellationRequested)` vs generic.

**ASP.NET Core:**

- `HttpContext.RequestAborted` — auto-canceled when the client disconnects. Pass it into EF queries, HTTP calls, Redis calls.
- `[CancellationToken]` action parameter injection.
- Graceful shutdown: hosted services get a token for `StopAsync`.

**Anti-patterns:**

- Swallowing `OperationCanceledException` at boundaries as if it were an error.
- Creating a `CancellationTokenSource` and never disposing (its timer/registration resources).
- Blocking on `.Wait()` with cancellation (blocking beats cancellation's purpose).

### Real World Example (Healthcare)

A FHIR search endpoint that must respect client disconnects and enforce a server-side cap:

```csharp
[HttpGet("patients")]
public async Task<IActionResult> Search(
    [FromQuery] string? mrn,
    [CancellationToken] CancellationToken ct)      // linked to RequestAborted
{
    var results = await _search.FindAsync(x => x.Mrn == mrn, ct);
    return Ok(results);
}
```

### Production Code Example

```csharp
public sealed class FhirGateway
{
    private readonly HttpClient _http;

    public async Task<Patient> GetPatientAsync(string id, CancellationToken ct)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        cts.CancelAfter(TimeSpan.FromSeconds(10));   // server-side cap

        try
        {
            using var response = await _http.GetAsync($"/Patient/{id}", cts.Token);
            response.EnsureSuccessStatusCode();
            return (await response.Content.ReadFromJsonAsync<Patient>(cts.Token))!;
        }
        catch (OperationCanceledException) when (cts.IsCancellationRequested && !ct.IsCancellationRequested)
        {
            throw new TimeoutException("FHIR gateway timed out");  // caller asked → timeout
        }
    }
}
```

**Key lines explained:**

- `CreateLinkedTokenSource` — client cancellation OR server timeout cancels the work.
- `CancelAfter(10s)` — hard ceiling for a downstream call.
- The `when` filter distinguishes "caller canceled" from "we timed out."
- Every `await` passes the token — cancellation propagates into the HTTP call itself.

### Internal Working

- `CancellationTokenSource` holds a `volatile`-ish `_state` and a registration list; `Cancel()` runs callbacks (in a special registration order) and triggers the linked sources.
- Tokens are cheap structs wrapping the source.
- `ThrowIfCancellationRequested` throws `OperationCanceledException` carrying the token.
- Timer-based `CancelAfter` uses a `Timer`.

### Advantages

- Graceful, cooperative shutdown; no resource leaks; testable timeouts.
- Propagates through an async chain naturally.

### Disadvantages

- Only cooperative (blocked sync code isn't interrupted).
- Registering many callbacks can be costly.
- Requires discipline: you must *thread the token through*.

### Best Practices

- Accept a `CancellationToken` param on every async I/O method.
- Use `WaitAsync` to bound tasks that don't support cancellation natively.
- Handle `OperationCanceledException` distinctly from errors.
- Dispose CTS (timers/registrations).
- Wire `RequestAborted` in controllers.

### Common Mistakes

- Not checking/passing the token → leaked work during shutdown (the "graceful shutdown hangs" bug).
- Catching `OperationCanceledException` and logging as error → alert spam.
- `new CancellationTokenSource().CancelAfter(...)` without disposal.
- Canceling then disposing the CTS before awaited work observes it.

### Interview Follow-up Questions

1. Cooperative vs. preemptive cancellation — which is .NET? (Cooperative.)
2. What's the difference between `OperationCanceledException` and `TaskCanceledException`? (Subclass; TaskCanceledException often = timeout.)
3. How does `RequestAborted` work? (Kestrel links it to connection close.)
4. What is `CreateLinkedTokenSource` for? (Combine signals.)
5. How do you add cancellation to a non-cancellable task? (`WaitAsync`.)

### Senior Level Talking Points

> "Cancellation is a *distributed* contract in a healthcare platform: client disconnect, Kubernetes termination signal, and a 5-second downstream timeout must all map to the same token graph. I wire `RequestAborted` into every query, use linked sources with `CancelAfter` at each boundary, and treat `OperationCanceledException` as a *flow-control* exception — never a bug. The failure mode I hunt for in reviews is swallowed cancellation, because that's how a 'simple client refresh' becomes a zombie query holding a DB connection hostage."

### Memory Trick

**"Cancellation is a polite request — the work must agree to stop."**

---

## Chapter 3 Wrap-Up

### Top 10 Interview Questions From This Chapter

1. Delegate vs. event — what can each do outside the declaring class?
2. How does `+=` build a multicast delegate and why can a throwing subscriber break others?
3. `Func<T,bool>` vs `Predicate<T>` — any difference?
4. Explain closures and the loop-capture bug.
5. How does the `async` state machine work? When does it allocate?
6. `Task` vs `ValueTask` — when would you return each?
7. How do `yield` iterators defer execution? Where do exceptions surface?
8. Expression trees vs. delegates — why does EF need `Expression<>`?
9. `Span<T>` vs `Memory<T>` — placement rules and use cases.
10. How does a `CancellationToken` propagate through an async chain?

### Revision Notes (1 page)

- **Delegates/events:** delegate = method reference (multicast via `Delegate.Combine`); event = protected delegate (add/remove only, raise only inside class). Snapshot before invoking; unsubscribe on Dispose.
- **Func/Action/Predicate:** Func returns, Action void, Predicate = `Func<T,bool>` legacy. Stateless lambdas compile to cached static delegates; capturing lambdas create closure classes (heap).
- **Generics:** type safety + no boxing + no duplication; constraints (`class/struct/new()/interface/unmanaged/Enum`); variance only on interfaces/delegates (`out`=covariant read, `in`=contravariant write); value types specialize, reference types share.
- **Async/await:** compiler state machine; await returns to caller; continuation posted to SyncContext/thread pool; ASP.NET Core has no SyncContext; `ConfigureAwait(false)` is a library convention; exceptions rethrown at resume; never `.Wait()`/`.Result`.
- **ValueTask:** struct, zero-alloc on sync-success, single-await contract, for hot paths only.
- **yield:** lazy streaming iterator; body runs on `MoveNext`; validate in eager wrapper; no `yield` in `try/catch`.
- **Reflection:** runtime metadata; `Invoke` slow → compile+ cache delegates; source generators replace most reflection; AOT/trimming hostile.
- **Expression trees:** data-shaped code; `Expression<Func<>>` → provider translation (EF→SQL); statements/await not allowed; keep predicates translatable.
- **Pattern matching:** type/property/relational/list/logical; switch expressions exhaustive; guards `when`.
- **Span/Memory:** Span = ref struct stack-only zero-copy view; Memory = heap-safe for async/fields; stackalloc small buffers; the low-alloc backbone.
- **Tuples:** ValueTuple struct; local grouping; records across boundaries.
- **Extension methods:** compile-time sugar; instance wins; utilities/fluent only.
- **Cancellation:** cooperative; CTS + linked sources + CancelAfter; pass token through every await; distinguish timeout vs. cancel.

### Things Interviewers Expect From 5+ Years Experience

- Deep understanding of *how* async works (state machine, SyncContext) — not just "async/await makes it faster."
- Knowledge of allocation behavior and when to reach for `ValueTask`, spans, and source generators.
- The ability to explain *why* expression trees are required for EF translation and where client-eval breaks.
- Cancellation threaded through APIs as a default, not an afterthought.
- Honest tradeoffs: when reflection/events/tuples are the *wrong* tool.

### Cheat Sheet

```
DELEGATE = method reference (multicast)
EVENT    = delegate + add/remove only; raise inside class only
FUNC returns | ACTION void | PREDICATE = Func<T,bool>

CLOSURE: lambda captures → compiler class on heap; loop-capture fixed C#5
STATELESS LAMBDA → static method + cached delegate (free)

ASYNC:
  await returns to caller (no block)
  state machine struct boxed on first suspension
  SyncContext: ASP.NET Core = none → ConfigureAwait(false) optional in libs
  NEVER .Wait()/.Result (deadlock/thread starvation)
  async void only for event handlers

VALUETASK: hot paths with sync-success; single-await; no caching
TASK: general purpose; cacheable; multi-await

YIELD: lazy; runs on MoveNext; eager wrapper for validation
REFLECTION: slow Invoke → cached compiled delegates; source-gen preferred
EXPRESSION: data tree; EF translates; statements/await banned
IQueryable + Expression<Func<>>  = server-side; Func = client-side

PATTERNS: is { Prop: val } | switch { guard } | [head, ..] lists

SPAN = ref struct (stack-only, zero-copy view)
MEMORY = heap-safe (fields/async)
stackalloc: small (<1KB) unmanaged buffers only

CANCELLATION: cooperative; linked sources; CancelAfter; pass token; OCE != bug
```

### Flash Cards

**Q1:** Can you invoke an event outside its class? **A:** No — only `+=`/`-=`; raises only inside.

**Q2:** Stateless lambda allocation? **A:** None — compiler caches one static delegate.

**Q3:** When does an async method allocate? **A:** On first real suspension (incomplete await); sync-success = no alloc.

**Q4:** `ConfigureAwait(false)` in ASP.NET Core? **A:** Mostly a no-op (no SyncContext); library convention.

**Q5:** Why EF needs `Expression<>`? **A:** To translate the tree to SQL instead of executing it.

**Q6:** Can `Span<T>` be a class field? **A:** No — `ref struct`, stack-only. Use `Memory<T>`.

**Q7:** `yield return` inside `try/catch`? **A:** Not allowed; only `try/finally`.

**Q8:** Covariance keyword? **A:** `out T` (output positions); contravariance `in T` (input).

**Q9:** `Task` vs `ValueTask` multi-await? **A:** Task yes; ValueTask single-use by contract.

**Q10:** Cooperative cancellation means? **A:** The callee must observe the token; nothing is force-killed.

### Interview Confidence Score

**Medium-Hard.** Advanced C# is where 5+ year developers are separated from 2-year developers. Expect deep async internals, allocation reasoning, and design-tradeoff questions. Know the mechanisms *and* when to apply them.

---

*Continue → Chapter 4: LINQ*
