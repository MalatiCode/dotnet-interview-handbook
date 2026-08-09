# Chapter 1: C# Fundamentals

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** Value vs. reference types, stack vs. heap, boxing, strings, equality, `ref`/`out`/`in`, `const` vs. `readonly`, nullable types, exceptions, and the modern type system in .NET 8+.

---

## 1.1 Value Types vs. Reference Types

### Interview Answer (30–45 seconds)

> "Value types, like `int`, `struct` and `enum`, store their data directly where the variable is declared — on the stack when they're locals, and inline within their parent object on the heap. Reference types, like `class`, `string` and `array`, hold a pointer to a heap-allocated object. The practical consequences: when you copy a value type you copy the data; when you copy a reference type you copy the pointer, so both variables point at the same object. Assignment semantics, equality behavior, nullability, and GC pressure all flow from that one distinction. I choose a struct when the type represents a small, immutable data value like a coordinate or a FHIR `Coding` primitive; otherwise I default to a class."

### Detailed Explanation

The single most important concept in C# — nearly every "gotcha" question in an interview traces back to this one distinction.

**Where the data lives (the mental model):**

- **Stack:** Each thread gets its own stack. Locals of value types live here, allocated at the call frame, freed when the method returns. Allocation is a simple pointer bump — extremely cheap. No GC involvement.
- **Heap:** All objects (reference types) live on the GC-managed heap. So do value types that are *boxed*, or that are fields *inside* a reference type (the value is embedded inline inside the object). Locals of reference types live on the stack but hold only a *reference* (an object header pointer) to the heap object.

**Why this matters:**

| Operation | Value type | Reference type |
|---|---|---|
| Assignment | Copies the value | Copies the reference (same object) |
| Equality | Structural (compares bits / memberwise) | Reference by default, unless overridden |
| Nullable | Only via `Nullable<T>` (`int?`) | Always nullable |
| Method param | Passed by value (a copy) | Passed by value (a copy of the *pointer*) |
| GC pressure | None when on stack | Yes, when the object is collected |

**The "passed by value" trap:** Everything in C# is passed by value — even references. The *value* of a reference-type argument is the reference itself. So:

```csharp
void ClearList(List<int> list) => list.Clear();  // mutates the caller's list
void Reassign(List<int> list) => list = new();   // caller sees NO change
```

The method can mutate the object the caller points at, but cannot make the caller's variable point at a *different* object — unless you use `ref`.

**Why, not just what:** The CLR makes this distinction because of performance and memory-safety tradeoffs. Stack allocation is O(1) and cache-friendly; heap allocation requires GC tracking. Value types give you deterministic lifetime and zero GC overhead, but lose polymorphism and inheritance. Reference types give you inheritance, shared identity, and polymorphism, at the cost of GC pressure and indirection.

**When to choose which:** Eric Lippert's rules of thumb: a struct should be small (≤16–24 bytes), immutable-ish, logically a *single value*, and not require identity semantics. `DateTime`, `TimeSpan`, `Guid`, `decimal` are the classic examples. Everything else: a class.

### Real World Example (Healthcare)

A FHIR resource like `Observation` is large, mutable, polymorphic, and carries identity — a class. But the `Quantity` inside it (`{ value: 120, unit: "mg/dL", system: "http://unitsofmeasure.org" }`) is a small immutable value: a struct is appropriate.

```csharp
public readonly struct Quantity
{
    public decimal Value { get; }
    public string Unit { get; }
    public string System { get; }

    public Quantity(decimal value, string unit, string system)
    {
        Value = value;
        Unit = unit;
        System = system;
    }
}
```

Now storing a million lab results as `Quantity[]` avoids a million heap allocations.

### Production Code Example

```csharp
// A mixed scenario: struct embedded in class
public readonly struct LabRange
{
    public decimal Low { get; }
    public decimal High { get; }
    public LabRange(decimal low, decimal high) { Low = low; High = high; }
    public bool IsInRange(decimal v) => v >= Low && v <= High;
}

public sealed class LabTestResult   // reference type: identity, mutation, GC
{
    public Guid Id { get; } = Guid.NewGuid();
    public required string TestCode { get; init; }  // e.g., "GLU" for glucose
    public LabRange ReferenceRange { get; init; }   // struct stored INLINE inside this heap object
    public bool IsAbnormal(decimal value) => !ReferenceRange.IsInRange(value);
}
```

**Key lines explained:**

- `readonly struct` → the compiler enforces immutability; copies cannot be corrupted; enables `in` parameters and defensive-copy avoidance.
- `public LabRange ReferenceRange { get; init; }` → the struct is embedded directly inside the heap-allocated `LabTestResult` object. Accessing `ReferenceRange.Low` requires no pointer dereference — the bytes are physically adjacent (good for cache locality).
- `required` and `init` (C# 11/9) → object initializer enforcement and post-construction immutability.

### Internal Working

1. Compiler emits different IL: `ldloc`/`stloc` for value-type locals vs. `newobj` + `dup` + reference handling for reference types.
2. For a value type stored in an array (`int[]`), the CLR stores the *elements themselves* contiguously — `int[]` of 1M elements is 4 MB flat. For an `object[]`, each slot is a pointer and each element is a separate heap object.
3. The JIT chooses to "promote" small structs into registers; large structs get spilled.
4. Stack size per thread is ~1 MB by default — you cannot put huge structs on the stack (`StackOverflowException` risk).

### Advantages

- Value types: no GC pressure, cache-friendly, deterministic lifetime, no null-checking needed (unless nullable).
- Reference types: inheritance, polymorphism, shared identity, uniform null handling, `IDisposable` semantics.

### Disadvantages

- Value types: no inheritance (can't derive from a struct), boxing when cast to `object`/interface, copies can hide bugs, large structs hurt performance when passed around.
- Reference types: GC cost, indirection, null-reference hazards, aliasing surprises.

### Best Practices

- Default to `class`; reach for `struct` only for small, immutable, single-value types.
- Use `readonly struct` and `ref struct` consciously (`Span<T>` is a `ref struct`).
- Never return a struct as an interface or `object` — it forces boxing.
- Use `in` parameters for large structs you don't mutate; use `ref readonly` for returned references to avoid copies.

### Common Mistakes

- Assuming a struct parameter is mutated by the callee — it's a copy.
- Comparing structs with `==` expecting deep comparison but it's not implemented → compile error, or bitwise comparison surprises with floats.
- Storing structs in `List<object>` → hidden boxing on every add/read.
- `default(SomeStruct)` is a *valid* value — forget that `default` ≠ null and use it accidentally in equality checks.

### Interview Follow-up Questions

1. What happens when you assign one value type variable to another? (Deep copy — confirm with two independent variables.)
2. What is `Nullable<T>` and how is it a struct?
3. Can a struct implement an interface? What happens when you call the interface method? (Boxing — virtual dispatch via interface requires boxing.)
4. Why is `DateTime` a struct? Why is `string` a class?
5. What is a `ref struct`? Why can't it be boxed or used in async methods?

### Senior Level Talking Points

> "In a healthcare API handling high-throughput lab-result ingestion, I measured that boxing during JSON deserialization and dictionary lookups caused measurable gen-0 GC pressure. Using `readonly struct`s for small value payloads and `Span<T>` for buffer parsing cut allocations significantly. But I'd also stress that premature struct-ification is a real risk — the memory layout and copy semantics make them harder to reason about, so I benchmark with BenchmarkDotNet before and after."

### Diagram

```
THREAD STACK                        GC MANAGED HEAP
┌─────────────────────────┐
│  int x = 42   ── 42 ────┼── stored directly          ┌───────────────────────────┐
│  Person p    ── 0x…20 ─┼── pointer ────────────────► │ [sync block | method table]│
│  Point pt    ── {3,7} ──┼── struct stored directly   │  Name = "Ana"             │
└─────────────────────────┘                             │  Age  = 34                │
                                                        └───────────────────────────┘
```

---

## 1.2 Stack vs. Heap

### Interview Answer (30–45 seconds)

> "The stack is a per-thread LIFO region used for method frames, local value types, and references; it's fast because allocation is just moving a stack pointer, and it self-cleans when methods return. The heap is a shared, GC-managed region for objects; allocation requires finding space and triggering the garbage collector, and deallocation is non-deterministic. In .NET, managed code doesn't let you choose explicitly — the runtime decides. The interview-level insight is understanding which data ends up where, why stack allocation is cheap, and how this drives design decisions like struct vs. class and why async avoids blocking threads."

### Detailed Explanation

**Stack mechanics:**

- One stack per thread; grows downward on most platforms.
- A method call pushes a *frame*: return address, parameters, saved registers, local slots.
- Allocation of a local = adjusting the stack pointer. No locking, no GC scan, no fragmentation.
- When a method returns, the frame is popped — everything it owned is gone, instantly.

**Heap mechanics:**

- Shared across threads; managed by the GC in generations (Gen 0/1/2 — see Chapter 6).
- Allocation: on Gen-0 the GC uses a "bump pointer" into a contiguous segment — actually fast — but segments fill up and trigger GC, promotion, and compaction.
- Deallocation: non-deterministic — the GC decides when. Finalizers complicate this further.

**Stack overflow:** each thread stack is fixed (~1 MB default, can be raised with `Thread` settings / `.config`). Deep recursion or a huge stack-allocated `Span`/`stackalloc` blows it → `StackOverflowException`, which is *not catchable* in .NET Core/.NET 5+ (the process dies — deliberate design).

**Heap fragmentation:** compaction in Gen 0/1 and the large object heap (LOH, ≥85 KB) being un-compacted by default. Pinning objects (during interop or `fixed`) prevents compaction, creating holes.

**Why do interviewers care?** Because the question "where does the memory live?" surfaces whether a candidate can reason about GC pressure, boxing, closures (captured locals get lifted to the heap!), and `async` state machines (also heap-allocated).

### Real World Example (Healthcare)

Serializing 50,000 FHIR `Observation` resources to JSON and back. Each `Dictionary<string,object>` boxed value, each string concat in a loop, each closure created per-iteration, inflates Gen-0 collections. The senior response: "the hot path should be structs + `Span<byte>` + pooled buffers (via `ArrayPool<T>`) so we keep GC out of the loop."

### Production Code Example

```csharp
public static int Sum(ReadOnlySpan<int> values)
{
    int total = 0;
    foreach (var v in values) total += v;
    return total;
}

// Callers can pass stack-allocated or heap-allocated data:
Span<int> onStack = stackalloc int[512];          // NO heap allocation
int[] onHeap = Enumerable.Range(1, 100_000).ToArray();

int a = Sum(onStack);   // stack memory, zero allocation
int b = Sum(onHeap);    // reads heap array, zero allocation
```

**Key lines explained:**

- `ReadOnlySpan<int>` is a `ref struct` — it can point at *either* stack or heap memory safely, with no copy.
- `stackalloc` places the buffer on the thread stack; it dies when the method returns.
- The same `Sum` function works on both without allocating.

### Internal Working

1. JIT emits the method prologue to `sub rsp, frameSize` (stack) vs. `call JIT_New` (heap).
2. Heap objects carry a sync block index + method table pointer; the GC walks object graphs from roots (stack, static fields, CPU registers) during collection.
3. A captured local (closure) is a compiler-generated class field → it *moves* from stack to heap the moment a lambda references it.

### Advantages / Disadvantages

| Region | Advantages | Disadvantages |
|---|---|---|
| Stack | O(1) alloc, no GC, cache-hot, deterministic teardown | Tiny, per-thread, frame-local lifetime |
| Heap | Arbitrary size, shared, object can outlive method | GC cost, fragmentation, non-deterministic teardown |

### Best Practices

- Keep recursion depth bounded; prefer iterative loops for unbounded depth.
- Use `stackalloc`/`Span<T>` for transient buffers in hot loops.
- Don't create closures per iteration in hot paths — hoist them.
- Pool large arrays (>85 KB → LOH) with `ArrayPool<T>`.

### Common Mistakes

- Deep recursion causing un-catchable `StackOverflowException`.
- Allocating large temporary arrays per request in an API (LOH churn).
- Treating heap allocation as free — no, it drives GC cost.

### Interview Follow-up Questions

1. Can a value type live on the heap? (Yes — boxed, or a field of a class, or in a closure.)
2. What happens when the stack overflows in .NET? (Process terminates; not catchable.)
3. What is the Large Object Heap and why is it special? (≥85 KB, Gen 2, no compaction by default.)
4. How does `async` affect the stack? (The state machine and captured locals go to the heap.)

### Senior Level Talking Points

> "I don't think in terms of 'stack vs heap' as a choice in managed code — the runtime owns that. What I actually reason about is *allocation rate*: how many bytes per request we allocate, because that drives GC frequency, which drives latency spikes at the 99th percentile. In our lab-orders pipeline I profile with PerfView and dotnet-counters and watch `gen-0-collections`, not just CPU."

### Diagram

```
Method A frame
├── local int x
├── ref  ─────────────►  Heap: Patient object
├── Span<T> (ref struct)
│                        GC generations:
Method B frame            Gen0 ▸ Gen1 ▸ Gen2 (oldest, most expensive)
└── local decimal y
                          LOH (>=85KB arrays) — Gen2, no compact
```

### Memory Trick

**"Values are their data; references are an address."** If copying a variable should copy the whole thing → value type. If copying a variable should copy a pointer to one shared thing → reference type.

---

## 1.3 Boxing and Unboxing

### Interview Answer (30–45 seconds)

> "Boxing is the implicit conversion of a value type to `object` or to an interface it implements — the CLR wraps the value in a heap-allocated object, which is exactly where the name comes from. Unboxing extracts the value back, which is a checked cast. Boxing allocates and copies, so it's expensive: it generates Gen-0 garbage and can spike GC pressure in hot paths. Modern C# avoids most of it via generics — a `List<int>` is unboxed, whereas an `ArrayList` boxed every element. I look for accidental boxing in hot paths, typically via `object` parameters, non-generic collections, string interpolation of structs, and `enum.ToString()`."

### Detailed Explanation

**The boxed object layout:** When `int i = 42; object o = i;` runs:

1. The CLR allocates an object on the heap (sync block + method table for `System.Int32`).
2. It copies the *value* (42) into that object's data fields.
3. The stack variable `o` now references the heap object.

**Unboxing:** `int j = (int)o;` performs a type check against the method table, then copies the bits back to the stack. If `o` isn't actually an `Int32`, `InvalidCastException` is thrown at the *cast* — a design choice for type safety (unlike `unbox.any` in IL which can also return the address).

**Costs:**

- Allocation (GC pressure) + copy of value.
- Cache miss / indirection.
- A `finally`-like teardown is *not* needed, but the box is garbage.

**Where accidental boxing sneaks in:**

- `object` method parameters, e.g., old-style `String.Format` / `Console.WriteLine("{0}", value)`.
- Non-generic collections: `ArrayList`, `Hashtable`, `DataSet`/`DataTable` (the classic healthcare legacy offender).
- Calling `ToString()`, `GetHashCode()`, `Equals()` on a value type when called *through* an interface or `object` reference.
- `enum` methods — `DayOfWeek.Monday.ToString()` boxes.
- String interpolation `$"{number}"` is actually safe in modern .NET (uses `ISpanFormattable`/`DefaultInterpolatedStringHandler`, no boxing). Good senior talking point.
- Passing a struct to a generic method whose type parameter is an interface-constrained or `object`-constrained parameter.

**Generic collections eliminated the systemic case.** `List<int>` stores an `int[]` internally — the elements are contiguous value types. `ArrayList` stores `object[]` — boxing on every add. This is *the* historical performance bug interviewers love.

### Real World Example (Healthcare)

A legacy healthcare app using `DataSet`/`DataTable` to move lab results. Each `DataRow` access via `row["GLU"]` returns `object` → every decimal value boxed, every read unboxed. Migrating the read path to typed records + `List<LabValue>` cut a batch job's time from 40 minutes to 6 and dramatically reduced GC pauses. (See `#if NET5_0`... no, see BenchmarkDotNet before/after.)

### Production Code Example

```csharp
// BAD — boxing everywhere
object[] ages = new object[] { 34, 41, 29 };      // 3 boxes on the heap
decimal total = 0;
foreach (object a in ages) total += (decimal)a;   // unbox per iteration

// GOOD — generic, zero boxing
decimal[] ages2 = { 34m, 41m, 29m };              // flat, no objects
decimal sum = 0;
foreach (decimal a in ages2) sum += a;

// GOOD — enum without boxing (generic helper)
public static string Describe<TEnum>(TEnum value) where TEnum : struct, Enum
    => value.ToString();                          // generic, no box
```

**Key lines explained:**

- `object[]` forces boxing on write and unboxing on read.
- `decimal[]` stores values contiguously — `foreach (decimal a ...)` iterates with zero boxing because `foreach` over an array uses `get_Item`/indexer, not the `IEnumerator` interface.

### Internal Working

IL ops: `box` allocates and copies; `unbox.any` checks type + copies. JIT inlines both for known types but the allocation remains. In .NET 8 the JIT can sometimes devirtualize and eliminate boxing (aggressive inlining + "boxing elimination"), but you should not rely on it in hot paths.

### Advantages

- Lets value types participate in polymorphism (`object`/interfaces), enable generic eras... no — allows non-generic APIs to handle all types, and is how `Nullable<T>` boxing works (`int?` boxes to a boxed `int` if has value, or `null`).

### Disadvantages

- Allocation + copy + GC pressure; extra indirection; cache-unfriendly; can hide in loops.

### Best Practices

- Prefer generics over `object` for reusable code.
- Avoid `ArrayList`, `Hashtable`, `DataTable` on hot paths.
- Avoid `enum.ToString()` in loops; cache strings or use generic helpers.
- Watch `Expression` trees — they force boxing of captured value types sometimes (that's a deeper topic).

### Common Mistakes

- `foreach (object o in listOfStructs)` — boxes on each iteration.
- Casting through `object` "just to be safe" in a hot path.
- Confusing `int?` boxing semantics (a `null` `int?` boxes to `null`, not a boxed `null`).

### Interview Follow-up Questions

1. When does an `int?` box? What does a `null` `int?` box to?
2. Does string interpolation box in .NET 8? (No — `DefaultInterpolatedStringHandler`.)
3. How did generics solve boxing? Explain `List<T>` vs `ArrayList`.
4. What's the boxing status of `struct` implementing `IEquatable<T>` when used in a `HashSet<T>`? (No boxing — the generic interface is implemented on the struct.)

### Senior Level Talking Points

> "Boxing is the poster child for 'correct but slow.' The senior approach isn't to eliminate it everywhere — it's to *measure* with BenchmarkDotNet or dotnet-counters, find the hot path, and only then restructure. In healthcare batch processing, a single hidden boxing in an O(n²) nested loop over millions of records is the difference between an SLA met and an SLA missed."

### Diagram

```
Stack                    Heap
┌────────────┐
│ int i = 42 │
└─────┬──────┘   box     ┌──────────────────────────┐
      │ ─────────────────►│ [sync|Int32 tbl| 42]    │  ← boxed object
┌────────────┐            └──────────────────────────┘
│ object o   │── pointer──┘
└────────────┘
```

### Comparison Table: `int` in `List<int>` vs `ArrayList`

| Aspect | `List<int>` | `ArrayList` |
|---|---|---|
| Storage | `int[]` (contiguous) | `object[]` (pointer array) |
| Add | no allocation, copy value | box + allocate |
| Read | no allocation | unbox + copy |
| GC pressure | none | per element |
| Type safety | compile-time | runtime cast |
| Modern usage | **use this** | legacy only |

### Memory Trick

**"Box = wrap a value in a shipping crate; it costs you a crate (heap object) every time."**

---

## 1.4 Strings: Immutability, `string` vs `StringBuilder`, Interning

### Interview Answer (30–45 seconds)

> "`string` is an immutable reference type — every operation that 'changes' it produces a new instance, which is why a loop of concatenations is O(n²) and creates a mountain of garbage. `StringBuilder` maintains a mutable char buffer and amortizes to roughly O(n), so it's the right tool for building strings in a loop. String interning is the CLR's optimization where equal string literals and `string.Intern` results share one instance via an intern pool, so reference equality can be used for content equality — `StringComparer.Ordinal` on interned identifiers. I default to `string` unless I'm composing strings repeatedly; and I use `StringBuilder`/`DefaultInterpolatedStringHandler` (which is literally what `$""` compiles to) for hot paths."

### Detailed Explanation

**Immutability semantics:** `string s = "hi"; s += "!";` — the `+=` produces a brand-new string `"hi!"`; the old `"hi"` becomes garbage (unless interned). Because strings are immutable, they're safe to share across threads and can be reused as dictionary keys safely.

**Why immutability is *good*:**

- Thread-safety for free (no one can corrupt the shared string).
- Safe as hash keys — the hash never changes.
- Reference equality optimization possible (interning).
- Security: a substring view can't be mutated to corrupt an audit log.

**The performance landmine:** `s = s + "x"` in a loop of N iterations is O(n²) — each concat allocates a new string of growing length and copies the whole thing. `StringBuilder` uses an expandable `char[]` buffer → amortized O(n).

**StringBuilder internals:** holds `char[] _chars`, tracks `_length`. `Append` writes into the buffer, doubling capacity when full. `ToString()` snapshots the buffer. Note: calling `.ToString()` repeatedly copies — in .NET 7+, `GetChunks()` lets you enumerate the internal chunks without copying; `ChunkEnumerator` exposes the backing buffer.

**Interning:** The CLR maintains a `HashSet<string>`-like intern pool of string instances. Two identical *literals* compile to reference the *same* interned instance. `string.Intern(s)` forces a string into the pool. Interning lets `ReferenceEquals(a,b)` imply content equality. Pitfalls: interned strings are never collected (they live for the process lifetime) → memory leak if you intern user input indiscriminately. Do NOT intern runtime data.

**Modern guidance (performance) for .NET 8:**

- `$"{a} {b}"` compiles to a `DefaultInterpolatedStringHandler` — writes into a pooled `ArrayBufferWriter`-backed char buffer, single allocation, no intermediate strings. This is *faster* than `string.Concat` in many cases and definitely better than `+` in loops... except in a *loop* you still want `StringBuilder` because the handler is per-statement.
- For very hot string building: `StringBuilder` with a pre-sized capacity, or `string.Create<TState>(...)` with a span-based fill.

### Real World Example (Healthcare)

Building a 100,000-row HL7 message export. With `+` concatenation each row rebuilds the entire message → minutes of runtime and GB of garbage. With a single `StringBuilder` with pre-sized capacity, it's milliseconds. Also: FHIR canonical URLs and LOINC/SNOMED codes are perfect interning candidates in a *bounded* context (known code system), NOT user-entered text.

### Production Code Example

```csharp
// Production-grade: building a large HL7 ORU^R01 message
public string BuildHl7Message(IEnumerable<Observation> observations, int estimatedSize)
{
    var sb = new StringBuilder(estimatedSize);   // pre-size to avoid reallocs

    sb.Append("MSH|^~\\&|LIS|HOSP|EMR|HOSP|");
    sb.Append(DateTime.Now.ToString("yyyyMMddHHmmss"));
    sb.Append("||ORU^R01|").Append(Guid.NewGuid().ToString("N")).Append("|P|2.5.1|\r");

    foreach (var obs in observations)
    {
        sb.Append("OBX|1|NM|")
          .Append(obs.TestCode)                 // e.g. "GLU"
          .Append("^").Append(obs.Name)
          .Append("||").Append(obs.Value.ToString("0.##"))
          .Append("|").Append(obs.Unit)
          .Append("|||||F|||").Append(obs.PerformedAt.ToString("yyyyMMddHHmmss"))
          .Append("\r");
    }
    return sb.ToString();
}
```

**Key lines explained:**

- Pre-sizing `estimatedSize` avoids repeated array-doubling + copies.
- Chained `.Append` returns `this` — no intermediate strings, all writes land in one buffer.
- `Guid.NewGuid().ToString("N")` — no hyphens; a stable message-control-ID.

### Internal Working

- `string` is `sealed class String : IEnumerable<char>`. A `String` object's data follows the header inline (null-terminated `char` data, contiguous).
- `string.Concat` with 2–3 args uses specialized fast paths; with more, it computes total length then `string.Create`.
- Interning happens at JIT time for literals (in the IL, `ldstr` consults the pool).
- `StringBuilder.Append(char)` writes directly; growth doubles capacity (like `List<T>`).

### Comparison Table: `string` vs `StringBuilder`

| Aspect | `string` | `StringBuilder` |
|---|---|---|
| Mutable? | No | Yes (buffer) |
| Concat loop | O(n²) allocs | amortized O(n) |
| Thread safety | Yes (immutable) | No (unless external lock) |
| Equality | content (`==` / `Equals`) | reference (no `==` override) |
| When to use | most cases | loops, big compositions |
| Memory | each op allocates | one growable buffer |

### Best Practices

- Use `$""` interpolation (it's fast in .NET 8); use `StringBuilder` when appending in a loop or unknown-sized composition.
- Use `string.Create`/`StringPool`/`ArrayPool<char>` only in proven hot paths — profile first.
- Use ordinal comparison (`StringComparer.Ordinal`) for identifiers and codes (LOINC, SNOMED, FHIR ids) — culture-sensitive comparison is slow and wrong for machine data.
- Never `string.Intern` user-supplied input (unbounded memory).

### Common Mistakes

- Concatenation inside a loop.
- Using `string.Equals(a, b, StringComparison.CurrentCulture)` for clinical codes.
- Interning dynamic data → memory leak.
- Confusing `==` on strings (content equality, overridden) with `==` on objects.

### Interview Follow-up Questions

1. Is `string` a value type? (No — reference type with value-like equality.)
2. What does `string.Intern` do and when would you (not) use it?
3. How does `$""` avoid boxing in .NET 8? (`DefaultInterpolatedStringHandler`)
4. Why is `StringBuilder` not thread-safe — and why is that OK?
5. When is `string ==` reference equality actually content equality? (When both are interned.)

### Senior Level Talking Points

> "The interview favorite is the O(n²) concatenation trap, but the senior answer is nuanced: modern `$""` interpolation is allocation-light via the interpolated string handler, so the rule 'always use StringBuilder' is outdated. The real decision is about *reuse* — do I build the same prefix per-row? Then I hoist it. I also make sure not to conflate display formatting with machine serialization; clinical codes should always use ordinal culture-insensitive comparison because a patient record with 'glu' vs 'GLU' is a patient-safety bug, not a cosmetic one."

### Diagram

```
 s = "Hi" + "!";
 "Hi" (interned, shared) ─┐
                         ├─► new heap string "Hi!"
 "!" (interned) ─────────┘

 StringBuilder
 ┌──────────┬──────────┬──────────┬───────┐
 │ 'H'│'i'│'!'│...│... │ ... grows (x2)   │
 └──────────┴──────────┴──────────┴───────┘
```

### Memory Trick

**"Strings are text with a frozen statue — any 'change' chips off a whole new statue."**

---

## 1.5 `ref`, `out`, and `in` Parameters

### Interview Answer (30–45 seconds)

> "By default C# passes arguments by value. `ref` passes a reference to the caller's variable — the callee can read and *reassign* it, affecting the caller. `out` is like `ref` but the callee *must* assign it before returning; it's for multiple return values and for the deconstruct pattern. `in` passes a read-only reference — the callee gets a reference but cannot mutate the argument; for large structs it avoids copies. In modern .NET, `ref`/`in` are mostly used for high-performance code (spans, low-alloc APIs) — I'd never use `out` for normal 'return two things'; a tuple or a result record is cleaner."

### Detailed Explanation

**Semantics table:**

| Modifier | Direction | Callee effect on caller's variable | Must assign? |
|---|---|---|---|
| (none) | by value | none | no |
| `ref` | in/out | can read & reassign | no |
| `out` | out | can read & must reassign | **yes** |
| `in` | in | can read only (no mutation) | no |

**Why they exist:** to avoid copies (pass a reference instead of copying a 64-byte struct), and to give the callee the ability to return results through the arguments — a pre-tuple pattern (`bool TryGetValue(key, out value)`).

**Compiler/runtime details:**

- `ref`/`out`/`in` are the *same* IL `ldarg`+pointer mechanism (managed pointers) — `out` differs only in compiler-enforced definite assignment. `in` uses the `IsReadOnlyAttribute` + readonly semantics with *defensive copies* when the callee calls a mutating or non-readonly member.
- **Defensive copy trap:** if you pass `int x` as `in` and the callee calls `x.ToString()` through a virtual/interface or accesses a non-readonly field, the compiler creates a *copy* to protect the caller's value → the "free" reference actually copied. This is why `readonly struct`s matter.
- `ref struct` (like `Span<T>`) can only be passed by `ref`/`in`, never boxed, never stored on the heap — that's a compile-time enforced rule.

**`ref` returns / `ref` locals:** `public ref int GetRef(...)` lets you return a reference to a field so callers can mutate it in place — used by `MemoryMarshal`, `CollectionsMarshal.GetValueRefOrAddDefault` etc. Advanced but a great senior signal.

### Real World Example (Healthcare)

`TryParse`-style APIs are everywhere in healthcare: `TryParseFhirDate("2024-03-01", out DateOnly d)`. And high-throughput HL7 field parsing uses `ReadOnlySpan<char>` + `ref`/`in` to slice fields without allocating substrings.

### Production Code Example

```csharp
// Multiple results, pre-tuple style (still common in libraries)
public static bool TryParseLabCode(string code, out string system, out string display)
{
    system = ""; display = "";
    if (string.IsNullOrWhiteSpace(code)) return false;
    system = "http://loinc.org";   // LOINC is a code system, not display
    display = code;                // placeholder
    return true;
}

// Avoid copying a big struct via `in`
public readonly struct Vitals
{
    public decimal Systolic { get; init; }
    public decimal Diastolic { get; init; }
    public decimal HeartRate { get; init; }
}

public static bool IsHypertensive(in Vitals v)
    => v.Systolic >= 130m || v.Diastolic >= 80m;   // no copy of 24-byte struct

// ref return — mutate in place (advanced)
public static ref decimal GetValueOrAddDefault(Dictionary<string, decimal> map, string key)
    => ref CollectionsMarshal.GetValueRefOrAddDefault(map, key, out bool exists);
```

**Key lines explained:**

- `out string system` — definite assignment: compiler guarantees `system` is assigned on every path before return.
- `in Vitals v` — reference passed, no 24-byte copy per call; safe because `Vitals` is `readonly struct` (no defensive copies).
- `ref` return via `CollectionsMarshal` — avoids a dictionary lookup+insert on the hot add path.

### Internal Working

At the IL level `ref`/`out`/`in` pass a **managed pointer** (`T&`). Managed pointers are GC-tracked addresses — the GC can move the object and update the pointer. This is what enables zero-copy mutation of heap array elements via `ref`.

### Advantages / Disadvantages

| Aspect | Advantage | Disadvantage |
|---|---|---|
| `ref` | mutate caller's variable, avoid copies | aliasing — caller's variable can be changed; more coupling |
| `out` | multiple returns, Try-pattern | ceremony; must assign; hides intent vs tuple |
| `in` | zero-copy reads of big structs | defensive copy surprise; only safe with `readonly struct` |

### Best Practices

- Default to value semantics; reach for `ref` only with a measured perf need.
- Prefer tuples / result records over `out` in *new* public APIs; keep `out` for `Try*` patterns that mirror the BCL.
- Only use `in` with `readonly struct` arguments.
- Mark your own struct parameters `in` only when you've profiled copies as a bottleneck.

### Common Mistakes

- Thinking `out` means the variable was passed by reference and the caller's original matters — the caller's variable IS overwritten, but you can pass an unassigned variable.
- Calling a non-readonly member on an `in` parameter → silent defensive copy.
- Using `ref`/`in` for value types < 16 bytes — copying is *cheaper* than the pointer + aliasing complexity.

### Interview Follow-up Questions

1. `ref` vs `out` — same IL? (Yes, differing only in definite assignment rules.)
2. What is a defensive copy and when does the compiler make one?
3. What's the difference between `ref` and `in` on a struct parameter? (mutable vs read-only reference)
4. Can you `await` inside a method with an `in` parameter? (Yes, unless the argument is a `ref struct`.)
5. Why can't `ref struct` be boxed or stored in a field of a class? (heap escape rule)

### Senior Level Talking Points

> "The senior answer distinguishes *mechanism* from *design*. `ref`/`in` are mechanisms to remove copies and enable in-place mutation — valuable in allocation-sensitive parsers, like a FHIR date parser that slices `ReadOnlySpan<char>` fields. But they're also a complexity tax: aliasing makes reasoning harder. So I use them surgically, behind well-tested primitives, never scattered through domain code."

### Diagram

```
Caller stack                 Callee frame
┌─────────────────┐
│ int a = 5;      │
│ Fn(ref a);      │
│                 │   ref ──► managed pointer to caller's slot
└─────────────────┘            └► Fn(int& a)  { a = 99; }  // caller's a becomes 99
```

### Memory Trick

**"`out` is a promise, `in` is a shield, `ref` is a two-way door."**

---

## 1.6 `const` vs `readonly` vs `static readonly`

### Interview Answer (30–45 seconds)

> "`const` is a compile-time constant — it must be initialized with a literal and is *inlined* into every reference, so its value is baked into the IL at the call site. `readonly` is a runtime constant — it's set once, either in a field initializer or the constructor, and can hold any value computed at runtime, even reference types. `static readonly` is a runtime constant shared across all instances. The practical difference matters for versioning: if a `const` in a library changes, every consumer must recompile to see it, because the old value is copied into their assemblies. That's why for configuration-like values that could change, I use `static readonly` or configuration, and `const` only for things that literally never change, like `Math.PI` or a magic string prefix."

### Detailed Explanation

**`const`:**

- Value must be computable at compile time: literals, other consts, or `nameof`.
- Only allowed for primitives + `string` + enum.
- Compiled as literal — no backing field at all. The IL embeds the value directly at each use site.
- Cannot be used as an argument to `ref`/`out`, cannot be `static` (implicitly static), cannot be used where a runtime value is required (e.g., `Array.Length`).

**`readonly` (instance):**

- Initialized at declaration or in the constructor; cannot be changed afterward.
- Can be any type, any runtime-computed value.
- Emits a real field with a `readonly` constraint enforced by the compiler (and the runtime, for correctness of reference-types pointing to arrays, etc.).

**`static readonly`:**

- Same as `readonly` but single instance shared by all class instances. Initialized either inline (before static ctor runs) or in the static constructor.
- Common pattern: lazily-frozen configuration, "immutable reference constants" like `public static readonly Regex PhonePattern = new(...);` — wait, that's not immutable content but the reference is.

**Versioning trap (the money detail):** `public const int DaysInWeek = 7;` used by assembly B. Change to `8` in A, rebuild A only → B still sees 7 because 7 was inlined into B. With `static readonly`, B reads the *field* at runtime → sees the new value without recompiling.

**`const` vs `static readonly` for strings:** const for small, stable, public contracts you control recompilation of. `static readonly` for values that may be swapped (e.g., via config) or computed.

### Real World Example (Healthcare)

```csharp
public static class Hl7Constants
{
    public const string SeparatorField = "|";       // literally never changes
    public static readonly string DefaultNamespace =
        "urn:oid:2.16.840.1.113883.2.10.2.3";       // could be overridden via config
}
```

The OID namespace could need updating if the organization re-registers; `static readonly` lets the ops team override without recompiling. `"|"` will never change → `const`.

### Production Code Example

```csharp
public sealed class AuditLogService
{
    private readonly ILogger _logger;          // readonly reference, set once in ctor
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(30); // runtime-computed

    public const string Component = "AuditService";  // inlined everywhere

    public AuditLogService(ILogger<AuditLogService> logger) => _logger = logger;

    public void Write(string eventName, Guid patientId)
    {
        // timeout used at runtime — reflects any new value after rebuild/retooling
        _logger.LogInformation("{Component} handling {Event} for {PatientId}", Component, eventName, patientId);
    }
}
```

**Key lines explained:**

- `readonly ILogger` — injected once, never reassigned; prevents accidental reassignment bugs.
- `static readonly TimeSpan` — could be moved to config; `TimeSpan.FromSeconds` is not a compile-time constant so it *must* be `static readonly`.
- `const string Component` — used in a structured log template; inlined.

### Internal Working

- `const` → compile-time: replaced with literal during JIT compilation of the *consumer*; no field reference.
- `readonly` → `initonly` in IL metadata; runtime JIT enforces write-once.
- `static readonly` → initialized in the type initializer; thread-safe by the CLR's `.cctor` guarantees.

### Advantages / Disadvantages

| | const | readonly | static readonly |
|---|---|---|---|
| Compile-time inlined | Yes | No | No |
| Runtime-computed | No | Yes | Yes |
| Shared per-type | implicitly | per instance | Yes |
| Versioning-safe across assemblies | No | n/a (per instance) | Yes |

### Best Practices

- `const` only for literals that are part of a frozen contract (and you control consumers).
- `static readonly` for "constants" that could change (URIs, timeouts, regexes, code-system URIs).
- For values read from config at startup, prefer `IOptions<T>` over any constant.

### Common Mistakes

- Changing a public `const` and expecting downstream services to see it without redeploy.
- Declaring `static readonly` for something that should be config.
- Forgetting that `const` values appear in *other* assemblies — debugging "phantom values".

### Interview Follow-up Questions

1. Can a `const` be an enum? A DateTime? (enum yes; DateTime no — not a primitive literal.)
2. When is `static readonly` *not* thread-safe to initialize? (The CLR guarantees type-init thread safety.)
3. Why does `string` support `const`? (compiler special-cases string literals.)
4. What's the difference between `readonly` and `init`? (`init` allows setting via object initializer once at construction; `readonly` only within ctor/initializer.)

### Senior Level Talking Points

> "This is a versioning question wearing a syntax costume. The senior answer connects `const`'s inlining to assembly versioning and warns about public API contracts: once you ship a `const` in a package, you've frozen it. In a microservice fleet you generally redeploy everything together, so it's less painful — but in shared NuGet packages (like our healthcare SDK), `static readonly` is the safe default."

### Memory Trick

**"`const` gets tattooed at compile time; `readonly` gets locked at runtime."**

---

## 1.7 `object`, `dynamic`, `var`, and Anonymous Types

### Interview Answer (30–45 seconds)

> "`var` is just compile-time type inference — the variable still has a concrete static type, it's just written by the compiler. It's not `Variant`. `object` is the ultimate base type — everything derives from it; using it means runtime casting and boxing. `dynamic` opts out of compile-time checking entirely — resolution happens at runtime via the DLR, which is why it's slow, error-prone, and essentially only justified for interop with COM or dynamic languages. Anonymous types are compiler-generated immutable reference types with read-only properties; useful for shaping query results. In a healthcare API, I use `var` liberally, avoid `object` in signatures, and never use `dynamic` for domain data."

### Detailed Explanation

**`var`:**
- Inferred from the initializer; after declaration the type is fixed.
- `var x = null;` is illegal (can't infer); `var x = (string)null;` legal.
- Helps when types are long (`var rows = await db.Observations.ToListAsync();`).
- Can create ambiguity with tuples and numeric literals (`var d = 5.0` → double).

**`object`:**
- Base of everything. Anything can be assigned to `object` (boxing for structs).
- Usage forces casting back → type-safety lost, boxing on value types.
- `object.Equals`, `object.ReferenceEquals`, `GetHashCode`, `ToString`, `GetType`.

**`dynamic`:**
- `dynamic` is `object` at runtime with `DynamicAttribute` marking — compile-time checks deferred to runtime via the DLR binder.
- Expression trees and cached binders make repeated calls faster, but first call is slow.
- Exceptions surface at runtime, not compile time → dangerous in domain code.
- Legit uses: COM interop, JSON objects in dynamic scripts, rarely in production .NET APIs.

**Anonymous types:**
- `var p = new { Name = "Ana", Age = 34 };`
- Compiler generates an internal sealed class, properties are read-only, `Equals`/`GetHashCode` are value-based (member-wise).
- Same shape → same compiler-generated type → usable across LINQ projections.
- Cannot outlive the assembly boundary publicly (they're `internal`); can't have methods.
- C# 12 added *primary constructors* for classes, but anonymous types remain the "quick shape" tool. For anything reused across layers → `record` instead.

**`record` (modern alternative):** records give you value equality, `with` expressions, and `ToString` printing — for DTOs in healthcare APIs, `record` is the *default* over anonymous types. Anonymous types still shine for throwaway projections in LINQ.

### Real World Example (Healthcare)

Querying lab results: anonymous type to shape a single projection inside the handler; a `record` to carry the result across the service boundary; never `dynamic` (a dynamic FHIR payload would defer all validation to runtime — a patient-safety and security smell).

### Production Code Example

```csharp
public sealed record ObservationSummary(
    Guid Id,
    string TestCode,
    decimal Value,
    string Unit,
    DateTimeOffset ObservedAt);

// Inside a service:
public async Task<IReadOnlyList<ObservationSummary>> GetAbnormalAsync(
    IQueryable<Observation> query)
{
    var results = await query
        .Where(o => o.Status == "final")
        .Select(o => new        // anonymous type: cheap throwaway shape
        {
            o.Id,
            o.TestCode,
            o.Value,
            o.Unit,
            o.ObservedAt
        })
        .OrderByDescending(o => o.ObservedAt)
        .ToListAsync();

    // project to a record for crossing boundaries
    return results
        .Select(o => new ObservationSummary(o.Id, o.TestCode, o.Value, o.Unit, o.ObservedAt))
        .ToList();
}
```

**Key lines explained:**

- `record` → value equality, `with` support, concise DTO; ideal for API contracts.
- Anonymous type inside `Select` → translates to a SQL `SELECT` with those columns only (no table bloat).
- Mapping anonymous → record at the boundary keeps the domain shape explicit.

### Internal Working

- Anonymous type: compiler emits a nested generic-equivalent class; same property names/types+order → same type identity.
- `dynamic`: compiler emits `Microsoft.CSharp.RuntimeBinder` call sites that use reflection-ish binder caching; first call slow, later cached.
- `var`: purely a compiler feature — no IL difference from an explicit type.

### Comparison Table

| Aspect | `var` | `object` | `dynamic` | Anonymous |
|---|---|---|---|---|
| Compile-time checked | Yes | casts needed | No | Yes |
| Static type | inferred | unknown | `object`-ish | compiler-generated |
| Performance | none | boxing/casts | slow binder | none |
| Use in APIs | yes | avoid | interop only | internal only |

### Best Practices

- Use `var` when the type is obvious from the right side; spell out when the right side is unclear.
- Prefer `record` for DTOs, anonymous types for local projections.
- Treat `dynamic` as a red flag in review.

### Common Mistakes

- Believing `var` is a variant type.
- Returning anonymous types from public methods (compile error unless cast to `object`).
- Using `dynamic` to parse JSON when `System.Text.Json`'s `JsonNode` or typed DTOs exist.

### Interview Follow-up Questions

1. Is `var` late-bound? (No — compile-time.)
2. Can you return an anonymous type from a method? (Not directly — internal class.)
3. When is `dynamic` actually a good idea? (COM interop / dynamic languages; rare.)
4. `object` vs `dynamic` — what does the compiler do differently? (compile-time checks vs runtime binder.)

### Senior Level Talking Points

> "The senior take: `var` is style; `dynamic` is an architectural smell; anonymous types are a LINQ optimization detail. In a healthcare system the cost of `dynamic` isn't just perf — it's that your CI can't catch a typo'd property path on a patient payload at compile time. Every one of those is a potential runtime 500 on a clinical endpoint, which is a compliance and safety issue."

### Memory Trick

**"`var` infers, `object` boxes, `dynamic` defers, anonymous types vanish (internal)."**

---

## 1.8 Nullable Value Types and Nullable Reference Types

### Interview Answer (30–45 seconds)

> "`Nullable<T>` (written `int?`) is a value-type wrapper that adds a boolean `HasValue` and `Value`; it's how value types model the absence of a value. Nullable reference types are a *compile-time* feature — the `?` annotation on a reference type (`string?`) is checked by the compiler's flow analysis, not the runtime, so it documents intent and catches null-flow bugs at compile time while emitting `[Nullable]` attributes. I enable `<Nullable>enable</Nullable>` on every project and treat warnings as errors in CI, because null-related bugs in a healthcare system can mean unhandled exceptions on clinical endpoints."

### Detailed Explanation

**`Nullable<T>` mechanics:**

- `int?` == `Nullable<int>` — a struct with `T Value` and `bool HasValue`.
- `HasValue == false` → `Value` throws `InvalidOperationException`.
- Boxing: `int?` with a value boxes to a boxed `int`; without a value, boxes to `null`.
- Operators are lifted: `int? a + int? b` → `null` if either is null.
- `??` and `?.` operators give concise handling: `x?.ToString() ?? "n/a"`.

**Nullable reference types (NRT, C# 8+, `#nullable enable`):**

- `string s` (non-nullable) vs `string? s` (nullable) — annotations only; no runtime difference.
- Compiler flow analysis: tracks null state of variables across assignments, calls, `if` checks, etc. Produces warnings (not errors) for dereference-of-possibly-null.
- Emits attributes: `[Nullable(2)]` for nullable references, `[NotNull]`, `[MaybeNull]`, `[NotNullWhen(true)]` on parameters/returns to propagate state across methods.
- Interop: unannotated external code is treated as "oblivious" (both), which blunts analysis at boundaries.
- Runtime: NRT is *not* enforced — a `string` can still be null at runtime if from JSON, reflection, or interop. `[NotNullDisallowNull]` doesn't add runtime checks.

**The `!` operator:** the null-forgiving operator (`x!`) tells the compiler "trust me, this isn't null." Use sparingly — it's a declaration, not a runtime check.

**Modern patterns in .NET 8:**

- `<Nullable>enable</Nullable>` + `<WarningsAsErrors>nullable</WarningsAsErrors>`.
- `required` members and `[SetsRequiredMembers]` in constructors for non-nullable initialization guarantees.
- `IOptions<T>` with `Bind` — config binding is where nulls sneak into properties typed non-nullable.

### Real World Example (Healthcare)

FHIR fields like `Observation.valueQuantity` are genuinely optional. Modeling `Quantity? ValueQuantity` (NRT) + `int? value` (Nullable<T>) correctly expresses "a glucose observation may not have a value." Meanwhile `Observation.subject` must be present — type it non-nullable and use `required`.

### Production Code Example

```csharp
public sealed class ObservationDto
{
    public required string Id { get; init; }          // must be set
    public required string SubjectRef { get; init; }  // must be set (patient link)
    public string? EncounterRef { get; init; }        // optional
    public decimal? Value { get; init; }              // optional numeric (Nullable<T>)
    public string Unit { get; init; } = "unknown";    // defaulted, non-null
}

// Flow analysis in action
public static string Describe(ObservationDto obs)
{
    if (obs.Value is { } v)
        return $"Glucose {v:0.##} {obs.Unit}";
    return $"Glucose not measured ({obs.Id})";
}
```

**Key lines explained:**

- `required` → compiler error if the object initializer omits it → non-null contract enforced at compile time.
- `decimal?` → correct modeling of an absent lab value.
- Pattern `obs.Value is { } v` → flow analysis proves `v` is the non-null value.
- `{ get; init; }` → immutable after construction — safe to share across handlers.

### Internal Working

- NRT annotations compile to metadata attributes; the JIT ignores them. Only analyzers/compilers consume them.
- Flow analysis is local to a method (plus `[NotNullWhen]` contracts on called methods); cross-method state tracking uses attributes.
- `Nullable<T>` is a real struct with a real field (`hasValue` + `value`), so there IS a size cost: `bool + T` (with padding). This is why `int?` is bigger than `int`.

### Advantages / Disadvantages

| Feature | Advantages | Disadvantages |
|---|---|---|
| `Nullable<T>` | real "no value" semantics for value types | larger size, lifted-operator mental cost |
| NRT | compile-time safety, self-documenting APIs | no runtime enforcement; interop boundaries lie |
| `required` | construction contract enforced | can't be used with records' positional syntax as freely |

### Best Practices

- Enable nullable on all projects; treat warnings as errors.
- Use `??`, `?.`, `switch` pattern matching (`is { }`) — avoid `!` except at proven interop boundaries.
- Validate at the boundary: `ApiController`/`[ApiController]` model validation, JSON deserialization defaults.
- Mark DTO members that legitimately may be absent as `?`.

### Common Mistakes

- Relying on NRT for runtime null safety (it's compile-time only).
- Overusing `!` to silence warnings → hiding real bugs.
- Deserializing untrusted JSON into non-nullable properties and then dereferencing → NRE at runtime despite green CI.

### Interview Follow-up Questions

1. Is NRT a runtime feature? (No — compile-time attributes + flow analysis.)
2. `int?` size vs `int`? (Larger — adds a `bool` + padding.)
3. What do `[NotNullWhen(true)]` and `[MaybeNull]` do?
4. `??` vs `?.` vs `??=` — give an example of each.
5. What happens when you box a null `int?`? (null reference, not a box.)

### Senior Level Talking Points

> "NRT is a *contract language*, and in healthcare we live or die by contracts. `required` + non-nullable + `[ApiController]` validation means a clinical endpoint literally cannot be invoked with a missing patient reference and slip into a runtime NRE — it fails at the boundary, which is exactly where failures should surface. The senior insight is that null-safety is a boundary problem: annotate at the edge, keep the core strict, and don't let `!` spread like a hedge."

### Memory Trick

**"`?` on a value type = a real 'no value' box; `?` on a reference = a compile-time promise."**

---

## 1.9 Equality: `==`, `Equals`, `ReferenceEquals`, `IEquatable<T>`

### Interview Answer (30–45 seconds)

> "`ReferenceEquals` checks identity — are two references pointing at the exact same object. `==` for reference types checks reference equality *unless* the type overloads `==` (like `string`, which compares content). `object.Equals` is virtual and can be overridden for value semantics; value types get default *bitwise* equality unless they override `Equals`. `IEquatable<T>` gives typed, allocation-free equality and is what `List<T>.Contains`, `HashSet<T>`, and `Dictionary<TKey,...>` actually use. The rule of thumb: if your type needs value equality, implement `IEquatable<T>`, override `Equals(object)`, `GetHashCode()`, and `==`/`!=` together, and keep `GetHashCode` consistent with `Equals` or you'll break hash-based collections. Or just use a `record`, which does all of it correctly for you."

### Detailed Explanation

**The three-layer system:**

1. **`object.ReferenceEquals(a, b)`** — identity only. Never overridden.
2. **`static object.Equals(a, b)`** — null-safe dispatcher: handles nulls, then delegates to `a.Equals(b)`.
3. **`a == b`** — a static operator, decided at *compile time* by the static type of the operands (not virtual). For `string` it's content equality (compiler/BCL). For `object`, it's reference equality unless the static type overloads it.

**The classic `string` nuance:** `(object)s1 == (object)s2` → reference equality (identity), while `s1 == s2` → content equality (because `string` overloads `==`). Both being interned literals, even reference equality can be true.

**`GetHashCode` contract:** equal objects must have equal hash codes. Unequal objects *may* share a hash code (collision). If you override `Equals` without `GetHashCode`, `HashSet<T>`/`Dictionary<T>` silently break. Hash must be stable while the object lives in a hash collection — that's why mutable keys are a bug.

**`IEquatable<T>`:** generic interface; `Equals(T? other)`. Generic collections call this (they test `T : IEquatable<T>` at runtime via `EqualityComparer<T>.Default`), avoiding boxing for value types.

**`EqualityComparer<T>.Default`:** the workhorse. For `int` → `Int32Comparer`; for types implementing `IEquatable<T>` → uses it; else falls back to `object.Equals`. Also provides `Default` for null handling.

**`record` types:** compiler generates `IEquatable<T>`, value-based `Equals`, `GetHashCode`, `==`, `!=` — and equality is *based on properties*, including for `record class`. `record struct` gets the same treatment with value-type storage.

### Real World Example (Healthcare)

Comparing a cached `Quantity` (`value`, `unit`, `system`) to the incoming value from a new lab result. `record struct Quantity` gives value equality — two `Quantity(120,"mg/dL","http://unitsofmeasure.org")` compare equal. In contrast, comparing two `Observation` *records* by value is a bug — a patient's observation has identity (`Id`); value-equality would collapse two distinct readings with equal fields.

### Production Code Example

```csharp
// Option A (preferred): let the compiler do it
public readonly record struct Quantity(decimal Value, string Unit, string System);

// Option B: hand-rolled value equality
public sealed class LabCode : IEquatable<LabCode>
{
    public string Code { get; }
    public string System { get; }

    public LabCode(string code, string system) { Code = code; System = system; }

    public bool Equals(LabCode? other) =>
        other is not null &&
        string.Equals(Code, other.Code, StringComparison.Ordinal) &&
        string.Equals(System, other.System, StringComparison.Ordinal);

    public override bool Equals(object? obj) => obj is LabCode other && Equals(other);

    public override int GetHashCode() => HashCode.Combine(Code, System);

    public static bool operator ==(LabCode? l, LabCode? r) => l?.Equals(r) ?? r is null;
    public static bool operator !=(LabCode? l, LabCode? r) => !(l == r);
}
```

**Key lines explained:**

- `record struct` → compiler emits the whole equality contract; `readonly` prevents mutation surprises.
- `Equals(LabCode?)` — typed, allocation-free.
- `HashCode.Combine(Code, System)` — stable, correct combination.
- `l?.Equals(r) ?? r is null` — null-safe `==` (both null → true).

### Internal Working

- `HashSet<T>` buckets by `GetHashCode` then confirms with `Equals` — bucket lookup is O(1) average, degrading to O(n) if hashes collide badly (esp. if `GetHashCode` returns a constant).
- `EqualityComparer<T>.Default` caches a comparer per type in a static dictionary (one-time reflection cost).
- String equality with `==` calls `String.Equals` with ordinal comparison by default (cultural comparisons only if explicitly asked).

### Comparison Table

| Operation | Type | Basis | Notes |
|---|---|---|---|
| `ReferenceEquals` | any | identity | never overridden |
| `==` (reference types) | compile-time static | identity unless overloaded | `string` → content |
| `==` (value types) | compile-time static | bitwise/overridden | `float` NaN caveats |
| `object.Equals` | virtual | overridable | used by `List<T>.Contains` via comparer |
| `IEquatable<T>` | generic | typed value equality | no boxing; used by hash collections |

### Best Practices

- Default to `record` for value-equality domain values.
- If hand-rolling: override the full quartet (`IEquatable<T>`, `Equals(object)`, `GetHashCode`, `==`/`!=`).
- Never mutate a field that participates in `GetHashCode` while the object is a dictionary/hashset key.
- Use `StringComparer.Ordinal` for clinical codes.

### Common Mistakes

- Overriding `Equals` but forgetting `GetHashCode`.
- Using mutable properties in `GetHashCode`.
- Comparing `float`/`double` with `==` (NaN != NaN; precision issues) — use an epsilon or `decimal` for money/vitals.
- Assuming `==` on `string` is reference equality (it's content — usually what you want, but `(object)a == (object)b` is not).

### Interview Follow-up Questions

1. Why does overriding `Equals` force overriding `GetHashCode`?
2. What is `EqualityComparer<T>.Default` and when does it use `IEquatable<T>`?
3. When is `(object)s1 == s2` true but `s1 == s2` also true? (Interning — both content and reference equal.)
4. Should equality be based on mutable state? (No — hash collections break.)
5. `record` equality — how does it work and how do you exclude a field? (Positional/init props; implement `IEquatable<T>` manually or use `with`.)

### Senior Level Talking Points

> "Equality is where correctness and performance meet. I had a team spend a week on a 'mystery' where lab codes collided in a `HashSet` — root cause: a hand-rolled `GetHashCode` that combined an unstable property. The senior lesson: equality and hashing are *contracts*, and if you can't articulate the invariant ('equal objects, equal hashes'), delegate to the compiler via `record`. When you must hand-roll, you own all four members or you own the bug."

### Memory Trick

**"Equal objects must share a hash; hash must never change while in a HashSet."**

---

## 1.10 Exception Handling, `try`/`catch`/`finally`, and `using`

### Interview Answer (30–45 seconds)

> "Exceptions are the .NET mechanism for signalling failures; they carry type, message, stack trace, and inner exceptions. I use `try`/`catch` at *boundaries* where I can actually do something — logging, translating to a proper HTTP status, retrying via Polly — and `finally`/`using` for deterministic resource cleanup. `using` compiles to a `try/finally` around `Dispose()`. The senior rules: never catch what you can't handle; never swallow exceptions silently; keep `catch (Exception)` broad only at process/request boundaries; use `throw;` not `throw ex;` to preserve the stack trace; and prefer result-objects (like the Try-pattern or `OneOf`) for *expected* business outcomes, reserving exceptions for truly exceptional conditions — a guideline especially important in high-throughput healthcare APIs where 'validation failed' is common, not exceptional."

### Detailed Explanation

**Exception anatomy:**

- `System.Exception` — `Message`, `StackTrace`, `InnerException`, `Data`, `Source`, `HResult`.
- Custom exceptions: derive from `Exception` (or more specific like `InvalidOperationException`), follow the naming convention `...Exception`, implement the serialization constructors (obsolete-ish in .NET 8; `Exception` is serializable but the pattern is mostly legacy now).

**`try`/`catch`/`finally` semantics:**

- `catch` filters run in order (first match wins); `when` filters let you catch conditionally: `catch (SqlException ex) when (ex.Number == 1205)`.
- `finally` runs on normal exit, exception exit, and even `return` — it's for cleanup that *must* happen.
- `throw;` (bare rethrow) preserves original stack trace; `throw ex;` resets it (the classic bug).
- Returning inside `try` does not skip `finally`.

**`using` and `IDisposable`:**

- `using var x = new ...;` → scope-based disposal at end of block.
- `using (var x = ...)` → explicit block.
- Compiles to `try/finally { x.Dispose(); }` — in .NET Core 2.1+ it's the *pattern-based* `using` (no cast to `IDisposable`).
- `await using` for `IAsyncDisposable`.
- `Dispose()` should not throw in most cases; `Dispose(bool)` + finalizer pattern is the legacy manual pattern (SafeHandle in modern code).
- Objects implementing `IDisposable` held across an async method need careful handling (the "async dispose" gap).

**Exception hierarchy to know:**

- `SystemException` → most runtime exceptions.
- `ArgumentException` → `ArgumentNullException`, `ArgumentOutOfRangeException`.
- `InvalidOperationException` — "object is in a state that doesn't allow this".
- `NotSupportedException`, `NotImplementedException`.
- `IOException` → `SqlException`, `HttpRequestException`, `EndOfStreamException`, `OperationCanceledException` → `TaskCanceledException`, `TimeoutException`.

**Exception handling anti-patterns:**

- Catching everything and doing nothing (swallowing).
- Using exceptions for control flow (`Parse` vs `TryParse`).
- Logging inside every method (perf + noise).
- `catch` with no `when` clause that then filters internally.

**The .NET 8 async flavor:** `async` methods turn a synchronous exception thrown before the first `await` into a *faulted task* (not a synchronous throw). Also: exceptions inside `Task.WhenAll` are aggregated into `AggregateException` when accessed via `.Result`, but `await` unwraps to the first.

### Real World Example (Healthcare)

A clinical endpoint calling a downstream FHIR server. Design:

- Expected outcomes (patient not found, invalid date) → returned as API results (`Results.NotFound`, `Results.BadRequest`), NOT exceptions.
- Infrastructure failures (DB down, downstream timeout) → exceptions caught at boundary middleware → logged with correlation ID → mapped to 502/503 with a generic message (never leaking stack traces to PHI-adjacent clients).
- Retryable transient errors (deadlocks 1205, timeouts -2) → `catch (SqlException ex) when (IsTransient(ex))` → Polly retry.

### Production Code Example

```csharp
// Boundary middleware translating exceptions to responses (ASP.NET Core)
public sealed class ExceptionHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    public ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (DomainNotFoundException)
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
        }
        catch (DomainValidationException ex)
        {
            context.Response.StatusCode = StatusCodes.Status422UnprocessableEntity;
            await context.Response.WriteAsJsonAsync(new { errors = ex.Problems });
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            // client went away — don't log as error, don't respond
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception for {TraceId}",
                Activity.Current?.Id ?? context.TraceIdentifier);
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        }
    }
}
```

**Key lines explained:**

- Specific catches for *known* domain outcomes → correct status codes.
- `when (context.RequestAborted...)` — don't treat client-cancellation as a server fault.
- Last broad `catch` — the boundary: logs with a correlation ID, returns a safe generic 500, never leaks internals.

### Internal Working

- `throw` → runtime walks the stack searching for a matching handler, unwinding frames; builds `StackTrace` from that walk.
- Filtering (`when`) → the filter expression runs *before* entering the handler, so the handler isn't entered if false; enables resource-cleanup reasoning.
- First-chance exceptions: debugger/`AppDomain.FirstChanceException` sees every throw even if caught.
- `finally` runs during unwind.

### Best Practices

- Catch specific types; add `when` filters; never swallow.
- `throw;` to rethrow; never `throw ex;`.
- Dispose deterministically with `using`/`await using`.
- Log exceptions with structured logging (properties, not just message text) — see Chapter 36.
- Exceptions are for exceptional conditions; expected outcomes are results/status codes.

### Common Mistakes

- `throw ex;` destroying stack traces.
- `catch (Exception)` + `return default` swallowing failures.
- Throwing/catching exceptions inside hot loops (benchmark it — it's brutal).
- Not disposing `DbContext`/`HttpClient`/streams properly.
- Believing `finally` can be avoided because "nothing can go wrong."

### Interview Follow-up Questions

1. `throw;` vs `throw ex;` — difference and why it matters?
2. Can `finally` be skipped? (Only via `Environment.FailFast`/process death, or stack overflow.)
3. What is `AggregateException` and when do you see it? (`Task.Wait`/`.Result` of `WhenAll`.)
4. What does `using` compile to? When would you need a custom `using`-like pattern (`ref struct` + `Dispose`)?
5. `catch` with `when` vs `catch` + internal `if` — which is better and why? (Filter prevents handler entry → correct resource semantics, e.g., `finally`.)

### Senior Level Talking Points

> "The senior line: an exception is a *bug report* or an *outage report*, not a business result. In healthcare APIs, every `400/404/409` should be a deliberate response; every `500` is a bug that needs a trace ID in the logs and an alert. I also make a point that cancellation (`OperationCanceledException`) deserves its own handling — mistaking client disconnects for server faults inflates error budgets and wakes people up at 3 AM for nothing."

### Memory Trick

**"Catch what you can fix; log what you can't; `finally` cleans what you opened."**

---

## 1.11 Modern C# Type System Summary (.NET 8)

### Interview Answer (30–45 seconds)

> "Modern C# gives us a rich type toolkit: `record` for value-semantic DTOs, `record struct` for small immutable values, `readonly struct` + `ref struct` for zero-copy spans, `required` and `init` for construction contracts, pattern matching with `is`/`switch` for expressive logic, primary constructors (C# 12) for concise classes, and `DateOnly`/`TimeOnly` for domain-correct dates and times. The discipline of the 2020s is *type-driven design*: the type system expresses invariants — non-null, immutable, valid ranges — at compile time, so the runtime has less to get wrong."

### Detailed Explanation

**The modern toolkit table:**

| Feature | Version | Purpose |
|---|---|---|
| `record` | C# 9 | value equality, `with`, concise DTO |
| `record struct` | C# 10 | value semantics for structs |
| `init` | C# 9 | immutable properties via initializer |
| `required` | C# 11 | mandatory members |
| `primary constructors` | C# 12 | constructor-inline fields/params |
| `DateOnly`/`TimeOnly` | .NET 6 | dates & times without timezone |
| `TimeProvider` | .NET 8 | injectable clock for testing |
| `Random.Shared` | .NET 6 | thread-safe random |
| collection expressions `[a,b,c]` | C# 12 | unified collection literals |
| `params ReadOnlySpan<T>` | C# 13 | low-alloc params |

**Pattern matching:**

- Property patterns: `o is { Status: "final", Value: > 0 }`.
- List patterns (C# 11): `arr is [_, var second, ..]`.
- Switch expressions with guards: `x switch { > 100 => "high", < 60 => "low", _ => "normal" }`.
- Type patterns + `var` capture.

**Primary constructors (C# 12):** parameters become fields if used in members, or just constructor params if not. Records already had positional constructors; classes get them too in C# 12.

**Where seniors actually apply these:**

- DTO/contracts → `record`/`required`.
- Parsers/hot paths → `Span<T>`, `readonly struct`, collection expressions.
- Testability → `TimeProvider`, injecting `Random.Shared`.

### Real World Example (Healthcare)

```csharp
public sealed record PatientDemographics(
    string PatientId,           // FHIR logical id
    string GivenName,
    string FamilyName,
    DateOnly? DateOfBirth,      // no timezone nonsense for a birth date
    Sex AdministrativeSex);

public enum Sex { Unknown, Male, Female, Other }

// Usage with collection expressions + pattern matching:
public static bool IsMinor(PatientDemographics p, DateOnly asOf)
    => p.DateOfBirth is { } dob && (asOf.Year - dob.Year, asOf.Month, asOf.Day) >= (18, dob.Month, dob.Day);
```

**Key lines explained:**

- `DateOnly?` — a date of birth has no timezone or time component; `DateTime` would be wrong.
- `(asOf.Year - dob.Year, ...) >= (18, ...)` — tuple comparison for age arithmetic (avoids the "month/day underflow" bug).
- `record` → free value equality for demos/tests; `with` for corrections.

### Best Practices

- Model dates with `DateOnly`, instants with `DateTimeOffset` (never `DateTime` for instants).
- Inject `TimeProvider` to test time-dependent clinical logic (e.g., "am I outside the 30-day refill window?").
- Use `record` for contracts, `class` for stateful services.
- Enable all modern analyzers (`EnableNETAnalyzers`, `AnalysisLevel: latest`).

### Common Mistakes

- Using `DateTime.Now` in testable code (nondeterministic).
- Using `DateTime` for birth dates or lab dates (timezone bugs).
- Structuring mutable DTOs when `record` with `with`-semantics is cleaner.

### Interview Follow-up Questions

1. `record class` vs `record struct` — when each?
2. What are primary constructors and a gotcha with them? (Captured params become fields if referenced; copy semantics of records.)
3. `DateOnly` vs `DateTime` vs `DateTimeOffset` — which for what?
4. What is `TimeProvider` for? (Deterministic time in tests.)

### Senior Level Talking Points

> "Type-driven design is the quiet superpower of modern C#. `DateOnly?` for DOB, `required` for clinical identifiers, `record` for FHIR-like resources — each one encodes a rule the compiler enforces. When an interview probes this, show that you don't just know the syntax; you know which type *means* what in the domain, because in healthcare the type system is the first line of defense against clinically wrong code."

### Memory Trick

**"DateOnly is a calendar day; DateTimeOffset is a moment; DateTime is legacy."**

---

## Chapter 1 Wrap-Up

### Top 10 Interview Questions From This Chapter

1. Explain the difference between value types and reference types with an example.
2. Where do value types and reference types live in memory?
3. What is boxing and why should you avoid it in hot paths?
4. Why are strings immutable and how does `StringBuilder` help?
5. What is string interning, and when is it dangerous?
6. `ref` vs `out` vs `in` — explain each with semantics.
7. `const` vs `readonly` vs `static readonly` — which to use where?
8. How do nullable reference types work under the hood? Are they enforced at runtime?
9. `==` vs `Equals` vs `ReferenceEquals` — when does each apply?
10. `throw;` vs `throw ex;` — and when to catch vs. not catch.

### Revision Notes (1 page)

- **Value vs Reference:** values are data, references are addresses. Copy semantics, equality, nullability, GC all derive from this.
- **Stack/Heap:** stack is per-thread, O(1), frame-scoped; heap is shared, GC-managed, non-deterministic teardown. `async` moves locals to the heap via state machines; closures lift captured variables to the heap.
- **Boxing:** value type → `object`/interface wraps in a heap object. Allocation + copy → Gen-0 garbage. Eliminate with generics (`List<T>`, not `ArrayList`).
- **Strings:** immutable; concat in loops is O(n²); `StringBuilder` is a growable char buffer. Interning is process-lifetime memory — never intern user input. `$""` in .NET 8 is handler-based and allocation-light.
- **Parameters:** everything passes by value; `ref` shares the caller's slot (two-way), `out` promises assignment, `in` read-only reference (defensive copies with non-`readonly` structs).
- **Constants:** `const` is inlined at compile time (versioning trap); `readonly`/`static readonly` are runtime-frozen fields.
- **Types:** `var` = compile-time inference; `object` = base everything; `dynamic` = runtime binder (avoid); anonymous types = internal throwaway shapes (prefer `record` for boundaries).
- **Nullability:** `Nullable<T>` real struct; NRT compile-time attributes + flow analysis only — validate at boundaries, use `required`, avoid `!`.
- **Equality:** `ReferenceEquals` identity; `==` compile-time dispatch (string = content); `object.Equals` virtual; `IEquatable<T>` allocation-free; `GetHashCode` must align with `Equals`; `record` does it all.
- **Exceptions:** exceptions = bug/outage reports, not control flow. Catch at boundaries, filter with `when`, `throw;` not `throw ex;`, `finally`/`using` for cleanup, `OperationCanceledException` handled specially.

### Things Interviewers Expect From 5+ Years Experience

- You can articulate *why* a design choice matters, not just the syntax.
- You connect C# mechanics (GC, boxing, closures) to *observable* effects (latency spikes, memory growth) and to *measurement* (counters, BenchmarkDotNet).
- You know modern .NET 8 recommendations and can call out deprecated patterns (e.g., `DataTable`, `DateTime.Now`, `throw ex;`, `ArrayList`).
- You reason about clinical correctness: ordinal code comparison, `DateOnly` vs `DateTimeOffset`, immutable DTOs, boundary validation.
- You treat the type system as a contract-enforcement tool (`record`, `required`, nullable, `init`).

### Cheat Sheet

```
VALUE vs REFERENCE:
  struct/enum/primitive = data copied
  class/string/array     = pointer copied
  (int, decimal, DateTime, Guid → struct; Patient, List → class)

BOXING TRIGGERS:
  object param, ArrayList, Hashtable, DataTable, enum.ToString() via object
  KILL: generics, List<T>, Dictionary<K,V>, readonly struct + IEquatable<T>

STRING RULES:
  concat in loop → StringBuilder (pre-size!)
  literals identical → interned (ReferenceEquals true)
  $"" → DefaultInterpolatedStringHandler (no box, no intermediate)
  codes → StringComparison.Ordinal

PARAMS:
  out = must assign;  ref = two-way;  in = read-only ref (use with readonly struct)

CONSTANTS:
  const = inlined (recompile consumers!)  |  readonly = runtime frozen
  static readonly = shared runtime constant  (config → IOptions)

NULL:
  int? → Nullable<T> struct  |  string? → compile-time annotation only
  ?? , ?. , is { }   |   enable <Nullable>enable</Nullable>

EQUALS:
  ReferenceEquals(identity)  vs  ==(static dispatch; string=content)
  object.Equals(virtual)     vs  IEquatable<T>(typed, no box)
  ALWAYS pair GetHashCode with Equals   |  records do it for you

EXCEPTIONS:
  catch specific + when(filter) + throw;   (never throw ex;)
  finally/using = cleanup   |  expected outcomes → results, not exceptions
  catch (Exception) ONLY at boundary, log with TraceId
```

### Flash Cards

**Q1:** `int[] a = new int[10];` — value or reference? **A:** The array is a reference type on the heap; the `int` elements are value types stored contiguously inside it.

**Q2:** Two `string` variables, same literal — `==` and `ReferenceEquals`? **A:** Both `true` (literals are interned → same instance).

**Q3:** `StringBuilder` vs `+` in a loop of 100k — why? **A:** `+` = O(n²) allocation; `StringBuilder` = amortized O(n), growable char buffer.

**Q4:** When does `int?` box? **A:** When assigned to `object`/interface. With value → boxed `int`; without → `null`.

**Q5:** `const int X = 2;` changed to `3` in a library — what breaks? **A:** Consumers not recompiled still inline `2`.

**Q6:** `ref` vs `out`? **A:** `out` must be assigned by callee; `ref` is two-way; identical IL otherwise.

**Q7:** What does `using` compile to? **A:** `try/finally { Dispose(); }` (pattern-based since .NET Core 2.1).

**Q8:** `throw;` vs `throw ex;`? **A:** `throw;` preserves stack trace; `throw ex;` resets it to the catch site.

**Q9:** Why override `GetHashCode` with `Equals`? **A:** Equal objects must hash equal, or `HashSet`/`Dictionary` break.

**Q10:** Is NRT enforced at runtime? **A:** No — compile-time flow analysis + metadata attributes only.

### Interview Confidence Score

**Medium.** These are foundational but they test *precision* — 5+ year candidates are expected to answer instantly, correctly, and with a production/healthcare lens. Miss the `GetHashCode` or `throw ex;` details and you look like a junior.

---

*Continue → Chapter 2: Object-Oriented Programming*
