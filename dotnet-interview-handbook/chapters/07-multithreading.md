# Chapter 7: Multithreading

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** Threads vs. tasks, the ThreadPool, Task composition (`WhenAll`, `WhenAny`), synchronization primitives (`lock`, `Monitor`, `Mutex`, `SemaphoreSlim`, `ReaderWriterLockSlim`, `SpinLock`), thread safety and races, `volatile`/`Interlocked`, deadlocks and livelocks, async vs. parallel, and producer/consumer with `Channel<T>`.

---

## 7.1 Thread vs. Task vs. ThreadPool

### Interview Answer (30–45 seconds)

> "A thread is an OS-level execution context with its own stack; creating one is expensive (~1 MB virtual stack, kernel object, context-switch overhead), so we never create threads per operation. The `ThreadPool` recycles a set of worker threads. A `Task` is a *unit of work with a lifecycle* — it's not a thread; it runs on a threadpool thread (for `Task.Run`/blocking work) or is driven by callbacks/completions (for async I/O, no thread is held). So `Task.Run` = schedule CPU work on the pool; `async/await` on I/O = no thread at all. The senior rule: threads for long-running dedicated workers, `Task.Run` for CPU-bound parallel work, `async/await` for I/O, and the pool's `SetMinThreads` for known concurrency shapes."

### Detailed Explanation

**Thread (OS level):**

- `new Thread(...)` — kernel thread with its own stack (~1 MB virtual), TLS (thread-local storage), scheduling priority.
- Context switch: save/restore registers + caches → expensive (~microseconds, cache-cold).
- Thousands of threads = scheduler thrash, memory overhead, GC sees each stack.
- Use for: dedicated long-lived workers (rare in modern .NET), UI thread (must be its own), legacy interop.

**ThreadPool:**

- A shared pool of reusable worker threads; size scales (min → max based on throughput heuristic).
- Work items: `ThreadPool.QueueUserWorkItem`, `Task.Run`, timers, `RegisterWaitForSingleObject`.
- Starvation: if all pool threads block (sync-over-async, DB lock waits), the pool injects threads slowly (1 per ~500ms default hill-climbing) → throughput collapse. `ThreadPool.SetMinThreads` raises the floor to avoid this.
- Per-core worker queues + work-stealing to balance load.

**Task:**

- A handle to *work with a state*: `Task`/`Task<T>` (completion, cancellation, continuations, exceptions).
- Two execution models:
  - `Task.Run(action)` → schedules the delegate on the threadpool. **Blocking** work (CPU or blocking I/O) occupies a pool thread for its duration.
  - Async I/O methods (`await httpClient.GetAsync`) → the *thread returns*; the completion comes from an I/O completion port callback. **No thread held during the wait.**
- `Task` is a *promise*, not a thread. This is the key interview distinction.

**When each:**

| Need | Choose |
|---|---|
| CPU-bound parallel computation | `Task.Run` / PLINQ / `Parallel.For` |
| I/O-bound (network, DB, file) | `async/await` (no thread held) |
| Long-running dedicated worker | `Task.Factory.StartNew(..., TaskCreationOptions.LongRunning)` or a `BackgroundService` thread |
| High-volume concurrent I/O | async + pool (thread count stays small) |
| Never | `new Thread` per request |

**`TaskCreationOptions.LongRunning`:** hints the scheduler to give the work a dedicated thread instead of the pool — for long-lived loops (avoid pool starvation of short tasks).

### Real World Example (Healthcare)

- 10,000 concurrent clinician viewers streaming vitals over SignalR: all async — Kestrel + async handlers serve them with a handful of threads. If this were `new Thread` per connection, the box dies.
- A batch EMR normalization job on 4 cores: `Parallel.ForEach` / `Task.Run` over CPU-bound normalization — pool threads exploit all cores.
- A background `AuditFlushWorker`: `BackgroundService` (a long-running task), not a per-request thread.

### Production Code Example

```csharp
// CPU-bound: parallelize on the pool
public static decimal[] NormalizeAll(IReadOnlyList<decimal> values)
{
    var result = new decimal[values.Count];
    Parallel.For(0, values.Count,
        new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount },
        i => result[i] = Normalize(values[i]));          // no shared state — safe
    return result;
}

// I/O-bound: async, thread returns to pool during waits
public async Task<IReadOnlyList<PatientDto>> FetchAllAsync(IEnumerable<string> ids, CancellationToken ct)
{
    var tasks = ids.Select(id => _gateway.GetPatientAsync(id, ct)).ToArray();  // start all
    return await Task.WhenAll(tasks);                   // no blocked threads
}
```

**Key lines explained:**

- `Parallel.For` with `MaxDegreeOfParallelism` — bounded CPU concurrency, index-based writes are disjoint.
- `Task.WhenAll` over async HTTP — all requests in flight, zero threads blocked.

### Internal Working

- ThreadPool: global queue + per-core local queues; threads pull work and steal.
- `Task.Run` → `ThreadPool.UnsafeQueueUserWorkItem` → worker thread executes → task completes → continuations fire.
- Async I/O: `Socket.BeginReceive` registers with the I/O completion port; the OS notifies via a port thread when data arrives → continuation.

### Comparison Table

| Aspect | Thread | ThreadPool thread | Task (async) |
|---|---|---|---|
| Allocation | heavy (kernel+stack) | pooled | cheap (state machine) |
| Thread held during wait | yes | yes (blocking) | **no** |
| Use for | dedicated worker | CPU/blocking batch | I/O concurrency |
| Lifetime | explicit | managed | managed |

### Best Practices

- Never `new Thread` per operation; use pool/tasks.
- `async` for I/O; `Task.Run`/`Parallel` for CPU.
- Watch `SetMinThreads` when you see pool starvation under load.
- `LongRunning` for genuinely long workers.

### Common Mistakes

- `Task.Run` around async methods (double scheduling: `Task.Run(async () => await ...)` — the outer runs on a pool thread only to block on nothing; it *does* return the thread at the await, but the `Task.Run` itself is pointless and allocates an extra task).
- Blocking sync-over-async (`.Result`) → thread held + starvation.
- Hundreds of `new Thread` → scheduler thrash.
- Assuming a `Task` == a thread (it isn't).

### Interview Follow-up Questions

1. `Task.Run` vs `new Thread`? (Pool scheduling vs dedicated OS thread.)
2. What happens when pool threads all block? (Starvation; slow injection; SetMinThreads mitigates.)
3. Is an `async` method holding a thread during `await`? (No — returns to pool.)
4. `LongRunning` option — when? (Dedicated long-lived workers.)

### Senior Level Talking Points

> "The senior mental model: a `Task` is a *promise*, and 'how many threads does this need?' depends on the kind of work. I/O-bound workloads want *as few threads as possible* — async lets 10k connections ride on a few dozen threads. CPU-bound wants *one thread per core* — beyond that you're paying for context switches. Blocking work occupies threads — so I hunt sync-over-async and blocked `Task.Run` delegates, because each one steals a pool thread and quietly multiplies latency under load."

### Memory Trick

**"Thread = a worker at a desk; Task = a promise of results; async = the worker leaves while the printer runs."**

---

## 7.2 Task Composition: `WhenAll`, `WhenAny`, and Exceptions

### Interview Answer (30–45 seconds)

> "`Task.WhenAll(tasks)` awaits all and completes when every task completes — exceptions are aggregated, but `await` unwraps and throws the *first* one (in .NET 5+, the AggregateException is unwrapped; you can access all via `task.WhenAll(...).Exception`). `Task.WhenAny` completes when the *first* task finishes — the basis for timeouts, racing, and failover. For handling all failures, I iterate the task list and inspect each `.Status`/`Exception`. My patterns: `WhenAll` for fan-out, `WhenAny` + `WaitAsync` for timeouts, and careful handling so one failed leg doesn't mask others."

### Detailed Explanation

**`WhenAll`:**

- `Task.WhenAll(IEnumerable<Task>)` → a `Task` that completes when all complete.
- `Task.WhenAll(Task<T>[])` → `Task<T[]>`.
- If any faults: the returned task faults; `await` throws the first exception (unwrapped). To see all: `allTask.Exception` (AggregateException) or inspect each child.
- Non-blocking — no threads held.

**`WhenAny`:**

- `Task.WhenAny(IEnumerable<Task>)` → completes with the first finished task (result = that task).
- Uses: timeout (`WaitAsync` is cleaner), race (fastest source wins), circuit breaker (one healthy upstream).

**`WaitAsync` (net6+):**

- `task.WaitAsync(TimeSpan)` / `WaitAsync(cancellationToken)` — completes when the task completes OR times out/cancels. The canonical timeout pattern.

**Cancellation composition:**

- `Task.WhenAll` with cancellation → all legs get the same token; one `OperationCanceledException` from a canceled leg cancels the batch.

**Exception handling patterns:**

```csharp
// ALL failures, not just the first:
var tasks = ids.Select(id => Fetch(id, ct)).ToArray();
await Task.WhenAll(tasks);          // throws first fault
var all = tasks.Select(t => t.Exception).Where(e => e != null);   // inspect all
```

**AggregateException nuance:** pre-.NET 5, `await WhenAll` threw `AggregateException`; since .NET 5 (and .NET Core 2.x partially), `await` unwraps to the first inner exception. `.Result`/`.Wait()` still throw `AggregateException` (blocking = aggregated).

### Real World Example (Healthcare)

A clinical dashboard needs patient, vitals, and labs concurrently:

```csharp
var patientTask = _patients.GetAsync(id, ct);
var vitalsTask = _vitals.GetLatestAsync(id, ct);
var labsTask = _labs.GetRecentAsync(id, ct);

await Task.WhenAll(patientTask, vitalsTask, labsTask);   // 3 in flight, no threads

return new DashboardDto(await patientTask, await vitalsTask, await labsTask);
```

If vitals are optional, don't fail the whole page:

```csharp
var vitalsTask = _vitals.GetLatestSafeAsync(id, ct);   // never throws
```

### Production Code Example

```csharp
public async Task<Patient> GetPatientWithTimeoutAsync(string id, CancellationToken ct)
{
    using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
    timeoutCts.CancelAfter(TimeSpan.FromSeconds(5));

    try
    {
        // WaitAsync = WhenAny-style timeout without blocking
        return await _gateway.GetPatientAsync(id, timeoutCts.Token).WaitAsync(timeoutCts.Token);
    }
    catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !ct.IsCancellationRequested)
    {
        throw new TimeoutException($"FHIR gateway timed out for {id}");
    }
}

public async Task ReportOnAllFailuresAsync(IEnumerable<string> ids, CancellationToken ct)
{
    var tasks = ids.Select(id => TryFetchAsync(id, ct)).ToArray();
    await Task.WhenAll(tasks);

    // Surface every failure, not just the first
    var failures = tasks
        .Where(t => t.IsFaulted)
        .SelectMany(t => t.Exception!.InnerExceptions)
        .ToList();

    if (failures.Count > 0)
        _logger.LogError("Batch had {Count} failures: {First}", failures.Count, failures[0]);
}
```

**Key lines explained:**

- `WaitAsync(token)` — the modern timeout (non-blocking; uses `WhenAny` internally).
- The `when` filter maps a timeout to a `TimeoutException` only when *we* initiated it.
- Inspecting `.IsFaulted` + `.InnerExceptions` surfaces all failures.

### Internal Working

- `WhenAll` uses a counter + continuations; completes when the count reaches zero (or on first fault/cancel).
- `WhenAny` registers a continuation on each child; the first to fire completes the parent.
- `WaitAsync` = `WhenAny(task, delay/canceled task)` internally.

### Advantages / Disadvantages

| | WhenAll | WhenAny |
|---|---|---|
| Completes on | all done | first done |
| Exceptions | first unwrapped (all via .Exception) | only the first's |
| Use for | fan-out, join | timeouts, races, fallbacks |
| Blocking? | no | no |

### Best Practices

- Fan-out then `WhenAll`; never await inside a loop.
- Use `WaitAsync` for timeouts.
- Handle partial-failure semantics deliberately (all-or-nothing vs. best-effort).
- Pass the same cancellation token to all legs.

### Common Mistakes

- `foreach` + `await` inside the loop (serial instead of parallel).
- `.Result`/`.Wait()` → deadlock/blocking.
- `WhenAny` then awaiting the *winner* without checking its status.
- Assuming `await WhenAll` gives you all exceptions (it gives the first).

### Interview Follow-up Questions

1. Does `await WhenAll` throw `AggregateException`? (No — unwraps the first since .NET 5.)
2. How do you get all exceptions? (Inspect each task's `.Exception`.)
3. `WhenAny` use cases? (Timeout, race, failover.)
4. `WaitAsync` vs manual `WhenAny`? (Convenience + cancellation.)

### Senior Level Talking Points

> "Task composition is about *partial-failure semantics*. In a clinical dashboard, a slow vitals service shouldn't kill the patient's chart page — so I use `WhenAll` for the critical path and degrade gracefully for optional legs. And I never serialize with `await`-in-loop: fan-out then `WhenAll` is the difference between 3 round trips and 1. The `WaitAsync` pattern is my default for any downstream call that must not hang the request past its SLA."

### Memory Trick

**"WhenAll waits for the whole team; WhenAny takes the first one home."**

---

## 7.3 `lock`, `Monitor`, `Mutex`, `SemaphoreSlim`, and Friends

### Interview Answer (30–45 seconds)

> "`lock(obj)` is `Monitor.Enter`/`Exit` in a `try/finally` — a reentrant mutual-exclusion primitive for protecting critical sections *within a process*. `Mutex` is a cross-process mutex (kernel object) — rarely needed. `SemaphoreSlim` limits concurrent access to N (a bounded counter with wait); `ReaderWriterLockSlim` allows many readers or one writer; `SpinLock` spins (busy-waits) instead of blocking — only for very short critical sections. My defaults: `lock` for quick critical sections, `SemaphoreSlim` for concurrency caps and async scenarios (`WaitAsync`), `ReaderWriterLockSlim` when reads vastly outnumber writes, and nothing when `Interlocked`/concurrent collections cover it."

### Detailed Explanation

**`lock` / `Monitor`:**

- `lock (obj) { ... }` → `Monitor.Enter(obj); try { } finally { Monitor.Exit(obj); }`.
- **Reentrant:** same thread can re-lock (recursion OK).
- **Blocking:** a waiting thread blocks (waits on a kernel-ish sync event).
- The lock object should be a *private, dedicated, reference-type* object — never a string (interned, shared) or `this` (public, other code can lock it).
- `Monitor.TryEnter` — non-blocking attempt with timeout.

**`Mutex`:**

- Cross-process: two processes can share a named mutex (`new Mutex(false, "Global\\Name")`). Kernel-backed.
- `WaitOne`/`ReleaseMutex`; abandoned-mutex exception if an owner dies.
- Overkill for in-process; `lock` is cheaper.

**`SemaphoreSlim`:**

- Counter-based gate: `Wait` decrements; `Release` increments; waits when zero.
- **Async:** `WaitAsync(CancellationToken)` — the only one of these that's await-friendly (no thread blocked). `Semaphore` (non-slim) is the older kernel semaphore.
- Use: bounded concurrency (e.g., limit 8 simultaneous FHIR fetches), rate shaping, resource pools.

**`ReaderWriterLockSlim`:**

- Multiple readers OR one writer; upgradeable read.
- Better than `lock` when reads dominate writes; worse if write-heavy (writer starvation tuning).
- Async-safe? No `WaitAsync` — it blocks. Prefer `SemaphoreSlim` for async-heavy code.

**`SpinLock`:**

- Busy-waits (spins) for a short window before blocking. Good for sub-microsecond critical sections where context-switch cost > spin cost.
- **Warning:** spinning holds a core; never spin while holding something else; use for microseconds only.

**`Interlocked`** (Chapter 7.5): atomic read-modify-write (`Increment`, `Add`, `Exchange`, `CompareExchange`) — the lock-free alternative for counters/flags.

**Choosing the primitive (decision tree):**

| Scenario | Primitive |
|---|---|
| Quick critical section | `lock` |
| Cross-process | `Mutex` |
| Cap of N concurrent (async) | `SemaphoreSlim.WaitAsync` |
| Many readers / one writer | `ReaderWriterLockSlim` |
| Microseconds critical section | `SpinLock` |
| Counter/flag | `Interlocked` |

### Real World Example (Healthcare)

```csharp
// Bounded concurrency for a downstream FHIR endpoint
private readonly SemaphoreSlim _gate = new(8, 8);

public async Task<Patient> GetPatientThrottledAsync(string id, CancellationToken ct)
{
    await _gate.WaitAsync(ct);                 // async wait — no thread blocked
    try
    {
        return await _fhir.GetPatientAsync(id, ct);
    }
    finally
    {
        _gate.Release();
    }
}
```

### Production Code Example

```csharp
public sealed class PatientCache
{
    private readonly object _gate = new();                   // dedicated lock object
    private readonly Dictionary<string, CachedPatient> _map = new();

    public CachedPatient? Get(string id)
    {
        lock (_gate)                                         // short critical section
        {
            return _map.TryGetValue(id, out var p) ? p : null;
        }
    }

    public void Set(string id, CachedPatient patient)
    {
        lock (_gate) { _map[id] = patient; }
    }
}

// Reader-heavy: ReaderWriterLockSlim
public sealed class ConfigSnapshot
{
    private readonly ReaderWriterLockSlim _rw = new();
    private Dictionary<string, string> _cfg = new();

    public string? Get(string key)
    {
        _rw.EnterReadLock();
        try { return _cfg.GetValueOrDefault(key); }
        finally { _rw.ExitReadLock(); }
    }

    public void Replace(Dictionary<string, string> next)
    {
        _rw.EnterWriteLock();
        try { _cfg = next; }                   // swap reference — readers never tear
        finally { _rw.ExitWriteLock(); }
    }
}
```

**Key lines explained:**

- `lock(_gate)` on a private field — the correct lock target.
- `SemaphoreSlim.WaitAsync` — async concurrency gate.
- `ReaderWriterLockSlim` read/write separation for a config snapshot.

### Internal Working

- `Monitor` — per-object sync block (in the object header); fast path = a CAS on the header; slow path = kernel wait.
- `Mutex` — kernel object; cross-process handle.
- `SemaphoreSlim` — an async-capable wait chain built over spin + kernel signal (`ManualResetEventSlim`-ish).
- `SpinLock` — `Interlocked.CompareExchange` loop on a `bool`; falls back to `Thread.Sleep(0)`/`SpinWait`.

### Advantages / Disadvantages

| | Pros | Cons |
|---|---|---|
| lock/Monitor | simple, reentrant, fast path cheap | blocks; contention hurts |
| Mutex | cross-process | heavy, abandoned-abort semantics |
| SemaphoreSlim | async wait, bounded concurrency | can't be reentrant per-thread |
| RWLS | read scaling | blocks (no async); writer starvation risk |
| SpinLock | fastest for micro-sections | wastes cores if overused |

### Best Practices

- `lock` on a private reference object; never lock strings, `this`, or mutable shared instances.
- Keep critical sections tiny; don't do I/O inside a lock.
- Use `SemaphoreSlim.WaitAsync` for async concurrency.
- Prefer `Interlocked`/concurrent collections over locks where possible.

### Common Mistakes

- Locking on `this` or a `string`.
- I/O or DB work inside a lock (kills concurrency).
- `lock` inside `async` across awaits (lock is a monitor; can't be held across `await`).
- Using `Mutex` where `lock` suffices (or the reverse — a *process-wide* assumption).

### Interview Follow-up Questions

1. What's the difference between `Monitor` and `Mutex`? (In-process reentrant vs cross-process kernel.)
2. Why can't you `await` while holding a `lock`? (Monitor is thread-bound; `SemaphoreSlim` has `WaitAsync`.)
3. `SemaphoreSlim(initial, max)` — what does it do? (Count gate; concurrency cap.)
4. When use `ReaderWriterLockSlim`? (Read-dominated, and reads are long-ish; blocking acceptable.)
5. `SpinLock` when? (Microseconds, no other sync held.)

### Senior Level Talking Points

> "Locks are a *contention budget*: every critical section is a potential serialization point, so I keep them tiny and reason about *who waits on whom*. The senior pattern is to avoid locks at the design level — `Interlocked`, `ConcurrentDictionary`, and immutable snapshots remove whole classes of races. Where locks remain (a cache, a bounded resource), `SemaphoreSlim.WaitAsync` keeps it async-friendly. And I have a hard rule: no I/O under a lock, because that's how a 'simple' dictionary turns into a pileup of blocked threads."

### Diagram

```
lock/Monitor:  ThreadA ──[X]──► critical section ◄── [X] waits
Mutex:         same but kernel object, cross-process
SemaphoreSlim: N permits | Threads wait on count, released one-by-one
RWLS:          RRRRR RR... (many readers) ── W (one writer at a time)
```

### Memory Trick

**"lock guards one door, semaphore counts tickets, mutex works across buildings."**

---

## 7.4 Deadlocks, Livelocks, and Race Conditions

### Interview Answer (30–45 seconds)

> "A deadlock is two or more threads each holding a resource the other needs and waiting forever — the classic ABBA pattern: thread 1 locks A then B; thread 2 locks B then A. Prevention: acquire locks in a consistent global order, avoid nested locks, use timeouts (`Monitor.TryEnter`, `WaitAsync`) so a stuck path becomes an error instead of a hang. Livelock is threads *repeatedly reacting* to each other without making progress (they're not blocked, just spinning). Race conditions are *unpredictable interleavings*: two threads read-modify-write the same state without atomicity — they 'work' in tests and break under load. Detection: `dotnet-dump` thread stacks show deadlocked threads; `lock` analysis + `Interlocked` audit finds races."

### Detailed Explanation

**Deadlock (the ABBA problem):**

```
Thread1: lock(A); lock(B) ...
Thread2: lock(B); lock(A) ...
        → each holds one and waits for the other → deadlock
```

- Necessary conditions: mutual exclusion + hold-and-wait + no preemption + circular wait.
- Breaking any one kills the deadlock: consistent lock ordering breaks circular wait; timeouts convert hang → error; single-lock designs remove the pair.
- Detect: threads in `Wait` state; `dotnet-dump` shows both stacks waiting on each other's locks; `Monitor` + SOS `clrstack`.

**Livelock:**

- Threads *change state* but never make progress — e.g., two threads each release a resource because the other wants it, then both re-acquire... forever.
- Typical in retry loops without backoff, lock-free algorithms with bad CAS loops.
- Fix: backoff/randomization, priorities, progress guarantees.

**Race condition:**

- Interleaving-dependent behavior. Classic: `if (count > 0) count--;` — two threads pass the `if` before either decrements.
- Data races on shared mutable state without synchronization → torn reads, lost updates.
- Fixes: `Interlocked` (atomic), `lock`, immutable values, or `ConcurrentDictionary`.
- The danger: race bugs are *probabilistic* — they appear at scale, under load, or on different CPUs.

**Memory model angle:**

- `lock`/`Interlocked`/`volatile` establish *memory barriers* — they make reads/writes visible across threads. Without them, the JIT/CPU can reorder or cache values (each thread sees its own view) → subtle races even on 'simple' bools.

**Async-specific races:**

- Two concurrent requests mutating the same singleton state.
- `DbContext` shared across concurrent operations (EF contexts are NOT thread-safe — one request per context).
- `Lazy<T>` default is thread-safe (`ExecutionAndPublication`).

### Real World Example (Healthcare)

A triage counter shared across SignalR hub methods:

```csharp
// RACE: two hub calls interleave
// _queueCount++;  ← two threads increment, one increment lost

// FIX: atomic
Interlocked.Increment(ref _queueCount);
```

### Production Code Example

```csharp
public sealed class PatientQueue
{
    private readonly object _a = new();
    private readonly object _b = new();

    // DEADLOCK PRONE (ABBA):
    public void MoveAtoB(Guid id)
    {
        lock (_a) { lock (_b) { /* move */ } }
    }

    // Use consistent ordering everywhere (always _a then _b) — breaking circular wait:
    public void MoveBtoA(Guid id)
    {
        lock (_a) { lock (_b) { /* move */ } }   // same order as MoveAtoB
    }

    // Or use a timeout to convert a hang into a retryable error:
    public bool TryEnterWithTimeout(Guid id)
    {
        if (!Monitor.TryEnter(_a, TimeSpan.FromMilliseconds(100))) return false;
        try
        {
            if (!Monitor.TryEnter(_b, TimeSpan.FromMilliseconds(100))) return false;
            try { /* critical */ }
            finally { Monitor.Exit(_b); }
            return true;
        }
        finally { Monitor.Exit(_a); }
    }
}
```

**Key lines explained:**

- Consistent lock ordering (`_a` then `_b` everywhere) — the #1 deadlock prevention.
- `Monitor.TryEnter(timeout)` — a stuck path becomes a `false`/exception instead of a permanent hang.
- Reentrancy: same thread can re-enter `_a`; nested locks still need ordering discipline.

### Internal Working

- Deadlock detection: the runtime doesn't auto-detect; it's diagnosed via dumps/stacks.
- `lock` acquires via a fast CAS then a kernel wait; timeout versions (`TryEnter`) bail instead of waiting forever.
- Memory barriers: locks/monitors and `Interlocked` operations emit fences so other threads observe writes.

### Best Practices

- Single lock where possible; consistent global ordering for multiple.
- Timeouts on every wait you can afford (`TryEnter`, `WaitAsync(timeout)`).
- Prefer lock-free (`Interlocked`, concurrent collections, immutable snapshots).
- No I/O inside locks; no locks inside locks without ordering.

### Common Mistakes

- Different lock acquisition orders in different methods (ABBA).
- Waiting on locks while holding others (nested + blocking).
- Async lock misuse (await inside lock).
- Races "hidden" by `volatile` alone for compound ops.

### Interview Follow-up Questions

1. What are the four conditions for deadlock? (Mutual exclusion, hold-and-wait, no preemption, circular wait.)
2. How do you prevent deadlock? (Ordering, timeouts, single-lock design.)
3. Deadlock vs. livelock? (Blocked-forever vs. spinning-forever.)
4. Why is `volatile` not enough for `count++`? (It's not atomic; needs `Interlocked`.)
5. How do you diagnose a deadlock in production? (Dump + SOS stacks.)

### Senior Level Talking Points

> "Deadlocks are a *design* failure, not a runtime accident: they come from uncoordinated lock acquisition. My review checklist is mechanical — every `lock`, `TryEnter`, and `WaitAsync` has a timeout or a documented ordering invariant; nested locks are banned unless ordered. And I prefer eliminating the problem: `Interlocked` for counters, `ConcurrentDictionary` for maps, immutable snapshots for config. In a healthcare system, a deadlocked request that hangs a clinician's chart is a patient-safety incident, not just an availability blip."

### Memory Trick

**"ABBA deadlock = two threads politely holding each other's keys forever."**

---

## 7.5 `volatile` and `Interlocked`

### Interview Answer (30–45 seconds)

> "`volatile` marks a field as read/written with a *memory barrier*, so the JIT won't cache it in a register or reorder it across threads — it guarantees fresh reads and observable writes for *that single field*. But it does NOT make compound operations atomic: `counter++` still races. `Interlocked` provides atomic read-modify-write (`Increment`, `Add`, `Exchange`, `CompareExchange`) and is the lock-free primitive for counters, flags, and simple state machines. The senior rule: `volatile` for a single flag/pointer that's checked/updated atomically by the language (`bool`, references), `Interlocked` for any compound math or compare-swap."

### Detailed Explanation

**`volatile`:**

- `private volatile bool _isRunning;` — reads/writes are not cached (register or CPU cache) and are ordered relative to other volatile ops (acquire/release semantics).
- Allowed on: reference types, pointers, primitives, and enums where the underlying type is a byte/int/etc. (not `double`, not `long` on 32-bit — those aren't atomic there; actually `double`/`long` volatile is disallowed).
- `volatile` is a *field-level* marker; a volatile field can't be passed `ref`/`out` (atomicity of the access is implied).

**`Interlocked`:**

- `Interlocked.Increment(ref long)`, `Add`, `Exchange`, `CompareExchange(ref x, new, comparand)`, `Decrement`, `And/Or` (net5+).
- Implemented as CPU atomic instructions (`lock xadd` / `cmpxchg`) — atomic on the hardware level, no user lock.
- `CompareExchange` is the CAS primitive for building lock-free structures and state machines.

**When each:**

| Need | Tool |
|---|---|
| Single flag read/check (no compound) | `volatile` |
| Counter increment | `Interlocked.Increment` |
| Swap a reference/pointer | `Interlocked.Exchange` / `volatile` ref |
| CAS-based state transition | `Interlocked.CompareExchange` |
| Any read-modify-write | `Interlocked` (never `volatile`) |

**The classic exam question:** `volatile int count; count++;` — still a race (three steps: read, add, write). Answer: use `Interlocked.Increment`.

**Memory ordering:** both insert *fences*; `Interlocked` has full fence semantics; `volatile` has acquire/release — enough for typical flag patterns.

### Real World Example (Healthcare)

```csharp
public sealed class JobRunner
{
    private int _activeJobs;                     // counter

    public void Start(Job job)
    {
        // atomic: no lost increments even with many concurrent starts
        Interlocked.Increment(ref _activeJobs);
        try { job.Run(); }
        finally { Interlocked.Decrement(ref _activeJobs); }
    }

    public bool IsIdle => Volatile.Read(ref _activeJobs) == 0;
}
```

### Production Code Example

```csharp
public sealed class CircuitState
{
    // lock-free state machine: Closed → Open → HalfOpen
    private int _state;   // 0 = Closed, 1 = Open, 2 = HalfOpen

    public bool TryOpen()
        // CAS: only transitions Closed → Open; returns whether we won
        => Interlocked.CompareExchange(ref _state, 1, 0) == 0;

    public bool IsOpen => Volatile.Read(ref _state) == 1;
}

public sealed class OnceFlag
{
    private int _set;
    public bool TrySet() => Interlocked.Exchange(ref _set, 1) == 0;   // set-once
}
```

**Key lines explained:**

- `CompareExchange` — atomic "if still in expected state, swap" — the circuit breaker gate.
- `Volatile.Read` — fresh read of the counter without a lock.
- `Exchange` — set-once idempotent flag.

### Internal Working

- On x86/ARM, `Interlocked.Increment` → `lock inc [addr]`; `CompareExchange` → `lock cmpxchg [addr], reg`.
- Memory fences prevent the CPU/JIT from reordering the surrounding accesses.

### Best Practices

- `Interlocked` for any compound op; `volatile` only for single field flags with atomic language-level access.
- Use `Volatile.Read`/`Volatile.Write` (method form) for non-`volatile` fields when you need one-shot semantics.
- Prefer concurrent collections/immutable over hand-rolled lock-free unless you can prove correctness.

### Common Mistakes

- `volatile` + `++` believing it's atomic.
- `volatile` on `double`/`long` (compile error on 32-bit; semantics wrong).
- Hand-rolled spin loops with `volatile` flags instead of `SpinWait`.

### Interview Follow-up Questions

1. Why isn't `volatile int x; x++` atomic? (Three sub-operations; only the field access is volatile.)
2. What does `Interlocked.CompareExchange` do? (Atomic conditional swap.)
3. `volatile` allowed on which types? (Refs, pointers, primitives, enums; not double/long on 32-bit.)
4. When to use `Volatile.Read`? (One-shot fresh reads without a volatile field.)

### Senior Level Talking Points

> "The senior line: `volatile` answers 'will I see the latest value?' while `Interlocked` answers 'is this update atomic?' Most people conflate them. In production I use `Interlocked` for counters and CAS state machines, and `volatile`/`Volatile.Read` only for single flags — and I prefer to make the whole state machine `ConcurrentDictionary`-backed or immutable when it grows beyond two states, because hand-rolled lock-free correctness is the most expensive correctness in the codebase."

### Memory Trick

**"volatile = fresh eyes on one value; Interlocked = the machine guarantees the whole move."**

---

## 7.6 Async vs. Parallel vs. Concurrency

### Interview Answer (30–45 seconds)

> "These are three different axes. *Concurrency* is doing multiple things at once (progress on multiple tasks). *Parallelism* is doing multiple things *simultaneously on multiple cores* (CPU-bound: `Parallel.For`, PLINQ, `Task.Run`). *Async* is *non-blocking I/O* — no thread is held during the wait; it's concurrency without threads. So: I/O-bound work → async (thread count low); CPU-bound work → parallelism on ~core-count threads; concurrency caps → `SemaphoreSlim`/`Channel`; UI → async to keep the UI thread free. The classic mix-ups: 'making it async makes it faster' (false — it reduces thread usage), and 'using Task.Run for I/O' (wrong tool)."

### Detailed Explanation

- **Concurrency:** interleaved progress — many tasks in flight, threads may switch. Async achieves concurrency with few threads.
- **Parallelism:** true simultaneous execution on multiple cores. Requires hardware. Bounded by `ProcessorCount`.
- **Async:** a style for I/O — `await` releases the thread; completion is event-driven. A single thread can drive thousands of async I/O ops.
- **The trap:** `Task.Run` for I/O just moves the blocking to a pool thread — you still hold a thread, and you pay scheduling. Async I/O holds *no* thread.

**Decision table:**

| Work | Tool |
|---|---|
| I/O-bound (HTTP, DB, files) | `async/await` |
| CPU-bound (transform, calculate) | `Parallel.For` / `Parallel.ForEach` / PLINQ / `Task.Run` |
| CPU-bound with async inside | `Task.Run` + async inside (compute then await) |
| Fan-out I/O | `Task.WhenAll` |
| Bounded concurrent I/O | `SemaphoreSlim.WaitAsync` / `Channel<T>` |
| Streaming producers/consumers | `Channel<T>` |

**Async doesn't make one operation faster** — it improves *scalability* (more concurrent requests per thread). CPU work isn't sped up by async.

**`Parallel.ForEachAsync`** (net6+): async-friendly parallel loop with `MaxDegreeOfParallelism` — for I/O with bounded concurrency.

### Real World Example (Healthcare)

- **Async:** a FHIR gateway — thousands of concurrent chart fetches on a few dozen threads.
- **Parallel:** normalizing 1M lab rows across 8 cores.
- **Both:** a batch job that fetches 10k patient records (async I/O, capped concurrency) then normalizes each (parallel CPU).

### Production Code Example

```csharp
// Async I/O with a concurrency cap — the realistic pipeline
public async Task ProcessBatchAsync(IReadOnlyList<string> ids, CancellationToken ct)
{
    using var gate = new SemaphoreSlim(8);          // max 8 concurrent fetches
    var tasks = ids.Select(async id =>
    {
        await gate.WaitAsync(ct);
        try { return await _gateway.FetchAsync(id, ct); }
        finally { gate.Release(); }
    }).ToArray();

    var patients = await Task.WhenAll(tasks);        // all started, threads return on awaits

    // CPU-bound normalization — parallel on cores
    Parallel.ForEach(patients, new ParallelOptions { MaxDegreeOfParallelism = Environment.ProcessorCount },
        p => Normalize(p));
}
```

**Key lines explained:**

- `SemaphoreSlim(8)` bounds downstream load — async, no thread blocked while waiting.
- `Select(async ...)` + `WhenAll` — fan-out without serializing.
- `Parallel.ForEach` for the CPU phase — this is where parallelism belongs.

### Advantages / Disadvantages

| | Async | Parallel |
|---|---|---|
| Threads held | no | yes (pool) |
| Best for | I/O | CPU |
| Speed of one op | same | same (or slightly slower) |
| Scalability | high | bounded by cores |

### Best Practices

- I/O → async; CPU → parallel; never mix unnecessarily (`Task.Run` around async only when you must bound CPU time).
- Cap concurrency explicitly (SemaphoreSlim/Channel) instead of unbounded fan-out.
- Use `Parallel.ForEachAsync` for I/O parallel loops.

### Common Mistakes

- `async` for CPU-bound (no gain, allocation).
- `Task.Run` for I/O (thread held anyway).
- Unbounded fan-out (thousands of tasks → resource blowup).
- Believing async improves latency per request.

### Interview Follow-up Questions

1. Does async make code faster? (No — more scalable.)
2. Async vs. parallel — which for DB queries? (Async — I/O.)
3. What's `Parallel.ForEachAsync` for? (Bounded-concurrency I/O loop.)

### Senior Level Talking Points

> "The three words are a *resource* question: threads are the resource, and async spends threads only during computation, not during waits; parallelism spends them to use cores; concurrency caps spend them deliberately. In healthcare batch pipelines I combine all three — async fan-out, a semaphore cap to protect downstream systems, then parallel CPU phases — and I document *which* thread budget each phase uses. That's how you get a batch that scales linearly with cores without hammering the DB."

### Memory Trick

**"Async waits without a worker; parallel hires workers per core; concurrency counts the workers."**

---

## 7.7 Producer/Consumer with `Channel<T>` and `BlockingCollection<T>`

### Interview Answer (30–45 seconds)

> "A producer/consumer pipeline decouples work generation from processing with a bounded buffer: producers `Write`, consumers `Read`. `Channel<T>` is the modern async-first option — `Channel.CreateBounded` gives backpressure (a `FullMode` policy), `WriteAsync`/`ReadAllAsync` are async, and it's the foundation of high-throughput services. `BlockingCollection<T>` is the older blocking option (sync `Add`/`Take`, supports bounding and cancellation). I use `Channel` for everything new: ingestion pipelines, decoupling a request from background processing, and distributing work to `BackgroundService` workers."

### Detailed Explanation

**`Channel<T>`:**

- `Channel.CreateBounded<T>(options)` / `Channel.CreateUnbounded<T>()`.
- `.Writer`: `WriteAsync` (respects bound + `FullMode`), `TryWrite`, `Complete`.
- `.Reader`: `ReadAsync`/`ReadAllAsync`, `TryRead`, `WaitToReadAsync`, `Completion`.
- `FullMode` policies: `Wait` (backpressure — writer waits), `DropNewest`/`DropOldest`/`DropWrite` (drop policy), `Dropped` (fail).
- Single/multi reader/writer options (`SingleReader = true` optimizes).
- Backpressure = memory safety: with `Wait`, the writer blocks when the buffer is full, so memory stays bounded.
- **Completion:** `Writer.Complete()` → `ReadAllAsync` ends after draining; `Complete(exception)` propagates the fault to readers.

**`BlockingCollection<T>`:**

- Wraps an `IProducerConsumerCollection<T>`; bounded with a max count; `Add` blocks when full; `Take` blocks when empty; supports `CancellationToken`.
- `GetConsumingEnumerable()` — the drain pattern.
- Sync-first (blocks threads); legacy vs. `Channel`.

**When each:**

| Need | Tool |
|---|---|
| Async, backpressure, high-throughput | `Channel<T>` |
| Sync blocking producers/consumers | `BlockingCollection<T>` |
| Batch + flush semantics | Channel + `TryRead` batching |
| Multi-consumer work distribution | Channel (multi-reader) |

### Real World Example (Healthcare)

HL7 message ingestion:

```csharp
Channel<Hl7Message> _inbox = Channel.CreateBounded<Hl7Message>(
    new BoundedChannelOptions(10_000) { FullMode = BoundedChannelFullMode.Wait, SingleReader = true });
```

A TCP listener writes parsed messages; a `BackgroundService` drains and persists them. Backpressure protects memory; `Complete()` during shutdown drains gracefully.

### Production Code Example

```csharp
public sealed class IngestPipeline
{
    private readonly Channel<Hl7Message> _channel =
        Channel.CreateBounded<Hl7Message>(new BoundedChannelOptions(10_000)
        {
            FullMode = BoundedChannelFullMode.Wait,   // backpressure
            SingleReader = true,
            SingleWriter = false
        });

    public ValueTask PublishAsync(Hl7Message message, CancellationToken ct)
        => _channel.Writer.WriteAsync(message, ct);   // waits if buffer full

    // Consumer: drain and batch-persist
    public async Task RunAsync(CancellationToken ct)
    {
        var batch = new List<Hl7Message>(500);
        await foreach (var message in _channel.Reader.ReadAllAsync(ct))
        {
            batch.Add(message);
            if (batch.Count >= 500)
            {
                await _persister.SaveBatchAsync(batch, ct);
                batch.Clear();
            }
        }
        if (batch.Count > 0) await _persister.SaveBatchAsync(batch, ct);  // final flush
    }

    public void Shutdown() => _channel.Writer.Complete();   // graceful drain
}
```

**Key lines explained:**

- `Bounded` + `Wait` — the writer paces itself when consumers are slow: bounded memory.
- `ReadAllAsync` — async drain until `Complete()`.
- Batch flush pattern — amortizes DB writes.
- `Complete()` → the reader finishes after draining → clean shutdown.

### Internal Working

- `Channel` unbounded = a `ConcurrentQueue`-ish with async waiters; bounded = a `Deque` + semaphore-like counters with waiters list.
- `WriteAsync` when full with `Wait` → returns an incomplete `ValueTask` that completes when space frees (async waiter, no thread held).
- `ReadAllAsync` = loop of `WaitToReadAsync`/`TryRead`.

### Advantages / Disadvantages

| | Channel | BlockingCollection |
|---|---|---|
| Async | yes | no (blocks) |
| Backpressure | `FullMode` | max count + blocking Add |
| Throughput | very high | high |
| Modern default | yes | legacy |

### Best Practices

- `Channel.CreateBounded` for production (never unbounded unless proven).
- Pick `FullMode` deliberately (`Wait` for backpressure; drop policies for telemetry).
- Use `SingleReader`/`SingleWriter` hints for perf.
- `Complete()` for graceful shutdown; drain before exit.

### Common Mistakes

- Unbounded channels → unbounded memory under load.
- Blocking on `Take` in async code.
- Not completing the writer → consumer hangs on shutdown.
- Multiple writers racing with `SingleWriter = true`.

### Interview Follow-up Questions

1. `Channel` vs `BlockingCollection`? (Async+backpressure vs sync blocking; modern vs legacy.)
2. What is backpressure? (Buffer full → producer waits/drops.)
3. How do you shut down a channel gracefully? (`Complete()` then drain.)
4. `FullMode` options? (Wait, DropNewest, DropOldest, DropWrite.)

### Senior Level Talking Points

> "Producer/consumer is where you buy *memory safety and decoupling*. The senior design rule: every channel is bounded, every `FullMode` is a conscious policy (backpressure for a clinical ingest pipeline — you'd rather slow the feed than drop PHI; drop policies only for non-critical telemetry), and shutdown is a first-class flow (`Complete()` + drain) so restarts don't lose the tail of the queue. I also batch consumers against the DB — drain 500 messages, persist once — because that's a 500x reduction in write calls."

### Memory Trick

**"A bounded channel is a pipe with a pressure valve — full pipes slow the pump."**

---

## Chapter 7 Wrap-Up

### Top 10 Interview Questions From This Chapter

1. Thread vs. Task vs. ThreadPool — explain each.
2. What happens when all pool threads are blocked? (Starvation; SetMinThreads.)
3. `WhenAll` vs `WhenAny` — semantics and use cases.
4. Does `await WhenAll` throw `AggregateException`? (First unwrapped; all via `.Exception`.)
5. `lock` vs `Monitor` vs `Mutex` vs `SemaphoreSlim` — when each?
6. Explain deadlock with the ABBA pattern and list preventions.
7. Why is `volatile` insufficient for `count++`?
8. Async vs. parallel — which is for I/O? Why?
9. What does `Channel<T>` give you that `BlockingCollection` doesn't?
10. How do you diagnose a deadlock in production?

### Revision Notes (1 page)

- **Thread vs Task:** thread = OS execution context (expensive); ThreadPool recycles workers; Task = promise of work, not a thread. `Task.Run` = schedule on pool; async I/O = no thread held during wait.
- **Pool starvation:** all threads blocked → slow thread injection → throughput collapse; `SetMinThreads` raises the floor.
- **Composition:** `WhenAll` all-done, first-fault thrown (unwrapped since .NET 5); `WhenAny` first-done (timeouts, races); `WaitAsync` for timeouts; fan-out then `WhenAll` (never await-in-loop).
- **Sync primitives:** `lock`/`Monitor` (reentrant, in-process), `Mutex` (cross-process), `SemaphoreSlim` (async concurrency cap, `WaitAsync`), `ReaderWriterLockSlim` (read-heavy), `SpinLock` (micro-sections only).
- **Deadlock/race:** ABBA circular wait; fix with consistent ordering, timeouts, single-lock, lock-free; races = non-atomic read-modify-write (use `Interlocked`); memory model needs fences.
- **volatile/Interlocked:** volatile = fresh single-value reads (acquire/release); Interlocked = atomic ops (`Increment`, `CompareExchange`). `volatile` ≠ atomic compound.
- **Async vs parallel vs concurrency:** async = I/O without threads; parallel = CPU on cores; concurrency = bounded progress. Never `Task.Run` for I/O.
- **Producer/consumer:** `Channel<T>` bounded + `FullMode` backpressure; `Complete()` drain on shutdown; batch consumers; `BlockingCollection` legacy sync.

### Things Interviewers Expect From 5+ Years Experience

- Precise "thread vs task vs async" articulation with a thread-count mental model.
- Starvation, sync-over-async, and deadlock diagnosis instincts.
- Lock-free-first mindset (`Interlocked`, concurrent collections, immutables).
- Choice of the *right* primitive per scenario (incl. async-aware `SemaphoreSlim.WaitAsync`).
- Production tooling: dumps, `dotnet-stack`, counters.

### Cheat Sheet

```
THREAD = OS execution (expensive, ~1MB stack) | Task = promise (not a thread)
Task.Run  = CPU/blocking work → pool thread
async     = I/O → NO thread held during wait
STARVATION: all pool threads blocked → SetMinThreads; hunt sync-over-async

WhenAll = all done (first fault unwrapped) | WhenAny = first done
WaitAsync(ts) = timeout pattern | never await in loop — fan-out then WhenAll

lock/Monitor  = reentrant in-process critical section
Mutex         = cross-process
SemaphoreSlim = N permits, WaitAsync (async!)
RWLS          = many readers/one writer
SpinLock      = microseconds only

DEADLOCK = ABBA circular wait → ordering/timeouts/single-lock
RACE     = non-atomic read-modify-write → Interlocked
volatile = fresh single value (NOT atomic compound)

Producer/Consumer:
  Channel<T> bounded + FullMode.Wait = backpressure | Complete() = graceful drain
  BlockingCollection = legacy sync
  batch consumers (500 msgs → 1 DB write)
```

### Flash Cards

**Q1:** Thread vs Task? **A:** Thread = OS execution; Task = promise/work unit (runs on pool or async).

**Q2:** Async holds a thread during I/O wait? **A:** No — thread returns to pool.

**Q3:** Await WhenAll exception type? **A:** Unwraps the first (since .NET 5); all via `.Exception`.

**Q4:** Deadlock prevention? **A:** Consistent lock ordering, timeouts, avoid nested locks.

**Q5:** volatile count++ safe? **A:** No — three sub-ops; use `Interlocked.Increment`.

**Q6:** Cross-process mutual exclusion? **A:** `Mutex` (named).

**Q7:** Async concurrency cap? **A:** `SemaphoreSlim.WaitAsync`.

**Q8:** Backpressure in Channel? **A:** Bounded buffer + `FullMode.Wait` — writer waits.

**Q9:** Shutdown channel gracefully? **A:** `Writer.Complete()` then drain via `ReadAllAsync`.

**Q10:** What does `CompareExchange` do? **A:** Atomic conditional swap (CAS).

### Interview Confidence Score

**Medium-Hard.** Multithreading is a top-3 differentiator for senior roles. Expect deep probing on async/thread models, starvation, deadlock prevention, and the correct primitive for each scenario. Lock-free design awareness sets seniors apart.

---

*Continue → Chapter 8: Dependency Injection*
