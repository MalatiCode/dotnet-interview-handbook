# Chapter 5: Collections

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** `List<T>` vs. arrays, `Dictionary<TKey,TValue>` internals and hash collisions, `HashSet<T>`, `LinkedList<T>`, `Stack<T>`/`Queue<T>`, `SortedDictionary` vs. `SortedList`, `ConcurrentDictionary` and the concurrent collections, `IReadOnlyList` vs. `IList`, capacity/growth behavior, and choosing the right collection.

---

## 5.1 Choosing the Right Collection

### Interview Answer (30–45 seconds)

> "Choosing a collection is a question of *access patterns*: do I read by index, by key, or by position; how often do I insert/remove at the ends or middle; do I need uniqueness; is it single-threaded or shared? The mental model: arrays and `List<T>` for index access; `Dictionary<TKey,TValue>` for O(1) lookup by key; `HashSet<T>` for fast membership; `Queue<T>`/`Stack<T>` for FIFO/LIFO; `LinkedList<T>` only for O(1) inserts/removes in the middle (rarely worth it — node overhead and cache misses). For concurrency, `ConcurrentDictionary<TKey,TValue>` is the workhorse; `BlockingCollection<T>` and `Channel<T>` for producer/consumer. I also follow the golden rule: expose `IReadOnlyList<T>`/`IEnumerable<T>` outward and keep the concrete mutable type internal."

### Detailed Explanation

**Access-pattern decision table:**

| Need | Collection | Complexity |
|---|---|---|
| Index access / iteration | `T[]`, `List<T>` | O(1) index, O(n) iterate |
| Lookup by key | `Dictionary<K,V>` | O(1) avg |
| Membership test | `HashSet<T>` | O(1) avg |
| FIFO | `Queue<T>` | O(1) enq/deq |
| LIFO | `Stack<T>` | O(1) push/pop |
| Sorted unique set | `SortedSet<T>` | O(log n) |
| Sorted key-value | `SortedDictionary<K,V>` | O(log n) |
| Sorted list (memory) | `SortedList<K,V>` | O(log n) lookup, O(n) insert |
| Middle insert/remove | `LinkedList<T>` | O(1) if node known |
| Thread-safe dict | `ConcurrentDictionary<K,V>` | lock-free-ish |
| Producer/consumer | `Channel<T>`, `BlockingCollection<T>` | - |
| Read-only view | `IReadOnlyList<T>` | - |

**Capacity/growth:**

- `List<T>`/`Dictionary` default capacity grows by doubling when full (List: internal `T[]`, doubles; Dictionary: internal buckets array, resizes when load factor ~0.72–1). Growing = allocate new array + copy → O(n).
- Pre-size with capacity when you know the size: `new List<Observation>(10_000)`, `new Dictionary<string, int>(1000)`.
- `List<T>.TrimExcess` reduces capacity (frees memory after bulk load).

**Interface discipline:**

- Prefer `IReadOnlyList<T>`/`IReadOnlyCollection<T>` for *exposure*; accept `IEnumerable<T>` for *input*.
- `IList<T>` implies writable surface — don't over-expose.
- Arrays: fixed size; use only when size truly fixed or for interop/perf hot loops.

### Real World Example (Healthcare)

```csharp
// Exposure discipline
public sealed class PatientChart
{
    // internal: mutable list for building
    private readonly List<Observation> _observations = new();

    // exposed: read-only view — callers can't mutate
    public IReadOnlyList<Observation> Observations => _observations;

    public void Add(Observation o) => _observations.Add(o);
}

// O(1) membership for allowed codes
private static readonly HashSet<string> CriticalCodes = new(StringComparer.Ordinal)
{
    "GLU", "POT", "SOD", "CRE"
};
```

### Production Code Example

```csharp
public sealed class CohortBuilder
{
    // Pre-size when the count is known — avoids repeated growth copies
    private readonly List<Guid> _patientIds = new(10_000);

    public void AddPatient(Guid id) => _patientIds.Add(id);

    public Guid[] ToSnapshot() => _patientIds.ToArray();   // fixed-size result

    public IReadOnlySet<Guid> AsSet()
        => new HashSet<Guid>(_patientIds);                 // O(1) membership later
}
```

**Key lines explained:**

- `new List<Guid>(10_000)` — capacity hint avoids reallocation churn.
- `_patientIds.ToArray()` — hands out a stable snapshot; internal list stays private.
- `HashSet<Guid>` for later membership queries — O(1) instead of O(n) scans.

### Internal Working

- `List<T>` — `T[] _items` + `_size`; `Add` writes at `_size`, doubles on overflow.
- `Dictionary<K,V>` — array of buckets; each bucket is a chain (linked list) of entries with hash + key + value; index = `hash % buckets.Length` (with `HashHelpers` mixing).
- `HashSet<T>` — dictionary-without-values (a slot table); same hashing.
- `Queue<T>`/`Stack<T>` — circular array / array with head pointer.
- `SortedDictionary<K,V>` — red-black tree. `SortedList` — two arrays (keys/values), binary search for lookup, shift for insert.

### Advantages / Disadvantages

| | Advantage | Disadvantage |
|---|---|---|
| Array | cache-friendly, zero overhead | fixed size |
| List<T> | dynamic, index fast | middle insert O(n) |
| Dictionary | O(1) key lookup | hash cost, memory |
| HashSet | O(1) membership | no ordering, no dups |
| LinkedList | O(1) known-node insert | node overhead, cache misses |
| Sorted* | ordered traversal | insert cost |

### Best Practices

- Choose by access pattern, not habit.
- Pre-size when size is known.
- Expose `IReadOnlyList<T>`/`IEnumerable<T>`; keep concrete types internal.
- Use `StringComparer.Ordinal` for code keys (healthcare).
- For hot loops over arrays, prefer `foreach` over arrays (JIT-vectorized) or `for` when index needed.

### Common Mistakes

- `List<T>` for frequent middle inserts (O(n)) — use `LinkedList` or a different data shape.
- `Dictionary` with mutable keys (hash breaks).
- Using `HashSet` when you need ordered/deduped access (use `SortedSet`).
- Exposing `IList<T>` when you meant read-only.
- Forgetting capacity hints → repeated O(n) copies on bulk load.

### Interview Follow-up Questions

1. Why is `LinkedList<T>` rarely used despite O(1) inserts? (Node allocation + cache misses; traversal dominates.)
2. When is a `Dictionary` the wrong choice? (Small sets, ordered iteration, frequent enumeration.)
3. `IReadOnlyList<T>` vs `IList<T>` — which to expose? (Read-only exposure; write internally.)
4. How does `List<T>` grow? (Doubles; O(n) copy; pre-size to avoid.)

### Senior Level Talking Points

> "Collection choice is an *access-pattern* decision, and the senior move is to make the choice visible in the signature: a method returning `IReadOnlyList<T>` says 'snapshot, don't mutate'; returning `IEnumerable<T>` says 'stream, maybe re-runs'; returning a concrete `List<T>` leaks growth strategy. In healthcare, where code sets are membership-checked constantly, `HashSet` with ordinal comparers is both a correctness and a perf decision — and I document the comparer because 'GLU' vs 'glu' is a clinical bug, not a style bug."

### Memory Trick

**"List by index, Dictionary by key, HashSet for 'is it in?', Queue for 'who's next?', Stack for 'undo.'"**

---

## 5.2 `List<T>` vs. Array vs. `IReadOnlyList<T>`

### Interview Answer (30–45 seconds)

> "Arrays are fixed-size contiguous memory — cache-friendly, zero overhead, but you can't grow them. `List<T>` is a growable wrapper over an array with a size counter; it doubles capacity on growth and adds ~O(1) amortized appends. `IReadOnlyList<T>` is the interface that promises read-only access — no `Add`/`Remove`/index-setter — so it's the right *exposure* type even though the concrete type is a `List<T>`. My defaults: internal mutable state → `List<T>`; fixed-size results → array; public API surfaces → `IReadOnlyList<T>` or `IEnumerable<T>`."

### Detailed Explanation

**Arrays:**

- `T[]` — fixed length at creation; index O(1); `Array.Length`.
- Foreach over arrays is fast (JIT recognizes and uses direct element access + vectorization).
- `Array.Resize` copies (not in-place).
- Good for: fixed-size buffers, interop, tightly-cached numeric hot loops, `stackalloc`-like semantics.

**`List<T>`:**

- Backing `T[] _items`; `_count`; `Add` → `_items[_count++] = item`; on overflow → `Grow` (allocate 2x, `Array.Copy`).
- Capacity vs Count: capacity is the allocated size; count is used size.
- `Insert(index)` — O(n) shift; `RemoveAt` — O(n) shift; `Add` — amortized O(1).
- `Capacity`, `TrimExcess`, `AsReadOnly()`, `BinarySearch` (O(log n), sorted only).
- `CollectionsMarshal.AsSpan(list)` → span over the backing array (careful: don't add while spanned).

**`IReadOnlyList<T>` / `IReadOnlyCollection<T>`:**

- Read surface only: indexer get, `Count`. No mutation methods.
- `List<T>` implements it; the concrete instance still mutable — the *reference type* promises read-only usage by callers.
- Prefer over `IList<T>` for exposure (avoids accidental mutation).
- Note: casting back to `List<T>` defeats it — by convention, not enforcement.

**Interface hierarchy:**

```
IEnumerable<T>  →  ICollection<T>  →  IList<T>
       │                                  │
       └─ IReadOnlyCollection<T> ──► IReadOnlyList<T>
```

**Selection rules:**

| Surface | Use |
|---|---|
| Accept "give me items to iterate" | `IEnumerable<T>` |
| Accept "index into it" | `IReadOnlyList<T>` |
| Return immutable-ish snapshot | `IReadOnlyList<T>` (or `ImmutableArray<T>`) |
| Internal mutable | `List<T>` |
| Fixed buffer/perf | array |
| Struct-like value snapshot | `ImmutableArray<T>` (from `System.Collections.Immutable`) |

### Real World Example (Healthcare)

```csharp
public sealed record PatientSummary(Guid Id, string Mrn, string FamilyName);

// Repo returns a read-only snapshot; no caller can mutate the list
public async Task<IReadOnlyList<PatientSummary>> GetActiveAsync(CancellationToken ct)
{
    var results = await _db.Patients
        .Where(p => p.IsActive)
        .Select(p => new PatientSummary(p.Id, p.Mrn, p.FamilyName))
        .ToListAsync(ct);
    return results;                 // List<T> exposed as IReadOnlyList<T>
}
```

### Production Code Example

```csharp
// Internal: mutable List for building
public sealed class Roster
{
    private readonly List<string> _mrn = new(500);

    public void Add(string mrn) => _mrn.Add(mrn);

    // Exposed: read-only index access — callers can read but not mutate
    public IReadOnlyList<string> Items => _mrn;

    // Fixed-size snapshot — arrays are the right "final result" for a report
    public string[] ToArray() => _mrn.ToArray();

    // Count without exposing the list
    public int Count => _mrn.Count;
}
```

**Key lines explained:**

- `IReadOnlyList<string>` exposes indexing + Count, no mutation.
- `ToArray()` returns a fixed-size copy — safe to hand across layers.
- `Capacity` hint `500` avoids growth copies during bulk build.

### Internal Working

- `List<T>` growth: new capacity = old * 2 (from default 4: 4→8→16→32...) — amortized O(1) appends.
- `List<T>` is not thread-safe — document or synchronize.

### Advantages

- List: dynamic, cache-friendly backing array, rich API.
- Array: minimal, fast, fixed.
- IReadOnlyList: contract safety at the boundary.

### Disadvantages

- List: middle ops O(n), not thread-safe, growth copies.
- Array: can't grow.
- IReadOnlyList: only a compile-time promise; cast leaks.

### Best Practices

- Pre-size; prefer `AddRange`/bulk ops over per-item `Add` in loops where possible (still amortized, but fewer growth events).
- Expose read-only interfaces outward.
- Use `ImmutableArray<T>`/`ImmutableList<T>` for genuinely immutable shared structures.
- For extremely hot numeric loops, arrays beat lists for iteration.

### Common Mistakes

- `List<T>` where you only ever need fixed size.
- Exposing `List<T>` publicly (callers can mutate).
- `BinarySearch` on an unsorted list (wrong results silently).
- Calling `AsReadOnly` then mutating through the original reference.

### Interview Follow-up Questions

1. How does `List<T>` grow internally? (Doubles capacity; O(n) copy on growth; amortized O(1) add.)
2. `IReadOnlyList<T>` — is the underlying object immutable? (No — only the reference contract.)
3. When is an array better than a list? (Fixed size, hot loops, interop.)
4. What's `CollectionsMarshal.AsSpan` for? (Zero-copy span over backing array; use with care.)

### Senior Level Talking Points

> "The senior signature habit is *reading the type name as a contract*: `IReadOnlyList<T>` means 'I'm handing you a snapshot; don't mutate it,' `IEnumerable<T>` means 'I may stream this and re-run it,' and a raw array means 'fixed shape, done.' In a healthcare SDK consumed by many teams, those contracts prevent a whole class of 'the caller cleared my list' bugs — the kind that corrupt a shared cohort between two features."

### Memory Trick

**"Array = fixed shelf; List = expanding shelf; IReadOnlyList = the 'look, don't touch' sign."**

---

## 5.3 `Dictionary<TKey,TValue>` Internals

### Interview Answer (30–45 seconds)

> "A `Dictionary<TKey,TValue>` is a hash table: the keys' `GetHashCode()` is used to pick a bucket (via a fast mod/and against the bucket count), and collisions within a bucket are resolved by chaining. Lookup is O(1) average, worst case O(n) if hashing degenerates (all keys colliding). Internally there's a buckets array of ints and an entries array storing hash, key, value, and the 'next' pointer forming chains. Resizing happens when the load factor is exceeded — it rehashes everything (O(n)). The critical rule: the key's `GetHashCode()` must be stable and match `Equals` — mutable keys, or keys whose hash changes, silently break lookups."

### Detailed Explanation

**Anatomy (conceptually):**

```
buckets:   [ 3 | -1 | 0 | -1 | 2 | ... ]      # head index into entries per bucket
entries:   [ {hash,key,val,next}, ... ]       # entries in insertion order

lookup: hash = key.GetHashCode() & (buckets.Length-1)
        walk chain starting at buckets[hash] until key matches Equals
```

- The initial bucket count is prime-ish; it resizes when count reaches a threshold (roughly 0.72 load factor internally via `HashHelpers`).
- Collision chain = linked list of entry indices.
- `Dictionary` uses the runtime-provided hash code; for strings that's randomized per-process (hash randomization for security — prevents hash-collision DoS attacks).
- Equality: `EqualityComparer<TKey>.Default` → uses `IEquatable<TKey>` if implemented, else `object.Equals`/`GetHashCode`.

**Performance characteristics:**

- `Add`/indexer-set/lookup: O(1) average (given good hashing).
- Worst case (all colliding): O(n).
- `ContainsKey`, `TryGetValue` — O(1).
- Removal: O(1) average, marks entry as free (frees array slot for reuse).
- Enumeration: unordered (insertion order NOT guaranteed in `Dictionary`; do not rely on it).

**Design choices / variants:**

- Pre-size with `new Dictionary<K,V>(capacity)` — avoids rehash storms.
- Custom comparer: `new Dictionary<string, X>(StringComparer.OrdinalIgnoreCase)`.
- `FrozenDictionary<TKey,TValue>` (.NET 8) — for *read-only*, fully-built dictionaries: better memory and lookup perf via perfect-hashing-style optimization. Use for static lookup tables.
- `ImmutableDictionary` — persistent, thread-safe snapshots (copy-on-write), slower; for multi-threaded immutable state.
- `ConcurrentDictionary` — see 5.6.

**Key correctness rule:** `GetHashCode()` must return the same value for equal keys, and must not change while the key is in the dictionary. Strings/records/ints are safe; a mutable object used as a key is a bug waiting to happen.

### Real World Example (Healthcare)

```csharp
// Pre-sized, ordinal keys — a LOINC-to-display cache
private readonly Dictionary<string, string> _loincDisplay = new(2_000, StringComparer.Ordinal);

// .NET 8: frozen dictionary for a static code table
private static readonly FrozenDictionary<string, string> CriticalCodes =
    LoadCriticalCodes().ToFrozenDictionary(StringComparer.Ordinal);
```

### Production Code Example

```csharp
public sealed class MedicationDoseCache
{
    private readonly Dictionary<string, (string Drug, decimal Dose)> _byOrder =
        new(1_000, StringComparer.Ordinal);

    public bool TryGet(string orderId, out (string Drug, decimal Dose) dose)
        => _byOrder.TryGetValue(orderId, out dose);   // O(1), single lookup

    public void Set(string orderId, string drug, decimal dose)
        => _byOrder[orderId] = (drug, dose);          // indexer set: add or update
}

// FrozenDictionary for an immutable lookup (reads only, after startup)
public sealed class DrugCodeService
{
    private readonly FrozenDictionary<string, string> _drugToAtc;
    public DrugCodeService(IEnumerable<(string Drug, string Atc)> mappings)
        => _drugToAtc = mappings.ToFrozenDictionary(x => x.Drug, x => x.Atc, StringComparer.Ordinal);

    public string? Lookup(string drug) => _drugToAtc.GetValueOrDefault(drug);   // O(1)
}
```

**Key lines explained:**

- `TryGetValue` — one hash lookup, no double-lookup via `ContainsKey`.
- Pre-size + ordinal comparer.
- `ToFrozenDictionary` — .NET 8's optimized read-only dictionary for static data.

### Internal Working

1. `GetHashCode()` → mixed with bucket-count mask → bucket index.
2. Insert walks the chain; if key found → replace value; else append entry, link into chain.
3. Resize (load factor exceeded) → new buckets+entries arrays, rehash all entries (O(n), pauses).
4. .NET uses *randomized string hashing* (per-process seed) to mitigate collision attacks.

### Advantages

- O(1) average key lookup; rich API (`TryGetValue`, `GetOrAdd` via extensions); pre-size/custom comparers.

### Disadvantages

- Memory overhead (buckets + entries arrays); unordered enumeration; rehash pauses; worst-case collisions.

### Best Practices

- Use `TryGetValue` (avoid double lookups).
- Pre-size for known volumes.
- Use `FrozenDictionary` for immutable static tables (.NET 8).
- Never use mutable keys.
- For string keys, prefer ordinal comparers.

### Common Mistakes

- Mutable key objects → "key vanished from dictionary."
- Relying on `Dictionary` enumeration order (insertion order is not guaranteed).
- `ContainsKey` then `[]` (two lookups) instead of `TryGetValue`.
- `GetHashCode` returning a constant (all keys collide → O(n)).
- Case/culture mismatch on string keys.

### Interview Follow-up Questions

1. How are hash collisions resolved in `Dictionary`? (Chaining via entries' next pointers.)
2. When does the dictionary resize? (Load factor ~0.72-ish; rehash O(n).)
3. What's the difference between `GetHashCode` and `Equals` roles in lookup? (Hash → bucket; Equals → verify within chain.)
4. `FrozenDictionary` vs `Dictionary`? (.NET 8; read-only optimized.)
5. Is `Dictionary` iteration ordered? (No — not guaranteed.)

### Senior Level Talking Points

> "The interview gold is the *correctness* rule: a dictionary key's hash must be stable and consistent with `Equals`. I've debugged a 'patient spontaneously loses their medications' bug that was a mutable key. The senior framing: if you need a lookup by a property that can change, key by an immutable id (`Guid`/string id) — never by a mutable object. And I reach for `FrozenDictionary` for code tables because at startup we build them once and read them millions of times — the .NET 8 optimization is free wins."

### Diagram

```
key.GetHashCode() → bucket index (mask)
buckets:  [3][-1][0][-1][2][...]
entries:
  idx0: {h1, keyA, valA, next:-1}
  idx1: {h2, keyB, valB, next:-1}
  idx2: {h1, keyC, valC, next:0}    # chain for bucket0: 2 → 0
lookup keyC: bucket0 → entry2 → Equals? yes → valC
```

### Memory Trick

**"Hash points you to the right street; Equals knocks on the exact door."**

---

## 5.4 `HashSet<T>` and `SortedSet<T>`

### Interview Answer (30–45 seconds)

> "`HashSet<T>` is an unordered set with O(1) membership (`Add`, `Contains`, `Remove`) built on the same hash-bucket machinery as `Dictionary` (it's basically a dictionary without values). `SortedSet<T>` keeps elements sorted via a balanced tree (red-black) with O(log n) operations and ordered traversal. I use `HashSet` for deduplication and membership checks, and `SortedSet` when I need the smallest/next-in-order. They're not thread-safe; `ConcurrentDictionary<K,V>` or `ImmutableHashSet` cover concurrent needs."

### Detailed Explanation

**`HashSet<T>`:**

- `Add` returns `bool` — false if already present (useful for dedupe in one pass).
- `Contains` — O(1) average.
- Set ops: `UnionWith`, `IntersectWith`, `ExceptWith`, `SymmetricExceptWith`, `IsSubsetOf`, `IsSupersetOf`, `SetEquals`.
- `Comparer<T>` configurable (`StringComparer.OrdinalIgnoreCase`).
- Enumeration unordered.
- Backing: slot table (like dictionary entries minus values).

**`SortedSet<T>`:**

- Ordered; `Min`/`Max` O(1)-ish (log n).
- `GetViewBetween(min,max)` — ordered range views (great for time ranges).
- `Reverse()` — descending.
- Operations O(log n) (red-black tree).

**`SortedDictionary<K,V>` vs `SortedList<K,V>`** (if asked):

- `SortedDictionary` — tree; O(log n) insert/lookup; good for frequent inserts.
- `SortedList` — two arrays; O(log n) lookup (binary search), O(n) insert (shift); good for mostly-read scenarios with bulk-load.

**Immutable sets:**

- `ImmutableHashSet<T>`/`ImmutableSortedSet<T>` — persistent; `Add` returns a *new* set sharing structure; thread-safe by immutability. Use for cross-thread sharing.

### Real World Example (Healthcare)

```csharp
// Dedupe an HL7 feed in one pass
var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
var unique = new List<Message>();
foreach (var m in messages)
    if (seen.Add(m.MessageId))         // Add returns false for duplicates
        unique.Add(m);

// Ordered set: who's next in triage (by priority)
var triageQueue = new SortedSet<(int priority, Guid id)>();
triageQueue.Add((1, patientA));
triageQueue.Add((3, patientB));
var next = triageQueue.Min;            // highest priority
```

### Production Code Example

```csharp
public sealed class LabCodeSet
{
    private readonly HashSet<string> _codes = new(StringComparer.Ordinal);

    public bool Add(string code) => _codes.Add(code);       // returns false if dup
    public bool Contains(string code) => _codes.Contains(code);  // O(1)
    public int Count => _codes.Count;
    public IEnumerable<string> Snapshot() => _codes.ToArray();    // unordered snapshot
}

// Sorted view for reporting ranges
public IEnumerable<Observation> InTimeWindow(SortedSet<Observation> byTime, DateTimeOffset from, DateTimeOffset to)
    => byTime.GetViewBetween(new Observation(from), new Observation(to));
```

**Key lines explained:**

- `_codes.Add` returning `bool` enables one-pass dedupe.
- `StringComparer.Ordinal` — exact code semantics.
- `GetViewBetween` — ordered range without scanning the whole set.

### Advantages / Disadvantages

| | HashSet | SortedSet |
|---|---|---|
| Membership | O(1) avg | O(log n) |
| Order | none | sorted |
| Min/Max | no | yes |
| Range views | no | yes (`GetViewBetween`) |
| Memory | buckets | tree nodes |
| Best for | dedupe, membership | ordered dedupe, ranges |

### Best Practices

- Use `Add`'s bool for dedupe-in-one-pass.
- Choose comparer explicitly for strings.
- Prefer `HashSet` unless you need order or ranges.
- For concurrent membership, consider `ConcurrentDictionary<K,byte>` or `ImmutableHashSet` per snapshot.

### Common Mistakes

- Expecting `HashSet` to be ordered (it isn't).
- Using `SortedSet` for plain membership (O(log n) when O(1) suffices).
- Mutable elements in a set (hash instability).
- Forgetting comparer → case-sensitive surprises on codes.

### Interview Follow-up Questions

1. What does `Add` return on `HashSet`? (bool — false for duplicates.)
2. How does `SortedSet` store elements? (Red-black tree.)
3. When `SortedSet` over `HashSet`? (Ordering/ranges needed.)
4. `SortedList` vs `SortedDictionary`? (Array vs tree tradeoffs.)

### Memory Trick

**"HashSet answers 'in or out?' in a blink; SortedSet keeps the line in order."**

---

## 5.5 `Queue<T>`, `Stack<T>`, and `LinkedList<T>`

### Interview Answer (30–45 seconds)

> "`Queue<T>` is FIFO — enqueue at the tail, dequeue from the head, backed by a circular array. `Stack<T>` is LIFO, backed by a simple array with a top index. `LinkedList<T>` is a doubly-linked list with O(1) inserts/removes *if you already hold the node*, but node-per-element overhead and poor cache locality make it rarely the right answer — `List<T>` wins for most scenarios. I use queues for work pipelines and BFS, stacks for parsing/undo, and linked lists almost never outside very specific O(1)-middle-insert needs."

### Detailed Explanation

**`Queue<T>`:**

- `Enqueue` — add at tail; `Dequeue` — remove head; `Peek` — view head.
- Circular buffer: head/tail indices wrap; growth doubles capacity.
- `TryDequeue`/`TryPeek` (.NET Core 2.0+).
- O(1) enqueue/dequeue amortized.

**`Stack<T>`:**

- `Push`/`Pop`/`Peek`; array-backed with top pointer; O(1).
- `TryPop`/`TryPeek`.

**`LinkedList<T>`:**

- `AddFirst/AddLast/AddAfter/AddBefore`, `Remove(node)` — O(1) with node ref.
- Node = `LinkedListNode<T>` (value, prev, next).
- Sequential access O(n); enumeration is pointer-walking (cache misses).
- Not indexed.
- When to use: algorithms needing efficient splice/middle ops and you hold nodes; otherwise `List<T>`.

**Concurrent variants:**

- `ConcurrentQueue<T>`, `ConcurrentStack<T>` — lock-free-ish, thread-safe.
- `BlockingCollection<T>` — bounded blocking queue for producer/consumer.
- `Channel<T>` — the modern high-throughput producer/consumer (Chapter on Background Services).

### Real World Example (Healthcare)

```csharp
// FIFO: radiology work queue
var workQueue = new Queue<ImagingJob>();
workQueue.Enqueue(new ImagingJob(patientA, "CT"));
var job = workQueue.Dequeue();

// LIFO: undo medication correction steps
var undo = new Stack<MedicationCorrection>();
undo.Push(correction);
var last = undo.Pop();
```

### Production Code Example

```csharp
public sealed class TriageWorkQueue
{
    private readonly Queue<PatientId> _queue = new();
    private readonly object _gate = new();

    public void Enqueue(PatientId id)
    {
        lock (_gate) { _queue.Enqueue(id); }          // simple producer
    }

    public bool TryDequeue(out PatientId id)
    {
        lock (_gate) { return _queue.TryDequeue(out id); }  // consumer
    }

    public int Count { get { lock (_gate) { return _queue.Count; } } }
}
```

**Key lines explained:**

- Manual `lock` for thread-safe queue (or just use `ConcurrentQueue<T>` — prefer that in real code; this shows the mechanics).
- `TryDequeue` — non-throwing consumer pattern.

### Advantages / Disadvantages

| | Queue | Stack | LinkedList |
|---|---|---|---|
| Ops | FIFO O(1) | LIFO O(1) | known-node O(1) |
| Cache | good | good | poor |
| Indexing | no | no | no |
| Typical | pipelines, BFS | parsing, undo | rare |

### Best Practices

- Prefer `ConcurrentQueue<T>`/`Channel<T>` over manual locks for concurrency.
- Use `TryDequeue`/`TryPeek` over exception-based access.
- Reach for `LinkedList` only when you can justify node-held O(1) operations.

### Common Mistakes

- `Dequeue` on empty → throws (use `TryDequeue`).
- `LinkedList` for iteration-heavy work (slow).
- Manual locking when `ConcurrentQueue` exists.

### Interview Follow-up Questions

1. `Queue` vs `Stack` backing structures? (Circular array vs array+top.)
2. When would you actually use `LinkedList<T>`? (Known-node middle ops.)
3. `BlockingCollection` vs `Channel`? (Bounded blocking vs modern async-first.)

### Memory Trick

**"Queue is a checkout line; Stack is a stack of plates; LinkedList is a row of hand-holding nodes."**

---

## 5.6 Concurrent Collections

### Interview Answer (30–45 seconds)

> "The concurrent collections — `ConcurrentDictionary<TKey,TValue>`, `ConcurrentQueue<T>`, `ConcurrentStack<T>`, `ConcurrentBag<T>`, `ConcurrentBag`, and the newer `ConcurrentBag`/`Channel` — provide thread-safe access *internally* without requiring callers to lock. `ConcurrentDictionary` is the workhorse: it uses lock-striping (a set of locks per bucket-region) rather than a single global lock, so concurrent reads scale. The key discipline: individual operations are atomic, but multi-step sequences (check-then-act, read-modify-write) are NOT — those still need `TryUpdate`, `AddOrUpdate`, `GetOrAdd`, or an external lock. `ConcurrentBag` is a thread-local bag — great for per-thread work accumulation, not a queue."

### Detailed Explanation

**The family:**

- `ConcurrentDictionary<K,V>` — thread-safe dictionary; `GetOrAdd`, `AddOrUpdate`, `TryGetValue`, `TryUpdate`, `TryRemove`, `ContainsKey`.
- `ConcurrentQueue<T>` — FIFO; `Enqueue`/`TryDequeue`/`TryPeek`; mostly lock-free (uses segments + optimistic).
- `ConcurrentStack<T>` — LIFO; `Push`/`TryPop`/`TryPeek`.
- `ConcurrentBag<T>` — unordered bag with per-thread storage; `Add`/`TryTake`; best for producer-consumer where each thread adds/takes its own.
- `BlockingCollection<T>` — producer/consumer with bounded capacity & blocking (`Add`/`Take`), built over a concurrent collection; supports cancellation.
- `Channel<T>` — modern async-first producer/consumer (unbounded/bounded, `WriteAsync`/`ReadAsync`, backpressure). The modern default.

**`ConcurrentDictionary` internals:**

- Lock-striping: internal tables partitioned by bucket hash; each stripe has its own lock (default 32-ish stripes / `Environment.ProcessorCount`-based). A read of a stripe acquires that stripe's lock briefly; writes take a stripe lock; resizing takes a bigger "grow" lock.
- `GetOrAdd(key, factory)` — note: the factory may run multiple times under contention; it's "add-once" semantics for the *stored* value, not a guarantee the factory ran once. Use `AddOrUpdate` carefully; for expensive factories, use `Lazy<T>` or `GetOrAdd` + idempotent factory.

**Atomic vs compound:**

- `TryGetValue`/`TryUpdate` are atomic individually.
- "Check then add" or "read value, modify, write back" are NOT atomic — use `AddOrUpdate`/`TryUpdate` (which use interlocked compare-and-swap semantics) or lock externally.
- Iteration over `ConcurrentDictionary` gives a *snapshot* (safe).

**Frozen/immutable for concurrency:**

- `ImmutableDictionary` — persistent; every mutation creates a new instance sharing structure; readers never see partial state. Use when you want lock-free reads with occasional snapshots, e.g., configuration caches.

### Real World Example (Healthcare)

```csharp
// Shared real-time vitals cache across hub connections
private readonly ConcurrentDictionary<string, VitalsSnapshot> _liveVitals = new();

public void UpdateVitals(string patientId, VitalsSnapshot v)
    => _liveVitals.AddOrUpdate(patientId, v, (_, _) => v);

public bool TryGetVitals(string patientId, out VitalsSnapshot v)
    => _liveVitals.TryGetValue(patientId, out v);
```

### Production Code Example

```csharp
public sealed class RateBucketStore
{
    private readonly ConcurrentDictionary<string, RateBucket> _buckets = new(StringComparer.Ordinal);

    // Atomic increment of a per-key counter (compound op → must be atomic)
    public long Increment(string key)
    {
        var bucket = _buckets.GetOrAdd(key, _ => new RateBucket());
        return Interlocked.Increment(ref bucket.Value);   // atomic
    }

    // Atomic replace of a whole snapshot
    public void Replace(string key, RateBucket newBucket)
        => _buckets.TryUpdate(key, newBucket, ComparisonComparer: null);
}

public sealed class RateBucket
{
    public long Value;         // mutated via Interlocked only
}

// Modern producer/consumer — Channel
public sealed class AlertPipeline
{
    private readonly Channel<ClinicalAlert> _channel =
        Channel.CreateBounded<ClinicalAlert>(new BoundedChannelOptions(1000)
        {
            FullMode = BoundedChannelFullMode.Wait,       // backpressure
            SingleReader = true
        });

    public ValueTask PublishAsync(ClinicalAlert alert, CancellationToken ct)
        => _channel.Writer.WriteAsync(alert, ct);

    public IAsyncEnumerable<ClinicalAlert> ReadAllAsync(CancellationToken ct)
        => _channel.Reader.ReadAllAsync(ct);
}
```

**Key lines explained:**

- `GetOrAdd` + `Interlocked.Increment` — the counter is compound and must be atomic.
- `TryUpdate` with comparison — compare-and-swap style replace.
- `Channel.CreateBounded` with `Wait` mode — backpressure: the writer waits when the buffer is full (no unbounded memory growth).
- `ReadAllAsync` — async consumption without blocking threads.

### Advantages

- Thread-safe, scalable reads, atomic single ops; no manual locking; `Channel` gives backpressure.

### Disadvantages

- Compound operations need care; `ConcurrentDictionary` is heavier than `Dictionary`; ordering guarantees limited; debugging harder.

### Best Practices

- Choose the right collection for the concurrency shape (dict, queue, bag, channel).
- Use `GetOrAdd`/`AddOrUpdate`/`TryUpdate` instead of check-then-act.
- For pipelines: `Channel<T>` (async-first, bounded, backpressure).
- Prefer `BlockingCollection` only for classic blocking producer/consumer.

### Common Mistakes

- Compound read-modify-write without atomicity → lost updates.
- Using `ConcurrentBag` where order matters (it's unordered).
- `GetOrAdd` factory running more than once (side-effecting factory).
- Locking externally on a concurrent collection (double protection, deadlock risk).

### Interview Follow-up Questions

1. How does `ConcurrentDictionary` achieve scalability? (Lock striping; per-stripe locks.)
2. Is `GetOrAdd`'s factory guaranteed to run once? (No — the *stored value* is added once, but the factory may run multiple times.)
3. What is `Channel<T>` and why prefer it over `BlockingCollection<T>`? (Async-first, backpressure, bounded.)
4. `ConcurrentBag` vs `ConcurrentQueue`? (Bag = unordered thread-local; Queue = FIFO.)
5. Are concurrent collections free of all locking? (No — internal locks, mostly fine-grained.)

### Senior Level Talking Points

> "Concurrency collection choice is a *data-shape* decision: a shared live-vitals cache is `ConcurrentDictionary`; an ingest pipeline is `Channel` with bounded backpressure; a distributed queue is none of these (that's Redis/RabbitMQ). The senior line on `GetOrAdd`: the factory is an *idempotent* hint, not a mutex — if it's expensive or side-effecting, you wrap it in `Lazy<T>` or use `AddOrUpdate` with your own lock. And I always audit compound operations, because 'thread-safe collection' lulls people into writing non-atomic read-modify-write code."

### Diagram

```
ConcurrentDictionary:  lock striping
 tables:  [stripe0][stripe1][stripe2]...     # ~32 stripes, each own lock
 Concurrent reads/writes hit their stripe's lock only — scales with stripes

Channel<T>:  Producer ──WriteAsync──► [ bounded buffer ] ──ReadAllAsync──► Consumer
                │                          │ full? Wait (backpressure)
```

### Memory Trick

**"Concurrent collections lock the strip, not the whole highway."**

---

## 5.7 Immutable Collections

### Interview Answer (30–45 seconds)

> "Immutable collections (`ImmutableList`, `ImmutableDictionary`, `ImmutableHashSet`, `ImmutableArray`) never mutate — every modification returns a *new* collection that shares unchanged nodes with the old one (structural sharing). They're thread-safe by construction (no locks needed for readers; writers get new instances) and give snapshot semantics for free. The costs: each update allocates a node-path and is slower than mutating a `List`/`Dictionary`, and they're often overkill. I use them for configuration snapshots, event-sourced state, and cross-thread immutable references — and I choose `ImmutableArray` for the rare 'struct-like value snapshot' case and `FrozenDictionary` (read-only, not immutable) when it's read-only but built once."

### Detailed Explanation

- **Structural sharing:** a red-black tree / AVL-like tree for `ImmutableSortedDictionary`, a hash-array-mapped-trie (HAMT) for `ImmutableDictionary`/`ImmutableHashSet` — updating creates new nodes along the path to the root, sharing the rest.
- **Semantics:** `dict = dict.Add(k, v)` — returns a new instance; the old `dict` reference is unchanged (snapshot).
- **Thread-safety:** immutable ⇒ readers see a consistent state; writers coordinate by creating new versions (usually guarded by a lock or `Volatile` reference swap).
- **`ImmutableArray<T>`** — wraps a real array; value-type box; `==` compares arrays by reference; serialization-friendly; good for static snapshots. Mutating via `.Add` copies (O(n)).
- **`FrozenDictionary`/`FrozenSet`** (.NET 8): *read-only*, built once — not immutable-persistent, but optimized for reads (fast, memory-light). If you never need to modify after build, `Frozen` beats `Immutable` for perf.

**Pattern — atomic reference swap:**

```csharp
public sealed class ConfigStore
{
    private ImmutableDictionary<string, string> _cfg = ImmutableDictionary<string, string>.Empty;

    public string? Get(string key) => _cfg.GetValueOrDefault(key);   // lock-free read

    public void Update(IEnumerable<(string, string)> changes)
    {
        // writers build a new version, then swap atomically
        ImmutableInterlocked.Update(ref _cfg,
            cfg => changes.Aggregate(cfg, (c, kv) => c.SetItem(kv.Item1, kv.Item2)));
    }
}
```

### Real World Example (Healthcare)

```csharp
// Feature-flag/consent snapshots shared across request threads
public sealed class ConsentRegistry
{
    private volatile ImmutableDictionary<Guid, Consent> _consents = ImmutableDictionary<Guid, Consent>.Empty;

    public Consent? Get(Guid patientId) => _consents.GetValueOrDefault(patientId);

    public void Grant(Guid patientId, Consent consent)
    {
        ImmutableInterlocked.AddOrUpdate(ref _consents, patientId, consent, (_, _) => consent);
    }
}
```

**Key lines explained:**

- `volatile` reference + immutable instances → readers never see torn state.
- `ImmutableInterlocked` — atomic swap helpers.

### Advantages / Disadvantages

| | Immutable | Mutable |
|---|---|---|
| Thread-safety | by construction | needs locks |
| Snapshot | free | manual copy |
| Update cost | node-path alloc | direct |
| Memory | shares structure | tightest |
| Best for | shared config, events, snapshots | hot mutable state |

### Best Practices

- Use immutables where state is *shared and versioned*.
- Prefer `Frozen` collections for read-only-after-build tables (.NET 8).
- Use `ImmutableInterlocked` for atomic swaps.
- Don't use immutables as a blanket replacement for `List` in hot single-threaded code.

### Common Mistakes

- Forgetting that `Add` returns a new instance (discarding the return → no change).
- Using immutables where `Frozen` (read-only) is the better fit.
- Serialization surprises with `ImmutableArray` (reference equality).
- Believing immutable collections are lock-free-cheap for writes (they're not).

### Interview Follow-up Questions

1. What is structural sharing? (Shared unchanged nodes between versions.)
2. `ImmutableDictionary` vs `FrozenDictionary`? (Persistent-immutable vs read-only optimized.)
3. When do you use `ImmutableInterlocked`? (Atomic swaps under concurrency.)
4. Why is `ImmutableArray` a struct? (Value-type box over an array for snapshots.)

### Senior Level Talking Points

> "Immutable collections are the *snapshot* answer to concurrent reads: swap a new version and readers never block or tear. The senior nuance is picking the right tool — `FrozenDictionary` when it's built once and read forever, `ImmutableDictionary` when versions change, and plain `ConcurrentDictionary` when the same key is hot-updated. In a healthcare platform, consent flags and feature config are classic immutable-snapshot cases: you want every request to see a *consistent* consent set, and a lock-free swap delivers that."

### Memory Trick

**"Immutable = every edit is a new photo album that shares the old pages."**

---

## Chapter 5 Wrap-Up

### Top 10 Interview Questions From This Chapter

1. How do you choose between `List<T>`, `Dictionary`, and `HashSet`?
2. How does `List<T>` grow internally? Why pre-size?
3. Explain `Dictionary` internals: buckets, chaining, resize.
4. Why must `GetHashCode` be stable and consistent with `Equals`?
5. `IReadOnlyList<T>` vs `IList<T>` — what should you expose?
6. `HashSet` vs `SortedSet` — when each?
7. `Queue`/`Stack`/`LinkedList` — backing structures and when to use.
8. How does `ConcurrentDictionary` achieve thread safety and scalability?
9. Is `GetOrAdd`'s factory guaranteed to run once?
10. Immutable vs Frozen vs Concurrent collections — how do you pick?

### Revision Notes (1 page)

- **Choice by access pattern:** index → List/array; key → Dictionary; membership → HashSet; FIFO → Queue; LIFO → Stack; ordered → SortedSet/SortedDictionary; thread-shared dict → ConcurrentDictionary; pipeline → Channel.
- **List growth:** doubles capacity (4→8→16…); growth copies O(n); amortized O(1) adds; pre-size to avoid storms.
- **Dictionary:** hash→bucket, chaining via entries; O(1) avg; resizes ~0.72 load factor (rehash O(n)); keys must be immutable + consistent hash; use TryGetValue; FrozenDictionary for static read-only (.NET 8).
- **Interfaces:** expose IReadOnlyList/IEnumerable; keep concrete mutable types internal; arrays for fixed/perf.
- **Sets:** HashSet O(1) membership + dedupe via Add-bool; SortedSet red-black, ordered, GetViewBetween.
- **Queue/Stack/LinkedList:** circular array / array+top / doubly-linked; LinkedList rarely worth it.
- **Concurrent:** ConcurrentDictionary (lock striping), GetOrAdd/AddOrUpdate/TryUpdate for compound ops; Channel for producer/consumer with backpressure; BlockingCollection legacy-ish.
- **Immutable:** structural sharing snapshots; ImmutableInterlocked swaps; Frozen for read-only-after-build; not a blanket replacement.

### Things Interviewers Expect From 5+ Years Experience

- Collection choice tied to *access patterns and concurrency* — not just vocabulary.
- Understanding of internal mechanics (buckets, growth, resizing) to justify decisions.
- The discipline of exposing read-only interfaces at boundaries.
- Compound-operation awareness with concurrent collections (atomic ops ≠ atomic sequences).
- Modern .NET knowledge: `FrozenDictionary`, `Channel<T>`, `CollectionsMarshal`.

### Cheat Sheet

```
Index access        → List<T> / T[]
Key lookup          → Dictionary<K,V> (TryGetValue; stable hash keys)
Membership          → HashSet<T> (Add-bool dedupe)
FIFO                → Queue<T> / ConcurrentQueue<T>
LIFO                → Stack<T> / ConcurrentStack<T>
Ordered             → SortedSet<T> / SortedDictionary<K,V>
Concurrent dict     → ConcurrentDictionary (GetOrAdd/AddOrUpdate/TryUpdate)
Producer/consumer   → Channel<T> (bounded, backpressure)
Snapshot sharing    → ImmutableDictionary / ImmutableInterlocked
Read-only table     → FrozenDictionary (build once, read forever) — .NET 8
Expose outward      → IReadOnlyList<T> / IEnumerable<T>

List<T> growth:  doubles; pre-size; TrimExcess
Dictionary:      hash→bucket→chain; resize ~72% load; unordered iteration
Never:           mutable keys; ContainsKey+[] double lookup; rely on dict order
```

### Flash Cards

**Q1:** List growth strategy? **A:** Doubles capacity (O(n) copy), amortized O(1) adds.

**Q2:** Dictionary collision resolution? **A:** Chaining — entries linked per bucket; Equals verifies.

**Q3:** When does Dictionary resize? **A:** ~0.72 load factor; O(n) rehash.

**Q4:** IReadOnlyList immutable? **A:** No — the reference contract is read-only; cast defeats it.

**Q5:** HashSet vs SortedSet? **A:** O(1) membership vs O(log n) ordered.

**Q6:** LinkedList O(1) insert requires? **A:** You already hold the node; otherwise O(n) to find it.

**Q7:** ConcurrentDictionary internals? **A:** Lock striping — per-stripe locks, not one global lock.

**Q8:** GetOrAdd factory runs how often? **A:** May run multiple times under contention; value added once.

**Q9:** Channel for? **A:** Async producer/consumer with bounded buffer + backpressure.

**Q10:** FrozenDictionary vs Immutable? **A:** Frozen = read-only optimized build-once; Immutable = persistent snapshots.

### Interview Confidence Score

**Medium.** Collection internals are a classic mid/senior gate. The senior signals: pre-sizing, boundary exposure discipline, concurrency semantics (compound ops), and knowing modern types (`Frozen`, `Channel`).

---

*Continue → Chapter 6: Memory Management & Garbage Collection*
