# Chapter 6: Memory Management & Garbage Collection

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** How the GC works (mark & sweep, generations, segments, LOH), reachability and roots, `IDisposable`/`IAsyncDisposable` and the dispose pattern, finalizers vs. `SafeHandle`, `GC.KeepAlive`, memory leak causes, `ArrayPool<T>` and pooled buffers, allocation analysis with dotnet-counters/PerfView, `WeakReference`, and when to tune GC settings.

---

## 6.1 How the Garbage Collector Works

### Interview Answer (30–45 seconds)

> "The .NET GC is a non-deterministic, mark-and-sweep (with compaction), generational collector. It tracks *reachability* from roots — static fields, thread stacks, and CPU registers — and any object not reachable from a root is garbage. To make collection fast, it uses generations: Gen 0 holds short-lived objects (the bulk), Gen 1 and Gen 2 hold survivors; a Gen-0 collection is cheap and frequent, a Gen-2 collection is expensive and rare. Objects ≥85 KB go to the Large Object Heap (LOH), which is collected as Gen 2 but *not compacted* by default. When an allocation can't fit in the current segment, the GC triggers a collection and may return memory to the OS. Workstation vs. server GC changes concurrency and per-heap behavior; in ASP.NET Core on multi-core, server GC (the default) gives each core its own heap, reducing contention."

### Detailed Explanation

**The big picture (why GC exists):**

- Manual memory management (`malloc`/`free`) is error-prone (use-after-free, leaks, double-free). The GC trades non-deterministic cleanup for safety: objects that become unreachable are reclaimed automatically.
- Managed reference tracking means no memory corruption (safe memory model); the tradeoff is the cost of *finding* garbage.

**Generations (the core trick):**

- New allocations land in Gen 0. Most objects die young (statistical "generational hypothesis" — most objects are short-lived).
- Gen-0 GC is cheap: it only scans what's reachable from roots into Gen 0 (roughly the young set) and promotes survivors to Gen 1.
- Gen 1 = a mid-life buffer; survivors go to Gen 2.
- Gen 2 = the "old" objects; collecting it requires scanning the *entire* graph including Gen 0/1 references (card tables help track cross-gen references) — it's the expensive one.
- A full GC = Gen 2 + LOH collection.

**Segments and allocation:**

- Heap is divided into *segments* (reserved memory regions); Gen 0/1 live in "ephemeral segments"; LOH has its own segments.
- Allocation is a *bump pointer* on Gen 0 — fast, cache-friendly, lock-free-ish (with per-heap segments under server GC, plus a "hot region" allocation).
- When Gen 0 is full → GC (promote survivors, compact, start fresh).

**Mark & sweep (with compaction):**

1. **Mark:** walk from roots, mark reachable objects (bits in object headers / dedicated bitmaps).
2. **Sweep:** scan the heap, and either (a) *compact* — move surviving objects to the front, updating references (this is why managed pointers/refs must be GC-aware), or (b) *sweep in place* — build free lists of dead blocks without moving.
3. Compaction is good for fragmentation but costs copies (and pauses); that's why LOH isn't compacted by default (big arrays are expensive to copy; instead it uses free lists — this can lead to LOH fragmentation).

**Roots:**

- Static fields, thread-local statics, local variables / args on thread stacks (including those in *frames* that the JIT knows are live), CPU registers, the finalizer queue (objects pending finalization are roots *while* they wait), handles (GCHandle, pinned handles).

**Pausing / Workstation vs Server GC:**

- **Workstation GC:** default for console/desktop; concurrent (background) collection; more pauses under high allocation.
- **Server GC (`ServerGarbageCollection=true` in runtime config):** default for ASP.NET Core; a heap + dedicated GC thread *per logical core*; each thread allocates into its own heap → less contention; uses more memory (each heap is a full segment); can have higher peak memory.
- **Background GC (from .NET 4.0, GCConcurrent=true):** old-gen collection runs on a background thread while Gen 0/1 continue; reduces perceived pauses. On Server GC the "background" phase still runs on per-heap threads.
- **Pauses:** the GC stops *mutator threads* (the threads running app code) at certain points (a stop-the-world phase for marking roots, or the compact move). The famous "GC pause" tail-latency spike.
- **`LatencyMode`** (SustainedLowLatency, Interactive, Batch, NoGCRegion) — trade pause frequency vs. memory. In containers, consider `GCHeapHardLimit`.

**Why this matters for an API:**

- High allocation rate → frequent Gen-0 GCs → more total pause time → worse tail latency.
- Gen-2/LOH churn is the killer (large byte arrays, string building at scale, unbounded caches).
- The *rate* of allocation is the lever you control, not the GC itself.

### Real World Example (Healthcare)

A FHIR ingestion service serializing tens of thousands of large `Observation` resources to JSON. Without attention: each serialization allocates buffers; large strings/arrays go to LOH; peak memory balloons and p95 latency spikes every time a full GC runs. The fix was pooled buffers (`ArrayPool<byte>`), `JsonSerializer` source-gen (fewer reflections/allocations), and keeping the working set inside one heap.

### Production Code Example

```csharp
// Allocation-conscious code: reuse buffers via ArrayPool, not per-call new byte[]
public static byte[] EncodeHl7(string message, out byte[]? pooled)
{
    var buffer = ArrayPool<byte>.Shared.Rent(Encoding.UTF8.GetByteCount(message));
    var written = Encoding.UTF8.GetBytes(message, buffer);
    pooled = buffer;                       // caller returns it
    return buffer.AsSpan(0, written).ToArray();  // NOTE: only if needed; prefer span
}
```

(For correctness, prefer spans end-to-end; the point is the *rent/return* discipline.)

**Key lines explained:**

- `ArrayPool<byte>.Shared.Rent(n)` — reuses a pooled array instead of allocating each time.
- The caller must `Return(buffer)` — a discipline, not a free lunch.
- Gen-0/LOH pressure drops because big buffers are recycled.

### Internal Working (sequence for a Gen-0 GC)

1. Allocation bumps into Gen 0; segment fills → GC enters.
2. Suspend mutator threads (or use background GC for Gen 2).
3. Mark: traverse object graph from roots (stacks are walked with JIT-visible liveness info; card tables flag cross-gen refs).
4. Plan: decide what survives; compute compaction addresses.
5. Sweep/compact: move survivors (updating references), update allocation pointers, free dead segments back if possible.
6. Resume threads; raise `GC.CollectionCount` counters.

### Advantages

- Safety (no dangling pointers/use-after-free), simpler code, no manual free.
- Generations make typical workloads cheap; compaction fights fragmentation.

### Disadvantages

- Non-deterministic pauses (tail latency), memory overhead (headers, alignment, segments), no control over *when*.

### Best Practices

- Measure allocation rate (`dotnet-counters`, PerfView); optimize the *hot allocation*.
- Prefer server GC on multi-core ASP.NET Core (default) — accept the memory tradeoff.
- For latency-sensitive services, watch Gen-2/LOH frequency; use pooled buffers and avoid large object churn.
- Don't call `GC.Collect()` in production code (except rare cases like memory pressure tests).

### Common Mistakes

- Calling `GC.Collect()` "to clean up" — pauses the world for nothing.
- Unbounded caches / static collections growing into Gen 2 → memory creep.
- Large byte arrays per request → LOH churn.
- Ignoring allocation rate because "memory is cheap."

### Interview Follow-up Questions

1. Why are there three generations? (Most objects die young; cheap young GCs.)
2. What's the LOH and why isn't it compacted by default? (≥85 KB; compaction cost vs. fragmentation tradeoff.)
3. Server vs. workstation GC — differences and defaults? (Per-core heaps vs single; server default in ASP.NET Core.)
4. What are roots? (Statics, stacks, registers, handles, finalizer queue.)
5. When would you ever call `GC.Collect()`? (Almost never; maybe at measured memory-pressure edge cases.)

### Senior Level Talking Points

> "The senior message: the GC isn't slow — *allocating* is what you control. I measure `gen-0/1/2 collections` and allocation bytes per request, and I fix the *source* of allocation, not the GC. In a healthcare API, a p99 latency spike that correlates with a full GC is almost always a design artifact — a query materializing a huge list, string building in a loop, an unbounded cache — not a GC setting problem. Fix the shape of the workload, keep Gen-2 quiet, and the GC becomes a non-event."

### Diagram

```
ALLOCATION → Gen 0 (bump pointer, cheap)
                 │  survives young GC
                 ▼
             Gen 1 (mid-life)
                 │  survives again
                 ▼
             Gen 2 (old) ──── expensive, full graph mark
                 │
LOH (>=85KB) ────┘  not compacted (free lists; fragmentation risk)

Roots: statics, thread stacks, registers, GC handles, finalizer queue
```

### Memory Trick

**"New things die young — the GC banks on it (generational bet)."**

---

## 6.2 Reachability, Roots, and Object Lifecycle

### Interview Answer (30–45 seconds)

> "An object is 'alive' if it's *reachable* from a root: a chain of references from a static field, a stack local, a CPU register, a GC handle, or the finalizer queue. The GC only collects unreachable objects. The practical consequences: a static field holding a collection keeps everything it references alive forever (the classic 'static cache = leak'), an event subscription from a long-lived object to a short-lived one keeps the subscriber alive (the 'event leak'), and a `Task` still referenced by a completion chain keeps its state machine alive. My mental model: reachability is a *graph* problem — I think in terms of who holds a reference, and I audit statics, event subscriptions, and caches for accidental roots."

### Detailed Explanation

**Roots, precisely:**

- **Static fields** — for the process lifetime (until the type is unloaded, which basically never for AppDomain-shared).
- **Thread stacks** — locals and arguments (live per JIT liveness analysis), including stack frames of suspended threads.
- **CPU registers** — the JIT keeps some refs in registers during a GC-safe point.
- **GC handles** — `GCHandle.Alloc(obj, GCHandleType.Normal)`, `Strong` handles; also `Weak` (non-root) vs `Pinned`.
- **The finalizer queue** — objects with finalizers are rooted until their finalizer runs.

**Reference types vs. structs:** structs are *inline*; they don't form independent nodes. Reference chains are through reference-type fields.

**The three classic leak patterns:**

1. **Static/global roots:** `static ConcurrentDictionary<string, BigData>` never collected. Fix: cache with eviction (bounded), or `ConditionalWeakTable` for keyed weak refs.
2. **Event subscriptions:** `longLived.Event += shortLived.Handler;` — the *publisher* holds the *subscriber* → the subscriber and its graph never collect. Fix: unsubscribe in `Dispose`/`Detach`, or use weak-event patterns.
3. **Async/Task chains:** an awaited `Task` chain, `TaskCompletionSource` retained, `Channel<T>` unbounded, or a captured closure retaining a big object.

**`WeakReference`:**

- `new WeakReference(obj)` — references without rooting; `Target` returns null after collection.
- Uses: caches (keep strong only while in use), `ConditionalWeakTable<TKey,TValue>` (attaches metadata to keys without rooting them — the key's value dies with the key).

**Keeping alive:**

- `GC.KeepAlive(obj)` — marks the object as live to the end of the method; prevents premature finalization (rarely needed in managed-only code; matters with finalizers + interop).
- `GCHandle.Alloc(obj, GCHandleType.Pinned)` — pins for interop (the object won't move; prevents compaction of that region).

### Real World Example (Healthcare)

A chat/monitoring hub: `MonitorService` (long-lived singleton) with `event AlertRaised;` — every page subscribed a `HubConnection`; when a clinician disconnected but forgot to unsubscribe, the `HubConnection` (and its whole graph) stayed alive, and memory grew per clinician. The fix: subscribe in `OnConnectedAsync`, unsubscribe in `OnDisconnectedAsync`.

### Production Code Example

```csharp
// ConditionalWeakTable — attach data to a key without rooting it
public sealed class AttachmentRegistry
{
    // key's lifetime controls value's lifetime (they die together)
    private static readonly ConditionalWeakTable<Patient, CarePlanAttachment> _plans = new();

    public static CarePlanAttachment? Get(Patient p) => _plans.TryGetValue(p, out var v) ? v : null;
    public static void Set(Patient p, CarePlanAttachment plan) => _plans.AddOrUpdate(p, plan);
}

// Event subscription hygiene
public sealed class AlertPublisher : IDisposable
{
    public event EventHandler<AlertEventArgs>? AlertRaised;
    public void Dispose() => AlertRaised = null;      // drop all subscribers on shutdown
}

// Weak cache example (bounded strongly, evicts via weakness)
public sealed class WeakResultCache
{
    private readonly ConditionalWeakTable<string, object> _cache = new();
    public bool TryGet(string key, out object? value) => _cache.TryGetValue(key, out value);
}
```

**Key lines explained:**

- `ConditionalWeakTable` doesn't *root* the key — when the patient object is collected, the attached plan can also go (no leak).
- `Dispose` clearing the event drops all subscriber references at once.
- Weak caches trade memory for eviction safety.

### Internal Working

- Reachability scan = graph traversal from roots; the GC does *not* track "who references whom" on every mutation — it computes reachability at collection time by walking.
- Card tables: per-region bits marking Gen-0/1 references into Gen 2, so a Gen-0 collection doesn't have to scan all of Gen 2 for roots.

### Best Practices

- Audit statics for accidental long-lived roots.
- Unsubscribe events in `Dispose`/scoped lifecycle.
- Use `ConditionalWeakTable` for keyed metadata; use bounded caches with eviction.
- Use `WeakReference` for optional memoization.

### Common Mistakes

- Static collections without eviction.
- Forgetting to unsubscribe (the #1 .NET "leak").
- Holding `Task`/`Lazy<T>` references to large graphs.
- `GCHandle` not freed (`Free()`) in interop code.

### Interview Follow-up Questions

1. Name three things that count as roots.
2. Why do event subscriptions leak? (Publisher → subscriber strong reference.)
3. What is `ConditionalWeakTable` for? (Attach data to keys without rooting them.)
4. When do you need `GC.KeepAlive`? (Finalizers + interop edge cases.)
5. Can a `WeakReference` target be resurrected? (If a finalizer re-roots it — resurrection.)

### Senior Level Talking Points

> "Memory 'leaks' in .NET are almost always *root leaks* — something long-lived holds a reference. The senior debug ritual: take a dump, run `dotnet-dump analyze`, `clrstack`/`gcroot` to find who roots the objects, and usually it's a static cache or an event subscription. I design for it: bounded caches, explicit unsubscription, and `ConditionalWeakTable` for attached metadata. In healthcare, where per-session clinician contexts accumulate, getting this wrong is a slow OOM that takes down a shift's monitoring UI."

### Memory Trick

**"Reachable = alive; roots are the tent pegs holding the graph down."**

---

## 6.3 `IDisposable`, `IAsyncDisposable`, and the Dispose Pattern

### Interview Answer (30–45 seconds)

> "`IDisposable` gives deterministic cleanup for unmanaged resources (file handles, sockets, DB connections): `Dispose()` releases them, and `using` guarantees it runs even when an exception is thrown. `IAsyncDisposable` extends this to async cleanup (`await using`), because you can't `await` inside `Dispose()`. The dispose pattern (`Dispose(bool)`, `protected virtual void Dispose(bool)`, finalizer) is mostly legacy now — modern .NET says: use `SafeHandle` for the unmanaged resource and you rarely need a finalizer; make the type `sealed` or provide the pattern carefully. The senior rules: only implement `IDisposable` if you own a resource; make disposal idempotent; never throw from `Dispose`; and for dependency-injected objects let the container own the lifecycle."

### Detailed Explanation

**When to implement `IDisposable`:**

- You own an *unmanaged* resource directly (via `SafeHandle` or a P/Invoke handle), OR
- You own *other* `IDisposable` fields that must be cleaned (composition).
- If you only *use* a disposable (like `HttpClient`, `DbContext`), you don't implement it — you manage usage with `using`.

**`IDisposable`:**

```csharp
public sealed class ReportBuilder : IDisposable
{
    private readonly FileStream _stream;     // owned resource
    public ReportBuilder(string path) => _stream = File.Create(path);
    public void Dispose() => _stream.Dispose();   // idempotent
}
```

- `using var` / `using (var x = ...)` / `await using var`.
- Compiles to `try/finally`.
- `Dispose()` must be *idempotent* (safe to call multiple times) and must *not throw*.
- `GC.SuppressFinalize(this)` — stops the finalizer queue entry (the type doesn't need finalization after explicit dispose).

**`IAsyncDisposable`:**

```csharp
public sealed class BatchWriter : IAsyncDisposable
{
    public async ValueTask DisposeAsync()
    {
        await _writer.FlushAsync();
        _writer.Dispose();
    }
}
```

- `await using var batch = new BatchWriter(...);`
- Why async dispose exists: `Dispose()` can't `await`; flushing a stream, closing a pool connection, unsubscribing — these are async and blocking inside `Dispose` is bad.

**The dispose pattern (legacy) and why modern code avoids the finalizer part:**

- `protected virtual void Dispose(bool disposing)`, public `Dispose()`, finalizer `~Type()` calling `Dispose(false)`.
- The finalizer is a *safety net* for forgotten `Dispose()` calls on unmanaged resources.
- Modern guidance: wrap the unmanaged resource in a `SafeHandle` (which has its own finalizer). Then your class doesn't need a finalizer — the `SafeHandle` will release the OS handle even if `Dispose()` is forgotten. This makes the pattern simple: `Dispose()` just calls `SafeHandle.Dispose()`.
- If you DO have a finalizer: `Dispose()` should `SuppressFinalize`, and finalizers must never throw, and never access other managed objects (finalizer ordering is undefined).

**Lifecycle ownership:**

- In DI, `IDisposable`/`IAsyncDisposable` instances registered are disposed by the container when appropriate (scoped → at request end; singleton → at app shutdown). Don't double-dispose manually AND via container (double disposal must be safe anyway).

### Real World Example (Healthcare)

A FHIR batch export:

```csharp
await using var exporter = new FhirBatchExporter(outputPath);   // owns the file
await exporter.AddAsync(patient);
await exporter.FlushAsync();
// DisposeAsync flushes + closes
```

A `SqlConnection` usage (owned temporarily):

```csharp
using var conn = new SqlConnection(connString);
await conn.OpenAsync(ct);
using var cmd = conn.CreateCommand();
...
```

### Production Code Example

```csharp
public sealed class FhirBatchExporter : IAsyncDisposable
{
    private readonly StreamWriter _writer;
    private bool _disposed;

    public FhirBatchExporter(string path)
    {
        _writer = new StreamWriter(File.Create(path), new UTF8Encoding(false));
    }

    public Task AddAsync(FhirResource resource, CancellationToken ct)
    {
        ThrowIfDisposed();
        return _writer.WriteAsync(resource.Serialize(), ct);
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;                 // idempotent
        await _writer.FlushAsync();            // async cleanup — the reason for IAsyncDisposable
        await _writer.DisposeAsync();
        _disposed = true;
    }

    private void ThrowIfDisposed()
        => ObjectDisposedException.ThrowIf(_disposed, this);
}
```

**Key lines explained:**

- `IAsyncDisposable` because flush is async — `Dispose()` couldn't flush properly.
- Idempotent via `_disposed` flag.
- `ObjectDisposedException.ThrowIf` — modern guard (no custom logic needed).
- Ownership is clear: the exporter owns the writer; it disposes it.

### Advantages / Disadvantages

| | IDisposable | IAsyncDisposable |
|---|---|---|
| Cleanup | sync | async-capable |
| Syntax | `using` | `await using` |
| When | sync resources | streams, pools, async close |
| Both? | Many types implement both | — |

### Best Practices

- Implement only when you *own* a resource.
- `sealed` types: simple `Dispose()`. Non-sealed: consider the pattern.
- Never throw from `Dispose`; keep it idempotent.
- Prefer `SafeHandle` so you don't need finalizers.
- Let DI own the lifecycle of registered instances.

### Common Mistakes

- Finalizer that touches managed objects or throws.
- Non-idempotent `Dispose` (double-dispose bugs with DI).
- Blocking (`.Wait()`) inside `Dispose` instead of `IAsyncDisposable`.
- Implementing `IDisposable` when you don't own a resource.

### Interview Follow-up Questions

1. Why can't you `await` inside `Dispose()`? (It's `void`; hence `IAsyncDisposable`.)
2. When does a finalizer still make sense? (Unmanaged resource not wrapped in SafeHandle — rare now.)
3. What does `SuppressFinalize` do and why call it? (Prevents finalizer running after explicit dispose.)
4. Who disposes DI-registered `IDisposable` objects? (The container per its lifetime.)
5. `IDisposable` + `IAsyncDisposable` together — how do they interact? (Both called; often `DisposeAsync` calls into shared cleanup.)

### Senior Level Talking Points

> "The modern discipline: `SafeHandle` owns the OS handle, your class owns `SafeHandle` — so you *don't need finalizers*, and the pattern collapses to 'Dispose my owned disposables.' And I treat async cleanup as a first-class concern: any type that flushes or closes something asynchronously implements `IAsyncDisposable`, because blocking in `Dispose` is exactly how 'graceful shutdown' becomes 'hang.' In healthcare batch jobs this is the difference between a clean checkpointed shutdown and a corrupted export file."

### Memory Trick

**"using guarantees cleanup; IAsyncDisposable lets that cleanup be async."**

---

## 6.4 Finalizers vs. `SafeHandle` vs. `GC.KeepAlive`

### Interview Answer (30–45 seconds)

> "A finalizer (`~Class()`) is a last-resort cleanup that runs *later, on a separate finalizer thread*, when the GC detects the object is unreachable — never on demand, never in a deterministic order. Because finalizers resurrect the object onto the finalizer queue, they delay collection and can hide bugs. The modern answer is `SafeHandle`: a `SafeHandle`-derived type wraps the OS handle and owns its own finalizer, so your *class* doesn't need one — the handle gets released even if you forget `Dispose()`. `GC.KeepAlive(obj)` just marks the object live to the end of the method, preventing premature finalization — almost never needed in managed-only code, but relevant at interop edges."

### Detailed Explanation

**Finalizer mechanics:**

- `~Type()` compiles to `Finalize()`.
- On GC: objects with finalizers are *not* collected directly — they're placed on the *finalization queue*, which is a root. A dedicated finalizer thread runs their `Finalize()`; after that, on a *later* collection, the object can be reclaimed. So finalizable objects take at least 2 GC cycles to die.
- **Resurrection:** if `Finalize()` re-roots the object (assigns it to a static), the object survives. `GC.ReRegisterForFinalize` enables multiple finalizations (rare).
- Finalizers run in an *undefined order* and on a non-deterministic thread → never touch managed resources from a finalizer (they may already be finalized).
- Finalizers must not throw (would terminate the process... in .NET Core, an exception in a finalizer terminates the process).

**Why `SafeHandle` replaced manual handles:**

- `SafeFileHandle`, `SafeSocketHandle`, `SafeWaitHandle` — each wraps a raw handle, implements its own finalizer, and exposes `IsInvalid`/`IsClosed` + `DangerousAddRef`/`Release` for interop pinning.
- Your class: `Dispose()` → `_handle.Dispose()`. If you forget → the SafeHandle finalizer releases the OS handle anyway. Correctness without a custom finalizer.
- For custom OS resources: derive from `SafeHandleZeroOrMinusOneIsInvalid` and override `ReleaseHandle()` to call the OS close function.

**`GC.KeepAlive`:**

- `GC.KeepAlive(obj)` — a no-op call that ensures `obj` is live at the GC-safe-point at that line. Prevents the JIT from collecting/finalizing an object whose last *use* was earlier in the method while an interop call still uses the native handle.
- Rarely needed in managed-only code (the GC only reclaims what's provably dead, but JIT liveness can end "early" at interop boundaries).
- The JIT/GC liveness analysis can decide an object is dead right after its last use — `KeepAlive` pins the liveness to the end of the method.

### Real World Example (Healthcare)

Interop to a native medical device SDK:

```csharp
// Native handle released by SafeHandle, not a custom finalizer
var handle = DeviceApi.AcquireSession();
var safe = new DeviceSessionHandle(handle, ownsHandle: true);
try { DeviceApi.StartStream(safe); }
finally { safe.Dispose(); }   // or rely on finalizer as safety net
```

### Production Code Example

```csharp
// Custom SafeHandle (modern unmanaged-resource ownership)
internal sealed class DeviceSessionHandle : SafeHandleZeroOrMinusOneIsInvalid
{
    private DeviceSessionHandle() : base(ownsHandle: true) { }

    protected override bool ReleaseHandle()
        => DeviceApi.ReleaseSession(handle);   // returns success bool
}

// Using it — the class implements IDisposable but has NO finalizer
public sealed class DeviceSession : IDisposable
{
    private readonly DeviceSessionHandle _handle;
    public DeviceSession() => _handle = DeviceApi.AcquireSessionSafe();

    public void Dispose() => _handle.Dispose();     // idempotent; SafeHandle has finalizer
}
```

**Key lines explained:**

- `ReleaseHandle` override — the single place the OS handle is released.
- The class needs no finalizer — `SafeHandle` covers the forgotten-dispose case.
- `IDisposable` only disposes the owned SafeHandle.

### Internal Working

- Finalizer queue: objects with finalizers enter it on allocation; GC moves them to *freachable queue* when unreachable; finalizer thread drains it; next GC can reclaim.
- SafeHandle finalizer → ReleaseHandle → OS close. P/Invoke marshaller treats SafeHandle refs specially (keeps them alive during the native call).

### Best Practices

- Wrap raw handles in `SafeHandle` derivatives.
- Don't write finalizers in new code unless you've exhausted SafeHandle options.
- If you must have a finalizer: only release unmanaged state, never throw, call `SuppressFinalize` in `Dispose`.
- Use `GC.KeepAlive` only where JIT liveness vs. native lifetime could disagree.

### Common Mistakes

- Writing finalizers that touch managed objects.
- Not calling `SuppressFinalize` in `Dispose` (finalizer still runs).
- Finalizer throwing → process death.
- Relying on finalizers for timely cleanup (they're *not* timely).

### Interview Follow-up Questions

1. Why do finalizable objects live longer? (Two GC cycles: finalize then reclaim.)
2. What's the modern replacement for finalizers? (`SafeHandle`.)
3. What is resurrection? (Finalizer re-roots the object.)
4. When do you actually need `GC.KeepAlive`? (Interop liveness edge cases.)
5. Can a finalizer run on the UI thread? (No — dedicated finalizer thread.)

### Senior Level Talking Points

> "The senior answer is to *design finalizers out*. In .NET 8, `SafeHandle` + `GC.SuppressFinalize` means your classes rarely need a finalizer, and the dispose pattern collapses to its simple form. When I see a `~Class()` in review, I ask: 'is this unmanaged state not wrapped in a SafeHandle?' — if it is, the finalizer is dead weight that adds a GC cycle to every instance. In healthcare device integration, correct handle ownership is a reliability question: a leaked `DeviceSessionHandle` means a device stays busy and a clinician can't start a scan."

### Memory Trick

**"Finalizer = 'cleanup later, maybe twice'; SafeHandle = 'cleanup for sure, once, wrapped.'"**

---

## 6.5 Memory Leaks, `GC.Collect`, and Debugging Memory

### Interview Answer (30–45 seconds)

> "A .NET 'memory leak' is usually a root leak — a long-lived reference keeps objects reachable — or unbounded growth from caches/static collections/large buffers. The debugging toolbox: `dotnet-counters` for live metrics (alloc bytes, GC pressure, LOH size), `dotnet-dump` + `dotnet-dump analyze` (or `SOS`) to look at `heapstat` and `gcroot` for who roots what, and PerfView for allocation profiles. The discipline: measure first (is it really growing?), find the root, fix the design. `GC.Collect()` is not a fix — it's a pause that hides the leak for one cycle."

### Detailed Explanation

**Common leak patterns (real-world ranking):**

1. **Static/global references** — static collections, static caches without eviction, static lazy singletons holding big graphs.
2. **Event subscriptions** — publisher outlives subscriber; subscriber never unsubscribed.
3. **Async / Task retention** — a `Task` held by a timer/`CancellationTokenSource` registration chain, `TaskCompletionSource` never completed, `Channel<T>` unbounded, `ConcurrentQueue` workers retaining work.
4. **`CancellationTokenSource` registration leaks** — registering with a long-lived CTS and never disposing leaves delegates retained.
5. **String interning of dynamic data** (Chapter 1) — interned strings never die.
6. **`DataTable`/`DataSet` (legacy)** — big object graphs in Gen 2.
7. **LOH fragmentation** — not strictly a leak, but memory appears "held."
8. **Closure captures** in a loop accumulating.

**Tooling:**

- `dotnet-counters monitor --counters System.Runtime` — `gen-0/1/2-collections`, `alloc-rate`, `loh-size`, `working-set`.
- `dotnet-dump collect` → `dotnet-dump analyze` with `clrheapstat`, `dumpheap -stat`, `gcroot <addr>` — find what roots an object.
- `dotnet-gcdump` — snapshot heap graph, open in analyzer to see who holds what.
- PerfView (Windows) — ETW allocation sampling.
- On the app side: `GC.GetTotalMemory`, `GC.GetGCMemoryInfo()`, `GC.CollectionCount(0/1/2)` for self-monitoring + metrics.

**`GC.Collect()`:**

- Almost always wrong in production. It pauses all threads, and doesn't prevent the leak (the root is still there).
- Legit uses: memory-pressure tests, `NoGCRegion` latency experiments, one-time startup cleanup of Gen 0/1 churn (still usually unnecessary).
- Better: reduce allocation rate, fix roots, tune `ServerGarbageCollection`/`GCHeapHardLimit` for containers.

**`GC.AddMemoryPressure`/`RemoveMemoryPressure`:** for native memory held by managed wrappers (so the GC counts it in the memory-budget math). Useful for large native buffers.

### Real World Example (Healthcare)

Symptom: monitoring service's memory grows linearly with clinician connections; OOM-kill at ~2 GB. `dotnet-dump analyze` + `gcroot` showed `AlertPublisher` (singleton) → event → `HubConnection` graphs. Unsubscribing in `OnDisconnectedAsync` fixed it. The leak wasn't "in the GC" — it was a root.

### Production Code Example

```csharp
// Self-monitoring a cache (avoid unbounded growth)
public sealed class BoundedCache<TKey, TValue>
{
    private readonly Dictionary<TKey, CacheEntry<TValue>> _map = new();
    private readonly int _maxSize;

    public bool TryGet(TKey key, out TValue? value)
    {
        if (_map.TryGetValue(key, out var entry) && entry.ExpiresAt > DateTime.UtcNow)
        {
            value = entry.Value;
            return true;
        }
        value = default;
        return false;
    }

    public void Set(TKey key, TValue value, TimeSpan ttl)
    {
        if (_map.Count >= _maxSize && !_map.ContainsKey(key))
            EvictExpiredAndOldest();                 // bounded memory

        _map[key] = new CacheEntry<TValue>(value, DateTime.UtcNow + ttl);
    }

    // metric to alert on
    public long Size => _map.Count;
}
```

**Key lines explained:**

- TTL + max-size eviction → the cache cannot grow unbounded.
- A `Size` counter lets you alert when the cache is unusually large — observability first.

### Internal Working

- The GC returns memory to the OS lazily (segments are released when empty; the runtime may hold them for reuse). "Working set high" can be normal; check *private bytes* and allocation rate.
- Gen-2 growth + LOH growth → the "leak-shaped" heapstat.

### Best Practices

- Measure before changing anything: `dotnet-counters` 5 minutes, correlate with memory growth.
- Find the root with `gcroot`; fix the design.
- Bounded caches with TTL/eviction.
- Unsubscribe events; dispose CTS; avoid dynamic interning.
- Expose cache sizes / GC counters as metrics.

### Common Mistakes

- Calling `GC.Collect()` as a "fix."
- Ignoring event-subscription leaks.
- Fixing the symptom (increase memory limit) instead of the root.
- Not measuring — "memory is high" without a before/after baseline.

### Interview Follow-up Questions

1. What tools do you use to diagnose a managed memory leak? (dotnet-counters, dump+gcroot, gcdump, PerfView.)
2. Name three root-leak patterns. (Statics, events, async/CTS chains.)
3. When is `GC.Collect()` legitimate? (Rare; tests, NoGCRegion.)
4. What does `GC.AddMemoryPressure` do? (Counts native memory in GC budget.)

### Senior Level Talking Points

> "Memory debugging is root-cause analysis: is it a *leak* (root keeps growing) or a *bloat* (large working set but bounded)? A dump + `gcroot` answers it in minutes; guessing and restarting services is how 'mystery OOMs' live forever. I also set up the monitoring first — cache sizes and GC counters as metrics — so that the next leak is a dashboard chart, not a 3 AM pager."

### Memory Trick

**"Leaks are root problems, not GC problems — find who's still holding the rope."**

---

## 6.6 `ArrayPool<T>`, `MemoryPool<T>`, and Buffer Reuse

### Interview Answer (30–45 seconds)

> "`ArrayPool<T>.Shared` is a pooled array reuser — rent a `T[]` (usually ≥ minimum size), use it, return it. It avoids per-request allocations, especially for byte buffers ≥85 KB (LOH). `MemoryPool<T>` is the pooled-memory abstraction for higher-level code (pipes). The discipline: rent → use within the method → `Return` in `finally` (with `clearArray: true` if it holds sensitive data); never let the rented array escape. The classic 'clearArray' matters in healthcare: a pooled buffer may have held PHI, and returning it dirty leaks data to the next renter — so either clear on return or don't pool sensitive buffers."

### Detailed Explanation

**Why pooling:**

- Allocating a large `byte[]` per request hits the LOH (≥85 KB) → fragmentation + Gen-2 churn.
- Pooling recycles buffers → allocation rate drops → fewer GCs → stable latency.

**`ArrayPool<T>`:**

- `ArrayPool<T>.Shared` — a process-wide default pool.
- `Rent(minimumLength)` — returns a buffer ≥ min (may be larger!); use `buffer.AsSpan(0, usedLength)`.
- `Return(buffer, clearArray: false)` — returns to pool; `clearArray: true` zeroes it (for sensitive data).
- Pools have buckets per size (power-of-two-ish buckets), per-CPU-array caches.
- Rented arrays must be returned exactly once; renting from a static pool is not owned for long-term retention.

**`MemoryPool<T>`:**

- `MemoryPool<byte>.Shared` — `IMemoryOwner<T>`; `owner.Memory` — a pooled `Memory<T>`.
- Used with `System.IO.Pipelines` and async code (memory must outlive async frames).
- Disposing the `IMemoryOwner` returns the memory to the pool.

**`System.IO.Pipelines`:**

- High-throughput I/O reading/writing with pooled buffers; `Pipe`/`PipeReader`/`PipeWriter`. The backbone of Kestrel.
- `GetMemory`/`Advance`/`Complete` — the writer borrows from a pool, advances, flushes.

**When NOT to pool:**

- Small, short-lived buffers (pool overhead > allocation).
- When the buffer must outlive the scope (pool returned too early = corruption).
- Sensitive data where clearing is uncertain — clear or don't pool.

### Real World Example (Healthcare)

Reading HL7 batches from a socket:

```csharp
var buffer = ArrayPool<byte>.Shared.Rent(8192);
try
{
    int read = await stream.ReadAsync(buffer, ct);
    // process buffer.AsSpan(0, read)
}
finally
{
    ArrayPool<byte>.Shared.Return(buffer, clearArray: true);   // clear: PHI hygiene
}
```

### Production Code Example

```csharp
public sealed class PayloadReader
{
    public async ValueTask ProcessAsync(Stream stream, CancellationToken ct)
    {
        var buffer = ArrayPool<byte>.Shared.Rent(64 * 1024);   // 64KB, avoids LOH? (rented bucket)
        try
        {
            int read;
            while ((read = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), ct)) > 0)
            {
                ProcessSpan(buffer.AsSpan(0, read));           // work on the slice
            }
        }
        finally
        {
            ArrayPool<byte>.Shared.Return(buffer, clearArray: true);
        }
    }
}
```

**Key lines explained:**

- `Rent` before the loop — one rented buffer reused for the whole stream.
- `AsMemory`/`AsSpan` slicing — no copies.
- `Return(clearArray: true)` — PHI-safe and pool-clean.

### Advantages

- Allocation reduction (esp. LOH), stable latency, less GC.

### Disadvantages

- Ownership discipline (return exactly once); buffer-size surprises (≥ requested); pool corruption if double-returned/leaked; clear-cost for sensitive data.

### Best Practices

- Rent in the narrowest scope; return in `finally`.
- Always respect the actual size: use `Span`/`AsMemory(0, len)`.
- `clearArray: true` when content is sensitive (PHI).
- Don't store rented arrays beyond the method.

### Common Mistakes

- Retaining a rented array (pool reuse = data corruption).
- Not clearing sensitive buffers.
- Double-returning (crash/corruption).
- Pooling small buffers (overhead).

### Interview Follow-up Questions

1. What's the point of `ArrayPool`? (Avoid per-call allocations, esp. LOH.)
2. Why `clearArray` matters in healthcare? (PHI in shared buffers.)
3. What's `IMemoryOwner<T>`? (Owned pooled memory; dispose returns it.)
4. When would you *not* pool? (Tiny buffers, long-lived retention.)

### Senior Level Talking Points

> "Pooling is where allocation engineering meets *data hygiene*: a pooled byte buffer that carried a patient payload must be cleared on return or the next renter reads someone else's PHI. That's a compliance decision, not just a perf one — so in healthcare I default to `clearArray: true` or skip pooling for sensitive payloads. And I treat rent/return as a scoped contract: if the buffer must outlive the method, it's not a rental — it's an allocation."

### Memory Trick

**"Rent it, use it, return it clean — never keep the rental."**

---

## 6.7 GC Tuning and Config

### Interview Answer (30–45 seconds)

> "Most services need *zero* GC tuning — the defaults are excellent. The knobs that matter: `ServerGarbageCollection` (per-core heaps; the ASP.NET Core default), `ConcurrentGarbageCollection` (background collection), `GCHeapHardLimit`/`GCHeapHardLimitPercent` (bound heap in containers so it doesn't steal the pod's whole budget), and `GCSettings.LatencyMode` (Batch/Interactive/SustainedLowLatency — rarely used). Before tuning, I measure: Gen-2/LOH collection rates, allocation rate, pause times (`GC.GetGCMemoryInfo().PauseDurations`). The senior stance: tune *allocation* first, then consider `ServerGarbageCollection=true`, a heap limit, and only in extreme latency cases `NoGCRegion` for a bounded window."

### Detailed Explanation

**Runtime config keys (runtimeconfig.json / env):**

```json
{
  "configProperties": {
    "System.GC.Server": true,
    "System.GC.Concurrent": true,
    "System.GC.HeapHardLimit": 402653184,           // 384 MB heap cap
    "System.GC.HeapHardLimitPercent": 50,            // or 50% of container limit
    "System.GC.RetainVM": false
  }
}
```

- `Server` — per-core heaps + per-heap GC threads. Better throughput/scaling on multi-core; higher memory (each heap has full segments). Default true for ASP.NET Core.
- `Concurrent` (background GC) — young-gen continues during old-gen collection; default true.
- `HeapHardLimit`/`Percent` — caps committed heap; GC triggers more frequently to stay under; avoids OOM-kill-by-container by coordinating with cgroup limits. Crucial in Kubernetes where pod memory limit is enforced by the runtime (Linux cgroups + OOM killer).
- `RetainVM` — whether to hold virtual memory after collection (default false; segments released).
- `GCSettings.LatencyMode`:
  - `Batch` — max throughput, longest pauses.
  - `Interactive` — default workstation.
  - `SustainedLowLatency` — avoid blocking Gen-2 during the window (memory grows; GC runs background only); for latency-critical phases.
  - `NoGCRegion` (via `GC.TryStartNoGCRegion`) — promise not to allocate beyond a budget for a window; allocation over budget throws.
- `TieredCompilation`, `TieredPGO` — JIT-level, not GC, but often grouped in tuning discussions.

**When to tune:**

- **Containers:** set `HeapHardLimitPercent` ~ 50–70% of the pod limit so the GC stays inside the cgroup before the OOM killer fires. This is the single most common production tuning.
- **High-throughput services:** ensure Server GC is on (default).
- **Latency-critical (e.g., clinical decision support):** if Gen-2 pauses are the p99 driver, consider reducing allocation, using `SustainedLowLatency` during peak, or moving cold work off-thread. `NoGCRegion` is a niche last resort.

**Measurement before tuning:**

- `dotnet-counters monitor` for GC counters.
- `GC.GetGCMemoryInfo()` (`PauseDurations`, `TotalCommittedBytes`), `GC.GetTotalAllocatedBytes`.
- PerfView GC Events for pause histograms.

### Real World Example (Healthcare)

A FHIR server in Kubernetes with a 1 Gi pod limit. Default settings allowed the heap to grow past the cgroup limit → OOM-kill → restart loop during a load spike. Setting `GCHeapHardLimitPercent=60` made the GC collect *inside* the budget, eliminating OOM kills. Zero code changes.

### Production Code Example

```csharp
// runtimeconfig.json
{
  "runtimeOptions": {
    "tfm": "net8.0",
    "configProperties": {
      "System.GC.Server": true,
      "System.GC.Concurrent": true,
      "System.GC.HeapHardLimitPercent": 60
    }
  }
}

// Self-reporting GC metrics (feed to Prometheus)
public static GcMetrics Snapshot()
{
    var info = GC.GetGCMemoryInfo();
    return new GcMetrics(
        GC.CollectionCount(0), GC.CollectionCount(1), GC.CollectionCount(2),
        info.TotalCommittedBytes, info.HeapSizeBytes,
        info.PauseDurations.Select(d => d.TotalMilliseconds).ToArray());
}
```

**Key lines explained:**

- `HeapHardLimitPercent` ties GC behavior to the container's memory budget.
- Self-reported counters enable dashboards — you can't tune what you can't see.

### Best Practices

- Measure before tuning; default settings are good.
- Containers: set a heap hard limit percent.
- Verify Server GC on multi-core (ASP.NET Core default).
- Prefer allocation reduction over GC knob-fiddling.
- Test latency-mode changes with load.

### Common Mistakes

- `SustainedLowLatency` left on forever (memory grows; could OOM).
- No heap limit in containers (OOM-kill surprises).
- Enabling/disabling GC modes at runtime without understanding pause tradeoffs.
- "Tuning" without measurements.

### Interview Follow-up Questions

1. What does `ServerGarbageCollection` do? (Per-core heaps/threads; throughput.)
2. Why set `GCHeapHardLimit` in containers? (Coordinate GC with cgroup limit; avoid OOM-kill.)
3. What's `SustainedLowLatency`? (Defer blocking Gen-2; memory grows.)
4. When is `NoGCRegion` appropriate? (Bounded, latency-critical windows with a budget.)

### Senior Level Talking Points

> "The senior story: 95% of 'GC problems' are allocation problems. The remaining 5% get fixed with three levers — Server GC on multi-core, a heap hard-limit percent in containers, and occasionally a latency mode for a specific window. I never tune blind: GC counters go into the dashboard first. In healthcare, the worst outcome isn't a slow request — it's a pod OOM-killed mid-export, corrupting a batch file — so the heap limit is non-negotiable in our Kubernetes manifests."

### Memory Trick

**"Fix allocation first; then Server GC, then a heap cap — and always after measuring."**

---

## Chapter 6 Wrap-Up

### Top 10 Interview Questions From This Chapter

1. Explain the generational model and why it's efficient.
2. What is the LOH and why isn't it compacted?
3. What are roots, and how does reachability determine collection?
4. Server vs. workstation GC — when is each default, and why?
5. `IDisposable` vs `IAsyncDisposable` — when do you need async disposal?
6. Why are finalizers discouraged? What replaces them?
7. Name three common .NET memory-leak patterns.
8. How do you diagnose a memory leak in production?
9. What does `ArrayPool<T>` do and why does `clearArray` matter in healthcare?
10. Why set a GC heap hard limit in containers?

### Revision Notes (1 page)

- **GC model:** mark & sweep, generational (0/1/2), non-deterministic, compaction. Allocation = bump pointer on Gen 0. Server GC = per-core heaps (ASP.NET Core default). LOH ≥85 KB, not compacted by default → free lists → fragmentation risk.
- **Reachability:** roots = statics, stacks, registers, GC handles, finalizer queue. Only unreachable objects collect. Leaks are *root leaks*: statics, event subscriptions, async/CTS chains.
- **Pauses:** Gen-0 cheap/frequent; Gen-2 expensive/rare; background GC for old-gen; pause = tail-latency spike.
- **Dispose:** implement only when you own a resource; `using`/`await using`; idempotent; never throw; `SafeHandle` instead of finalizers; `SuppressFinalize`; DI owns registered lifecycles.
- **Finalizers:** run on finalizer thread, ≥2 cycles, undefined order → design them out with `SafeHandle`; never touch managed state; never throw.
- **Diagnosis:** `dotnet-counters` (live), `dotnet-dump` + `gcroot`/`heapstat` (roots), `dotnet-gcdump`, PerfView (allocation). Fix roots, not `GC.Collect()`.
- **Pooling:** `ArrayPool<T>.Shared` rent/return; `MemoryPool`/`IMemoryOwner`; `System.IO.Pipelines`; clear on return for PHI.
- **Tuning:** measure first; Server GC, `GCHeapHardLimit(Percent)` for containers, `SustainedLowLatency`/`NoGCRegion` only in bounded latency-critical windows. Almost never call `GC.Collect()`.

### Things Interviewers Expect From 5+ Years Experience

- Comfort with *why* the generational model works (the young-die-young statistic), not just the terms.
- Debugging skills: which tool, which counter, which root pattern.
- Design discipline: bounded caches, event hygiene, pooled buffers, PHI-safe clearing.
- Container awareness: heap limits, cgroup OOM.
- Calm, measurement-first attitude toward "GC tuning."

### Cheat Sheet

```
GC MODEL:  mark & sweep | generations 0/1/2 | LOH(>=85KB, no compact)
ALLOCATION: Gen-0 bump pointer | Server GC = per-core heaps (ASP.NET Core default)
ROOTS:  statics | stacks | registers | GC handles | finalizer queue
LEAK PATTERNS:  static caches | event subscriptions | async/CTS retention

DISPOSE: implement only if you OWN a resource
  using / await using | idempotent | never throw | SuppressFinalize
  SafeHandle replaces finalizers | DI owns registered lifecycles

TOOLS:
  dotnet-counters monitor       → live GC metrics
  dotnet-dump collect/analyze   → gcroot, clrheapstat
  dotnet-gcdump                 → heap graph snapshot
  PerfView                      → allocation profiles (ETW)

POOLING: ArrayPool<T>.Shared rent/return-in-finally; clearArray:true for PHI
  MemoryPool / IMemoryOwner | System.IO.Pipelines

TUNING: measure → Server GC → HeapHardLimitPercent (containers)
  SustainedLowLatency only for bounded windows | never GC.Collect() in prod
```

### Flash Cards

**Q1:** Three generations — why? **A:** Most objects die young; cheap young collections, rare expensive old ones.

**Q2:** LOH not compacted? **A:** ≥85 KB arrays too expensive to move; free lists instead.

**Q3:** What's a root? **A:** Statics, thread stacks, registers, GC handles, finalizer queue.

**Q4:** Server GC default where? **A:** ASP.NET Core on multi-core; per-core heaps/threads.

**Q5:** Why can't you await in Dispose? **A:** It's void — use IAsyncDisposable (`await using`).

**Q6:** Finalizer replacement? **A:** SafeHandle — wraps OS handle, owns its own finalizer.

**Q7:** #1 .NET leak pattern? **A:** Event subscription from long-lived publisher to short-lived subscriber.

**Q8:** `gcroot` does what? **A:** Shows what roots an object in a dump.

**Q9:** Why clearArray on return? **A:** Pooled buffers may hold PHI; next renter must not read it.

**Q10:** Containers + GC? **A:** Set GCHeapHardLimitPercent so GC collects before cgroup OOM-kill.

### Interview Confidence Score

**Medium-Hard.** Memory & GC separates senior from junior instantly. Prepare the generational model, root-leak patterns, the tooling ritual, and container GC limits. Practicing explaining the GC "in one breath" pays off.

---

*Continue → Chapter 7: Multithreading*
