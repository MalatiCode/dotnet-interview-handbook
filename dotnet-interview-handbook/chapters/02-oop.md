# Chapter 2: Object-Oriented Programming

> **Audience:** Experienced .NET developers (5+ years) preparing for an L2 (Mid/Senior) interview at a Healthcare company.
> **Scope:** The four pillars of OOP, SOLID principles, interfaces vs. abstract classes, polymorphism, composition vs. inheritance, cohesion and coupling, sealed types, static classes, and how to apply all of this to healthcare domain modeling.

---

## 2.1 The Four Pillars of OOP

### Interview Answer (30–45 seconds)

> "The four pillars are encapsulation, abstraction, inheritance, and polymorphism. Encapsulation hides internal state and exposes a controlled surface — in C# that's access modifiers plus properties and backing fields. Abstraction exposes 'what' an object does while hiding 'how' — interfaces and abstract classes. Inheritance enables a class to derive from a base, reusing and extending behavior — with the caveat that deep hierarchies become a maintenance liability. Polymorphism lets the same call invoke different implementations depending on the runtime type — virtual methods and interface dispatch. In production healthcare code I lean heavily on encapsulation and abstraction, use inheritance sparingly, and prefer composition."

### Detailed Explanation

**1. Encapsulation — "hide and control access".**

- Bundles data + behavior; external code touches state only through an API surface.
- C# mechanisms: `private`/`protected`/`internal` fields, properties with computed accessors, indexers, and events.
- Benefit: you can change internals (e.g., swap an in-memory list for a database-backed structure) without touching consumers.
- A class is a *capsule*: what's inside (implementation) is private; what's outside (contract) is the public surface.

**2. Abstraction — "expose the contract, hide the detail".**

- Related to but distinct from encapsulation: abstraction is about *models* (interface/abstract member = contract), encapsulation is about *hiding state*.
- Interfaces: pure contract, no implementation. Abstract classes: contract + partial implementation.
- In domain modeling: `IDateTimeProvider`, `IPatientRepository`, `IClinicalAlertRule` are abstractions; concrete classes provide implementations.

**3. Inheritance — "is-a" relationship.**

- A derived class *is* a base class. C# supports single class inheritance (one base class), plus multiple interface implementation.
- `virtual`/`override` for polymorphic extension; `abstract` members must be implemented.
- `sealed` prevents further derivation.
- The classic problem: deep hierarchies ("god base class"), brittle coupling to base implementation (fragile base class problem).

**4. Polymorphism — "many forms".**

- **Compile-time polymorphism:** method overloading (same name, different signatures) and operator overloading. Decided by the compiler.
- **Runtime polymorphism:** virtual method dispatch and interface dispatch. Decided at runtime by the object's actual type.
- The classic: `Animal.MakeSound()` → `Dog` says "woof", `Cat` says "meow", decided at runtime.
- In C#, virtual dispatch is via the *virtual method table* (vtable) — every type with virtual/interface methods gets a vtable; instances carry a method-table pointer.

### Real World Example (Healthcare)

Encapsulating a FHIR `MedicationRequest` resource:

```csharp
public sealed class MedicationRequest
{
    private MedicationStatus _status = MedicationStatus.Draft;
    private readonly List<DosageInstruction> _dosages = new();

    public string Id { get; } = Guid.NewGuid().ToString();
    public string? PrescriberId { get; private set; }

    // Encapsulation: state transitions only via guarded methods
    public bool TryActivate(string prescriberId)
    {
        if (_status != MedicationStatus.Draft) return false;   // rule: only draft can activate
        PrescriberId = prescriberId;
        _status = MedicationStatus.Active;
        return true;
    }

    public IReadOnlyList<DosageInstruction> Dosages => _dosages;  // read-only view
}
```

**Key lines explained:**

- `private List<DosageInstruction> _dosages` — fully encapsulated; exposed as `IReadOnlyList<>` so callers can't mutate the collection.
- `PrescriberId` has a private setter — only the state-transition method can assign it.
- The invariant "only a Draft can be activated" lives *inside* the class. This is encapsulation of rules, not just data.

### Production Code Example

```csharp
// Abstraction
public interface IClinicalRule
{
    string RuleName { get; }
    ClinicalRuleResult Evaluate(PatientContext context);
}

// Inheritance + Polymorphism
public abstract class AlertRuleBase : IClinicalRule
{
    public abstract string RuleName { get; }

    protected abstract bool IsTriggered(PatientContext context);
    protected abstract string BuildMessage(PatientContext context);

    // Template method: shared flow, polymorphic details
    public ClinicalRuleResult Evaluate(PatientContext context)
    {
        if (IsTriggered(context))
            return ClinicalRuleResult.Triggered(RuleName, BuildMessage(context));
        return ClinicalRuleResult.NotTriggered(RuleName);
    }
}

public sealed class SepsisScreenRule : AlertRuleBase
{
    public override string RuleName => "SepsisScreen";
    protected override bool IsTriggered(PatientContext ctx)
        => ctx.Temperature >= 38.3m && ctx.HeartRate >= 110;   // qSOFA-lite example
    protected override string BuildMessage(PatientContext ctx)
        => $"Suspected sepsis: T={ctx.Temperature}, HR={ctx.HeartRate}";
}
```

**Key lines explained:**

- `IClinicalRule` — the contract (abstraction).
- `AlertRuleBase` — template method pattern via inheritance: `Evaluate` is fixed; subclasses override only the hook methods.
- `SepsisScreenRule` — polymorphism: the caller holds `IClinicalRule` and the runtime type decides behavior.

### Internal Working

- Each type with virtual members has a vtable; instance layout starts with an object header whose first word points to the method table.
- `virtual` dispatch = indirect call through the vtable; `interface` dispatch = similar but through an interface map. Both are slower than direct calls (devirtualization can help when the JIT can prove the concrete type).
- Properties compile to `get_`/`set_` methods; encapsulation is enforced at compile time, but reflection can bypass it (used by serializers/EF).

### Advantages

- Encapsulation → safe evolution, reduced blast radius.
- Abstraction → replaceable implementations, testability (mocks).
- Inheritance → reuse, IS-A modeling, open/closed extension.
- Polymorphism → code written against a contract works for unlimited implementations.

### Disadvantages

- Inheritance: deep hierarchies = coupling, fragile base class, diamond-of-death (mitigated by single inheritance in C#).
- Over-abstraction: interfaces for everything = indirection without value.
- Encapsulation can be overdone: getters/setters that are just field proxies add noise (use `record`/immutable DTOs).

### Best Practices

- Prefer interfaces for *capability* contracts; abstract classes for shared implementation.
- Keep hierarchies shallow (≤2–3 levels); prefer composition for sharing behavior.
- Make members `sealed` by default in hot-path libraries (prevents accidental overriding; enables devirtualization).
- Design for testability: abstract the I/O boundaries, not every method.

### Common Mistakes

- "Everything is an object with getters/setters" — anemic domain + no behavior → logic leaks into services.
- Deep inheritance chains that break when the base changes.
- Using inheritance when composition is right ("is-a" forced where "has-a" applies).
- Public fields instead of properties (breaking change if you ever need logic).

### Interview Follow-up Questions

1. Encapsulation vs. abstraction — what's the difference? Give a concrete example.
2. How does C# achieve multiple inheritance of behavior? (Interfaces + default interface methods.)
3. What is the fragile base class problem?
4. What is the Liskov substitution principle and how does it constrain inheritance?
5. What is an "anemic domain model" and why is it criticized?

### Senior Level Talking Points

> "The four pillars are the vocabulary, but the senior conversation is about *tradeoffs*: inheritance gives reuse at the cost of coupling, so I use it for *template* shapes like a rule base, and composition for *capabilities* like logging, auditing, or notifications. In healthcare, where every rule and every audit step is a compliance surface, the abstraction boundary matters more than the class hierarchy — the domain rules must be testable in isolation, and that comes from interface boundaries, not from deep inheritance."

### Diagram

```
                    ┌─────────────────────────────┐
                    │        IClinicalRule        │  ← ABSTRACTION (contract)
                    │   + Evaluate(context)       │
                    └─────────────────────────────┘
                                   ▲
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
┌───────────────┐          ┌───────────────┐          ┌───────────────┐
│ AlertRuleBase │          │  OtherRule    │          │    Mock       │  ← POLYMORPHISM
│ (abstract)    │          │               │          │ (tests)       │
└───────┬───────┘          └───────────────┘          └───────────────┘
        │
┌───────────────┐
│SepsisScreenRule│   ← INHERITANCE (IS-A)
└───────────────┘

ENCAPSULATION:  private _status + TryActivate() guards state transitions
```

### Comparison Table: Encapsulation vs. Abstraction

| Aspect | Encapsulation | Abstraction |
|---|---|---|
| Focus | Hides *state and implementation* | Hides *complexity*, exposes *what* |
| Mechanism | private fields, properties, methods | interfaces, abstract classes |
| Answer to | "How is the data protected?" | "What can I do with this?" |
| C# keyword | `private`/`internal`/`protected` | `interface`/`abstract` |
| Example | `_dosages` private list | `IClinicalRule` |

### Memory Trick

**"E-hide, A-reveal: Encapsulation hides how, Abstraction reveals what."**

---

## 2.2 SOLID Principles

### Interview Answer (30–45 seconds)

> "SOLID is five design principles. Single Responsibility: a class has one reason to change. Open/Closed: open for extension, closed for modification. Liskov Substitution: a derived type must be substitutable for its base without breaking behavior. Interface Segregation: clients shouldn't depend on interfaces they don't use. Dependency Inversion: depend on abstractions, not concretions — high-level policy shouldn't depend on low-level details. In practice I apply SRP to my services, use strategies and the template method for Open/Closed, design domain interfaces small and cohesive for ISP, and invert dependencies via constructor injection for DIP."

### Detailed Explanation

**S — Single Responsibility Principle (SRP)**

- A class should have exactly *one reason to change*. The "reason to change" = a stakeholder or actor whose requirements change.
- It's *not* "do only one thing" at the method level; it's about change axis.
- Classic violation: a `PatientService` that loads data, validates clinical rules, formats output, *and* sends emails. Three reasons to change.
- Fix: split into `PatientLoader`, `ClinicalRuleEngine`, `PatientFormatter`, `INotifier`.

**O — Open/Closed Principle (OCP)**

- Software entities open for *extension*, closed for *modification*.
- Add behavior by adding new code (new subclass, new strategy), not by editing existing tested code.
- Implementation tools: polymorphism, strategy pattern, template method, decorator, interfaces.
- Example: adding `SepsisScreenRule` requires *no modification* to the rule engine — the engine iterates over registered `IClinicalRule`s.

**L — Liskov Substitution Principle (LSP)**

- If `S` is a subtype of `T`, then objects of type `T` may be replaced with objects of type `S` without altering any of the desirable properties of the program.
- The practical contract: *preconditions* cannot be strengthened, *postconditions* cannot be weakened, invariants must hold, no new exceptions where the base threw none.
- Classic violation: `Square : Rectangle` where `SetWidth` breaks `Rectangle` semantics (setting width changes height). Better: common `IShape` or composition.
- Throwing `NotImplementedException` from a derived member is an LSP smell.

**I — Interface Segregation Principle (ISP)**

- No client should be forced to depend on methods it does not use.
- Fat interfaces (`IPatientRepository` with `GetVitals`, `SendMessage`, `ExportFhir`) force implementers to stub unused members.
- Split into `IPatientQueryRepository`, `INotificationSender`, `IFhirExporter`.
- Default interface methods (C# 8) can soften this but are best used carefully.

**D — Dependency Inversion Principle (DIP)**

- High-level modules should not depend on low-level modules; both should depend on abstractions. Abstractions should not depend on details; details should depend on abstractions.
- This is the foundation of Dependency Injection (Chapter 8): `OrderProcessor` depends on `INotifier`, and `EmailNotifier` depends on `INotifier` — the abstraction sits between.
- Not to be confused with Dependency *Injection* — DI is the *mechanism*, DIP is the *principle*.

### Real World Example (Healthcare)

A medication ordering pipeline:

```
HIGH-LEVEL:  MedicationOrderProcessor  ──► depends on ──►  IMedicationValidationRule
                                    ──► depends on ──►  IPrescriptionRepository
                                    ──► depends on ──►  IAuditLogger

LOW-LEVEL:   SqlPrescriptionRepository : IPrescriptionRepository
             SerilogAuditLogger : IAuditLogger
```

High-level policy (ordering flow) never references SQL or Serilog. The abstractions live in the domain; the implementations live in infrastructure. Swapping `SqlPrescriptionRepository` for a `CosmosPrescriptionRepository` or an in-memory test double requires zero changes in the processor.

### Production Code Example

```csharp
// SRP + OCP + DIP: rule engine that can grow without modification
public interface IMedicationRule
{
    string RuleId { get; }
    Task<RuleOutcome> EvaluateAsync(MedicationOrder order, CancellationToken ct);
}

public sealed class MedicationOrderProcessor
{
    private readonly IEnumerable<IMedicationRule> _rules;   // injected strategies
    private readonly IPrescriptionRepository _repository;
    private readonly IAuditLogger _audit;

    public MedicationOrderProcessor(
        IEnumerable<IMedicationRule> rules,
        IPrescriptionRepository repository,
        IAuditLogger audit)
    {
        _rules = rules;
        _repository = repository;
        _audit = audit;
    }

    public async Task<OrderResult> PlaceOrderAsync(MedicationOrder order, CancellationToken ct)
    {
        // OCP: adding a rule = adding a class, zero changes here
        foreach (var rule in _rules)
        {
            var outcome = await rule.EvaluateAsync(order, ct);
            if (!outcome.IsApproved)
                return OrderResult.Blocked(outcome.Reason);
        }

        await _repository.SaveAsync(order, ct);              // DIP: abstraction
        await _audit.LogAsync("OrderPlaced", order, ct);     // DIP: abstraction
        return OrderResult.Approved();
    }
}
```

**Key lines explained:**

- `IEnumerable<IMedicationRule>` — the processor runs *any* number of rules; the container injects them (Open/Closed + DIP).
- `_repository` / `_audit` are interfaces — the processor never knows about SQL or Serilog (Dependency Inversion).
- Each rule is a small single-responsibility class (SRP).

### Internal Working

- DIP is enforced structurally (constructor injection, composition root).
- OCP manifests as adding new registered types — the DI container enumerates them; no `if/else` chain.
- LSP violations surface at runtime as "works in tests, breaks in prod" bugs (e.g., a subtype throwing a different exception type).

### Advantages

- Testability: every dependency is a seam.
- Evolution: new rules/adapters without touching existing code.
- Comprehension: each class is small and its responsibility is named.

### Disadvantages

- More types (interfaces + impls + registration) → boilerplate and indirection.
- Over-engineering risk: applying SRP/DIP to a 3-class utility is premature.
- OCP via polymorphism can obscure control flow (you must know the registered rules).

### Best Practices

- Apply SRP at the *change-actor* level, not method level.
- Register strategies with `AddScoped<IEnumerable<IMedicationRule>>()` and inject the collection.
- Test LSP: if a derived class can't fulfill the base contract, don't derive.
- Keep interfaces small; rename for intent (`IQueryX`, `ICommandY`).

### Common Mistakes

- `IFoo` that is a grab-bag (ISP violation).
- Substituting a subtype that throws or changes invariants (LSP).
- Concrete dependency injection into high-level code (`new SqlX()` inside a processor) (DIP).
- A 2000-line "Service" class doing persistence + rules + email (SRP).

### Interview Follow-up Questions

1. What's the difference between Dependency Inversion and Dependency Injection?
2. Give a concrete LSP violation and its fix.
3. How does the Strategy pattern relate to Open/Closed?
4. Can SRP be applied too granularly? What's the cost?
5. How does the Interface Segregation Principle interact with the Adapter pattern?

### Senior Level Talking Points

> "SOLID is a *packaging* of principles I use to keep a codebase cheap to change. The senior nuance: these are guidelines with costs — I ask 'what's the actual axis of change?' before splitting a class, and I never let DIP push me into 'interface for every class' absurdity. The real test in a healthcare codebase is velocity: can we add a new clinical rule in a one-file change, covered by a unit test, without touching a reviewer's precious existing code? That's SOLID paying rent."

### Memory Trick

**"SOLID = Single, Open, Liskov, Interface, Depend — 'S.O.L.I.D. rules keep code standing.'"**

---

## 2.3 Interfaces vs. Abstract Classes

### Interview Answer (30–45 seconds)

> "An interface defines a *contract* — what a type can do — with no implementation (though C# 8 added default interface methods). A class can implement many interfaces. An abstract class provides *partial implementation* — shared state, fields, protected helpers, virtual template methods — and a class can inherit from only one. My rule of thumb: use an interface when I need a capability contract and multiple unrelated types must implement it; use an abstract class when I have shared implementation and a natural IS-A hierarchy. In practice, most of my 'seams' are interfaces, and I reserve abstract classes for template-method patterns like rule bases."

### Detailed Explanation

**Interface:**

- Syntax: `interface IPatientStore { Task<Patient?> GetAsync(string id); }`.
- Members: methods, properties, events, indexers. No fields (except static), no constructors (until C# 8 default members add bodies).
- C# 8+ *default interface methods*: interfaces can carry implementations — mainly for API evolution (add a member without breaking implementers). Use sparingly; they can hide design problems.
- Access modifiers allowed since C# 8 (`private`, `protected`, `static` members).
- `record` types can implement interfaces; `readonly struct` too.

**Abstract class:**

- `abstract class Animal { protected abstract string Sound { get; } public string Speak() => $"{Name} says {Sound}"; }`.
- Can have: fields, constructors, concrete methods, virtual/abstract members, state.
- Must be derived to be used (cannot instantiate).
- Abstract *property/method* = must be implemented by derived; `virtual` = may be overridden.

**When to choose which:**

| Scenario | Choose |
|---|---|
| Multiple unrelated types share a *capability* | Interface |
| You need to pass a contract into a generic algorithm | Interface |
| Shared implementation/state across related types | Abstract class |
| Template-method skeleton | Abstract class |
| You want a versioning-tolerant contract (add default members) | Interface (C# 8+) |
| Composition over inheritance ethos | Interface |

**Why interfaces are the DI default:** a class implementing an interface is a *role*; DI containers work naturally with interfaces. Abstract classes create coupling to base implementation (fragile base class risk).

### Real World Example (Healthcare)

```csharp
// Interfaces: capability contracts used across unrelated types
public interface IAuditSink
{
    Task WriteAsync(AuditEntry entry, CancellationToken ct);
}

// Abstract class: shared template for alerts
public abstract class AlertRuleBase
{
    public abstract string Name { get; }
    public abstract Severity Level { get; }
    protected abstract bool Evaluate(PatientSnapshot snapshot);
    public virtual string? Recommendation() => null;   // optional override
}
```

An email sink, a database sink, and an SIEM sink all implement `IAuditSink` but share nothing else — interface. All alert rules share the evaluation template — abstract class.

### Production Code Example

```csharp
public interface IHandleMessage<T>          // capability
{
    Task HandleAsync(T message, CancellationToken ct);
}

public sealed class EmailAuditSink : IAuditSink, IHandleMessage<AuditEntry>  // multiple
{
    public Task WriteAsync(AuditEntry entry, CancellationToken ct) => /* smtp */ Task.CompletedTask;
    public Task HandleAsync(AuditEntry msg, CancellationToken ct) => WriteAsync(msg, ct);
}

// Abstract base used for shared validation scaffolding
public abstract class FhirValidatorBase<T>
{
    protected abstract IEnumerable<string> ValidateRules(T resource);
    public bool IsValid(T resource) => !ValidateRules(resource).Any();
}
```

**Key lines explained:**

- `EmailAuditSink` implements two unrelated interfaces — C# single-inheritance doesn't limit capability count.
- `FhirValidatorBase<T>` shares validation plumbing; subclasses implement only the rules.

### Internal Working

- Interface dispatch: the runtime builds an *interface map* per type; calls go through it (slightly slower than virtual dispatch; JIT devirtualization can help).
- Abstract class virtual dispatch: vtable, like normal virtual inheritance.
- Default interface methods: implemented as a static DIM slot; calling them boxes/costs more — don't rely on them in hot paths.

### Advantages

| | Interface | Abstract class |
|---|---|---|
| Multiple contracts per type | Yes | No (single base) |
| Shared fields/state | No | Yes |
| Versioning tolerance | Yes (DIM) | Yes (add virtuals) |
| Testing (mock easily) | Very easy | Easy |

### Disadvantages

- Interface: no shared state; can lead to duplicate implementation (mitigate with composition/helpers); DIM is a band-aid.
- Abstract class: single inheritance consumes your one base slot; deep hierarchies; coupling to base behavior.

### Best Practices

- Default to interfaces for seams and DI; use abstract classes for shared implementation within a hierarchy.
- Name interfaces after capabilities: `IX`, `IQueryX`, `ICommandX`, `IRepository`.
- Don't use default interface methods to 'fix' a fat interface — split it (ISP).
- Make abstract classes `sealed`? No — they're abstract; but make derived leaf types `sealed`.

### Common Mistakes

- `IMyService` that's a mirror of the concrete class with zero design value.
- Abstract class with mutable public fields leaking state.
- Using inheritance to share *data* (composition would be safer).
- Forgetting that adding a member to an interface breaks implementers at compile time (until DIM).

### Interview Follow-up Questions

1. Since C# 8, when is a default interface method justified?
2. Can a struct implement an interface? (Yes — but boxing on interface dispatch.)
3. Why does the .NET team prefer interfaces in the BCL (e.g., `IEnumerable<T>`)?
4. What happens to interface methods with private access in C# 8+?
5. Abstract class with only abstract members — why not just an interface?

### Senior Level Talking Points

> "The mature answer is that this is a *coupling* decision. Interfaces couple you to a contract; abstract classes couple you to an implementation you can't fully control — and in a microservice where you ship contracts as NuGet packages, interfaces let consumers evolve independently. I use abstract classes where the shared code is the point — template methods, validators — and interfaces where replaceability is the point — repositories, notifiers, sinks."

### Diagram

```
INTERFACE (contract)                      ABSTRACT CLASS (skeleton)
┌───────────────────────┐                 ┌──────────────────────────┐
│ IAuditSink            │                 │ AlertRuleBase            │
│  + WriteAsync(...)    │                 │  + Name (abstract)       │
└───────────┬───────────┘                 │  + Evaluate (abstract)   │
            │ implements                  │  + Recommendation(virtual)│
   ┌────────┼─────────┐                   └───────────┬──────────────┘
   ▼        ▼         ▼                               ▼ (derives)
 SqlSink  EmailSink  SieveSink               SepsisRule   HypoRule
```

### Memory Trick

**"Interface = job description; abstract class = family recipe book."**

---

## 2.4 Polymorphism: Overloading vs. Overriding

### Interview Answer (30–45 seconds)

> "Overloading is compile-time polymorphism — multiple methods with the same name but different parameter lists; the compiler picks the best match. Overriding is runtime polymorphism — a derived class provides a different implementation of a `virtual`/`abstract` base member; the runtime dispatches through the vtable. The classic interview trap is method-hiding with `new`: hiding doesn't participate in virtual dispatch, so a `Base` reference calling a hidden method runs the *base* version even if the object is a derived instance. I prefer `override` for polymorphic behavior and avoid `new`-hiding except when extending a non-virtual BCL member."

### Detailed Explanation

**Overloading (compile-time polymorphism):**

```csharp
void Save(Patient p);
void Save(IEnumerable<Patient> patients);
void Save(Patient p, bool force);
```

- Selected by the compiler using the *most specific applicable* signature (with `params`, defaults, covariance rules).
- Not polymorphic — the decision is baked in at compile time.
- Works on constructors too.
- Null-literal selection: `Save(null)` — ambiguous if both overloads are applicable → compile error (needs a cast).

**Overriding (runtime polymorphism):**

```csharp
public virtual string Describe() => "Patient";
public override string Describe() => "Inpatient";
```

- Requires `virtual` on base, `override` on derived (or `abstract`).
- Dispatch: `Patient p = new Inpatient(); p.Describe();` → calls `Inpatient.Describe` (runtime type).
- `base.Describe()` can call the base implementation.
- `sealed override` stops further overrides.

**Method hiding with `new`:**

```csharp
class Base { public void X() => Console.WriteLine("Base"); }
class Derived : Base { public new void X() => Console.WriteLine("Derived"); }

Base b = new Derived();
b.X();        // "Base"    ← static type decides
Derived d = new Derived();
d.X();        // "Derived"
```

- `new` hides, doesn't override → no vtable entry → no polymorphic dispatch.
- The compiler warns CS0108 when you hide without `new`.
- Rarely desirable; if it happens on purpose, it's usually an API-compat decision.

**Overload resolution gotchas:**

- `Task.Run(() => Go())` ambiguity between `Func<Task>` and `Action` — classic.
- `params` + null.
- Generic overloads: `M<T>(T)` vs `M(object)` — `M<string>("x")` picks the generic (more specific).

### Real World Example (Healthcare)

Overloading a `ReportBuilder` for different outputs; overriding the `ToString`/`Describe` of domain records:

```csharp
public abstract class ClinicalEvent
{
    public abstract string ToDisplayText();            // override per subtype
}

public sealed class LabResultEvent : ClinicalEvent
{
    public override string ToDisplayText() => $"{TestCode} = {Value} {Unit}";
}

public sealed class MedicationAdminEvent : ClinicalEvent
{
    public override string ToDisplayText() => $"{Drug} {Dose} at {AdministeredAt:HH:mm}";
}
```

A single feed renderer `foreach (ClinicalEvent e in events) Render(e.ToDisplayText());` — pure runtime polymorphism.

### Production Code Example

```csharp
public static class FhirResourceFactory
{
    // Overloads (compile-time) — convenience over a single core method
    public static T Create<T>(string json) where T : Resource, new()
        => JsonSerializer.Deserialize<T>(json)!;

    public static T Create<T>(ReadOnlySpan<byte> utf8Json) where T : Resource, new()
        => JsonSerializer.Deserialize<T>(utf8Json)!;

    public static T Create<T>(Stream stream) where T : Resource, new()
        => JsonSerializer.Deserialize<T>(stream)!;
}

// Overriding (runtime) — resource-specific serialization
public abstract class Resource
{
    public string ResourceType => GetType().Name;
    public abstract string Serialize();
}
```

**Key lines explained:**

- Overloads share behavior but differ in input shape — the compiler routes calls.
- The abstract `Serialize()` is dispatched at runtime; a FHIR server can serialize any `Resource` subtype without knowing it.

### Internal Working

- Overload resolution is fully static — the JIT sees the resolved method.
- Virtual/override members are vtable slots; overriding replaces the slot; `new` creates a *distinct* slot shadowing the name.
- Interface dispatch uses interface maps — a different mechanism than class vtables.

### Advantages

- Overloading: ergonomic APIs; no runtime cost.
- Overriding: extensible frameworks, plugin-friendly design.

### Disadvantages

- Overloading: ambiguity can hide bugs (`null` args); too many overloads confuse.
- Overriding: vtable indirection; fragile base class risk; `new`-hiding confusion.

### Best Practices

- Keep overloads semantically consistent (same behavior, different inputs).
- Prefer `virtual` + `override` for extension; avoid `new` unless extending BCL with no `virtual`.
- Mark leaf types `sealed` when overrides aren't meant to propagate.
- Watch out for `Task.Run`-style delegate ambiguity.

### Common Mistakes

- Forgetting the `virtual` keyword — silently hiding instead of overriding.
- Using `new` and being surprised dispatch is static.
- `Save(null)` ambiguity between overloads.
- Overriding in a class that isn't `sealed`, letting subclasses override the override unintentionally.

### Interview Follow-up Questions

1. What decides which overload runs? (Compiler, most-specific-match at compile time.)
2. What decides which override runs? (Runtime type via vtable.)
3. Can you overload a method differing only by return type? (No — not by return type alone.)
4. What is the CS0108 warning? (Method hides inherited member without `new`.)
5. Overload vs. default parameter values — interplay gotchas?

### Senior Level Talking Points

> "The senior insight is *where the decision happens*. Compile-time overloading is free and predictable; runtime overriding buys extensibility but taxes reasoning — the reader must know the concrete types. I use overrides for genuinely polymorphic domain shapes and keep `new`-hiding out of the codebase entirely, because it silently breaks the substitution contract that makes OOP useful."

### Diagram

```
 COMPILE-TIME (overload)            RUNTIME (override)
 Source: Save(Patient)              var e = (ClinicalEvent)new LabResultEvent();
          Save(List<Patient>)       e.ToDisplayText();
               │                              │
          compiler picks              vtable lookup → LabResultEvent.ToDisplayText
          (static, resolved)         (dynamic, per-instance)
```

### Memory Trick

**"Overload = pick a recipe at compile time; override = the kitchen decides at runtime."**

---

## 2.5 Composition over Inheritance

### Interview Answer (30–45 seconds)

> "Composition over inheritance means building behavior by *containing* objects with the right capabilities rather than inheriting from a base class. Inheritance couples you to a base's implementation and constraints you to one ancestry; composition lets a type *delegate* to collaborators it owns — like a `NotificationService` that *has* an `ISmtpClient`, an `IQueue`, and an `ILogger`. The rule I apply: use inheritance only for genuine IS-A relationships with shared code; use composition for HAS-A capability assembly. The decorator, strategy, and facade patterns are all composition patterns, and DI makes composition natural in .NET."

### Detailed Explanation

**Why composition wins (most of the time):**

- **Fragile base class problem:** changes to a base's internals break derived classes in ways you can't see locally. Composition has no such coupling.
- **Single inheritance ceiling:** C# allows one base. Composition has no ceiling — a class can hold any number of collaborators.
- **Behavioral reuse:** inheritance exposes inherited members in your public surface (a `Dog` exposing `Swim()` from an ill-fitting base); composition exposes only what you want.
- **Testability:** collaborators are injectable; base-class behavior is hard to mock (though `virtual` + `protected` testing is possible).
- **Favors small, focused classes** (SRP).

**When inheritance is still right:**

- Genuine IS-A with shared *code* you don't want to repeat (template method).
- You need to plug into a framework expecting a base (e.g., `BackgroundService`).
- Polymorphic substitution through a *stable* base.

**Composition techniques:**

- Constructor injection of collaborators (primary).
- Strategy objects passed to methods.
- Decorator wrappers adding behavior transparently.
- Facades grouping fine-grained collaborators.

### Real World Example (Healthcare)

Anti-pattern: `PatientRepository` inheriting from `BaseRepository` that has `Save`, `Log`, `Audit`, `Cache`... every specialization inherits a blob.

Pattern: compose:

```csharp
public sealed class PatientRepository : IPatientRepository
{
    private readonly IDbContext _db;        // persistence
    private readonly IAuditLogger _audit;   // auditing
    private readonly ICache _cache;         // caching
    private readonly IMetrics _metrics;     // observability
}
```

Each collaborator is separately testable and swappable (swap `ICache` for a no-op in tests).

### Production Code Example

```csharp
// Inheritance when it fits: template method (shared code is the point)
public abstract class FhirAuditDecoratorBase : IAuditSink
{
    private readonly IAuditSink _inner;
    protected FhirAuditDecoratorBase(IAuditSink inner) => _inner = inner;

    public async Task WriteAsync(AuditEntry entry, CancellationToken ct)
    {
        await PreWriteAsync(entry, ct);          // hook
        await _inner.WriteAsync(entry, ct);
    }
    protected abstract Task PreWriteAsync(AuditEntry entry, CancellationToken ct);
}

// Composition when it fits: capability assembly
public sealed class ClinicalNotificationCoordinator
{
    private readonly IEnumerable<INotificationChannel> _channels;  // sms, push, pager
    private readonly INotificationPriorityQueue _queue;
    private readonly IMetrics _metrics;

    public async Task DispatchAsync(ClinicalAlert alert, CancellationToken ct)
    {
        await _queue.EnqueueAsync(alert, ct);                        // reliability first
        foreach (var channel in _channels.OrderBy(c => c.Priority))  // composition
            await channel.TrySendAsync(alert, ct);
        _metrics.Count("clinical_alert_dispatched", 1, alert.Kind);
    }
}
```

**Key lines explained:**

- The *decorator* uses inheritance (`: IAuditSink`) to wrap another sink — inheritance for interface shape, composition for behavior.
- The coordinator *composes* channels, a queue, and metrics — no base class needed, infinitely extensible.

### Internal Working

- Composition is a *design-time* decision; at runtime it's just object references + method calls (delegation).
- Inheritance has *runtime* machinery: vtable slots, `base` calls. Composition is simpler at runtime (direct calls, easier inlining/devirtualization).

### Advantages

- Loose coupling, high cohesion.
- Unlimited capability combination.
- Easy mocking/DI.
- Smaller change blast radius.

### Disadvantages

- More indirection (many small collaborators).
- Sometimes verbose (constructor injection boilerplate — mitigated by DI containers).
- Delegation code ("forwarding methods") can be noisy.

### Best Practices

- Default to composition; reach for inheritance when IS-A + shared implementation is real.
- Favor the decorator for cross-cutting concerns (logging, retry, caching) — this is exactly how `IHttpClientFactory` handlers work.
- Keep collaborators behind interfaces so tests can substitute fakes.

### Common Mistakes

- Forcing inheritance ("I need to reuse that method") → composition or a shared helper is cleaner.
- Deep hierarchies ("Animal → Mammal → ... → Dog") that break on the first real requirement.
- Base classes with `protected` mutable state — a fragile-base ticking bomb.

### Interview Follow-up Questions

1. Name three patterns that are composition-based.
2. When is inheritance *clearly* the right call?
3. What is the fragile base class problem?
4. How does the Decorator pattern differ from inheritance-based extension?
5. Does composition always mean more classes? (Yes-ish — weigh against benefits.)

### Senior Level Talking Points

> "I treat 'inheritance or composition' as a *change-analysis* question: when the base changes, who pays? With inheritance, every derived class pays and might not know it. With composition, only the classes that actually use the collaborator pay. In a healthcare platform where audit, security, and clinical rules evolve constantly, I optimize for the cheapest change — and that's almost always composition."

### Memory Trick

**"Has-a beats is-a when the family tree would become a family web."**

---

## 2.6 Sealed Classes, Static Classes, and Partial Classes

### Interview Answer (30–45 seconds)

> "`sealed` prevents a class from being inherited — it's a design statement that this type is final, and it lets the JIT devirtualize and inline more aggressively. `static` classes can't be instantiated or inherited; they only contain static members and are used for utilities and extension-method containers. `partial` lets a type's definition be split across files — useful for designer-generated code, EF models, and code-generation boundaries. I seal most leaf classes, use static classes only for stateless utilities, and use `partial` mainly for generated code."

### Detailed Explanation

**`sealed`:**

- Prevents derivation. Cannot be used on interfaces/abstract classes.
- `sealed override` stops further overriding of a specific member.
- Performance: with a sealed type, the JIT can prove the exact type → devirtualize virtual calls → inline. A known hot-path trick.
- Design: signals "this is a finished contract" — great for DTOs, value objects, and domain leaves.

**`static` class:**

- All members static; no instance can exist; cannot derive.
- Implicitly `abstract` and `sealed` (that's why you can't instantiate or inherit).
- Used for: utility classes (`Math`, `FileHelpers`), extension-method containers, constant holders.
- Warning: static *state* is process-global → threading and testability hazards. Prefer DI for stateful services; static for pure functions.

**`partial`:**

- Splits a type (class, struct, interface, record) across files; all parts merge at compile time into one type.
- All parts must have the same accessibility and `partial` keyword.
- `partial` methods (private-ish): declaration in one part, optional implementation in another — if not implemented, the calls are *removed* (zero overhead). Great for code-gen hooks.
- Typical uses: `GeneratedCode` files, `#region` designer split, large models.

### Real World Example (Healthcare)

```csharp
public sealed class PatientRecord        // sealed: domain leaf
{
    public required string PatientId { get; init; }
    public required string Name { get; init; }
}

public static class FhirExtensions      // static: stateless helpers
{
    public static bool IsEmpty(this string? s) => string.IsNullOrWhiteSpace(s);
}

public partial class Observation         // partial: model + generated mapping
{
    public string? Category { get; set; }
}
public partial class Observation
{
    // EF or DTO-mapping generated part lives here
}
```

### Production Code Example

```csharp
// Hot path: sealed lets the JIT devirtualize
public sealed class FhirId
{
    private readonly string _value;
    public FhirId(string value) => _value = value;
    public override string ToString() => _value;
}

// Static utility (pure function — safe)
public static class ClinicalMath
{
    public static decimal BodyMassIndex(decimal weightKg, decimal heightCm)
    {
        if (heightCm <= 0) throw new ArgumentOutOfRangeException(nameof(heightCm));
        var hM = heightCm / 100m;
        return Math.Round(weightKg / (hM * hM), 1);
    }
}

// Partial method hook for generated code
public partial class AuditLogWriter
{
    partial void OnEntryWritten(AuditEntry entry);   // may be implemented elsewhere
    public void Write(AuditEntry entry)
    {
        OnEntryWritten(entry);   // call removed if unimplemented
        /* ... persist ... */
    }
}
```

**Key lines explained:**

- `sealed FhirId` — a value object; no one needs to extend it; JIT can treat calls as exact.
- `static ClinicalMath.BMI` — pure, deterministic, testable; no hidden state.
- `partial void OnEntryWritten(...)` — if the second part never implements it, the call site compiles to nothing.

### Internal Working

- `sealed` → metadata flag; JIT uses it to devirtualize (`tocall` instead of indirect vtable call).
- `static` → `abstract sealed` in metadata; no instance ctor.
- `partial` → purely a source-level merge; IL is a single type.

### Comparison Table

| Keyword | Instantiate? | Inherit? | Split files? | Use for |
|---|---|---|---|---|
| `sealed` | Yes | No | No | leaf types, final contracts |
| `static` | No | No | No | utilities, extensions |
| `partial` | Yes (as declared) | Yes | Yes | generated + hand-written parts |

### Best Practices

- Seal leaf types; seal `override`s you don't want extended.
- Use `static` only for stateless utilities; inject state via DI.
- Use `partial` where code-gen boundaries exist (EF, source generators, designer).
- Prefer `readonly struct` + `sealed class` for value objects.

### Common Mistakes

- `sealed` on a type you later need to mock in tests (mocking frameworks can't fake sealed — use interface instead).
- Static class with mutable static fields → global state bugs.
- Declaring `partial` on one part but forgetting the keyword on the other (compile error).

### Interview Follow-up Questions

1. Why do mocking frameworks dislike sealed classes? (They fake via proxy/inheritance or interface.)
2. What's the JIT benefit of `sealed`? (Devirtualization/inlining.)
3. Can a static class implement an interface? (No — but extension methods approximate.)
4. What happens if `partial void` is not implemented? (Call site removed.)
5. When would you split a class with `partial` in production? (Generated code boundaries.)

### Senior Level Talking Points

> "`sealed` is my default for value objects and leaf domain types — it's a cheap way to reclaim performance via devirtualization while making design intent explicit. `static` classes are fine for pure functions, but I'm allergic to static state in a service mesh — that's how 'works on one node' becomes 'mystery failure on the fleet.' And I keep `partial` out of hand-written code; it's for the boundary where machines write code."

### Memory Trick

**"sealed = final contract, static = no instances, partial = one type, many files."**

---

## 2.7 Cohesion and Coupling

### Interview Answer (30–45 seconds)

> "Cohesion is how strongly related the members of a module are; coupling is how strongly a module depends on others. High cohesion means a class does one well-defined job — its members belong together. Loose coupling means modules interact through small, stable contracts, so changing one doesn't ripple through the system. These two are the *true* quality metrics of a design — SOLID and the patterns are mostly means to this end. In healthcare systems, high coupling between clinical services is a patient-safety risk because a change in one place can silently break a care flow elsewhere."

### Detailed Explanation

**Coupling spectrum (from tight to loose):**

- **Content coupling** — one module reaches into another's internals (breaking encapsulation). Worst.
- **Common coupling** — shared global state (static mutable singletons). Bad for tests.
- **Control coupling** — passing flags that steer another module's behavior (`if (mode == "X")`).
- **Stamp coupling** — passing large structures and using part of them (passing the whole `Patient` to a method that only needs the DOB).
- **Data coupling** — passing only what's needed. Good.
- **Message coupling** — interacting through public methods with well-defined contracts. Good (a.k.a. decoupled-by-contract).

**Cohesion levels (from worst to best):**

- **Coincidental** — members grouped randomly ("misc utilities").
- **Logical** — similar *kinds* of things but unrelated ("string helpers", "validation").
- **Temporal** — grouped because they run at the same time (init everything).
- **Procedural** — grouped by procedure steps.
- **Communicational** — grouped because they operate on the same data.
- **Functional** — everything contributes to a single well-defined purpose. Best.

**The relationship:** coupling is what forces change in unrelated places; cohesion is what keeps related changes local. Improving one usually improves the other.

### Real World Example (Healthcare)

Bad: a `PatientService` that loads a patient, evaluates insurance eligibility, formats a summary, and emails it — *and* has a `mode` parameter that switches between "read" and "write" behavior. Control coupling + low cohesion.

Good:

```
PatientQueryService    ── reads patient (data coupling: PatientId in, PatientDto out)
InsuranceEligibility   ── data coupling (PatientDto + PlanId → Eligibility)
SummaryFormatter       ── functional cohesion
EmailDispatcher        ── message coupling via INotificationChannel
```

### Production Code Example

```csharp
// Loose coupling + high cohesion
public interface IPatientLookup
{
    Task<PatientDto?> GetAsync(string patientId, CancellationToken ct);  // narrow contract
}

public sealed class PatientDemographicsCoordinator
{
    private readonly IPatientLookup _patients;       // loose: depends on contract only
    private readonly IInsuranceGateway _insurance;   // loose
    private readonly INotifier _notifier;            // loose

    public PatientDemographicsCoordinator(
        IPatientLookup patients, IInsuranceGateway insurance, INotifier notifier)
    {
        _patients = patients;
        _insurance = insurance;
        _notifier = notifier;
    }

    public async Task NotifyEligibilityAsync(string patientId, CancellationToken ct)
    {
        var patient = await _patients.GetAsync(patientId, ct);       // data coupling
        var eligibility = await _insurance.CheckAsync(patient, ct);
        if (eligibility.Changed)
            await _notifier.SendAsync(patient, eligibility, ct);      // message coupling
    }
}
```

**Key lines explained:**

- Each dependency is a narrow contract (`IPatientLookup.GetAsync(string, ...)`) → data coupling, not stamp coupling.
- The coordinator is functionally cohesive: one purpose — notify on eligibility change.
- No flags, no globals, no internal-reaching.

### Advantages / Disadvantages

| Property | High | Low |
|---|---|---|
| Coupling | Loose (good) | Tight (bad) |
| Cohesion | High (good) | Low (bad) |
| Change cost | Local | Ripples |
| Testability | Easy seams | Hard to isolate |
| Comprehension | Clear | Opaque |

### Best Practices

- Measure with tests: if changing X requires touching Y, they're coupled.
- Pass exactly what a method needs (DTOs over raw entities; primitive params where possible).
- Keep cross-module communication contract-based (interfaces, messages).
- Aim for functional cohesion per class; don't create "misc" namespaces.

### Common Mistakes

- Control flags (`mode`, `type`) that steer behavior — extract strategies.
- Giant "service locator" classes that reach into everything (content coupling).
- Global static caches/dictionaries (common coupling).
- Passing entities where primitives suffice (stamp coupling).

### Interview Follow-up Questions

1. Name the coupling types and order them by severity.
2. How does high coupling hurt testing?
3. What does stamp coupling look like in practice?
4. Can you have high cohesion and high coupling? (Yes — one focused class coupled to many others.)

### Senior Level Talking Points

> "Cohesion and coupling are the *real* metrics behind every pattern I use — SOLID, interfaces, DI, hexagonal architecture are all in service of 'cohesive modules with narrow contracts.' At the system level this becomes the microservice boundary decision: a service boundary is correct when it captures a functional-cohesion boundary and minimizes coupling across it. In healthcare, where audit and consent cross every module, getting those boundaries right is literally a compliance decision."

### Memory Trick

**"Cohesion = how tight the family is; coupling = how many strings attach the boxes."**

---

## 2.8 Records vs. Classes for Domain Modeling

### Interview Answer (30–45 seconds)

> "Records give you value semantics by default: `with` expressions, structural equality, and a concise positional syntax — ideal for immutable DTOs, events, and API contracts. Classes are for types with identity, mutable state, and behavior — services, entities that change over time, anything the DB identity-follows. My rule: entities and services are classes; events, DTOs, and value objects are records. A clinical `Observation` with a DB id is a class; a `PatientAdmitted` event or an API `CreatePatientRequest` is a record."

### Detailed Explanation

**Record (`record class`):**

- Compiler generates: `IEquatable<T>`, value-based `Equals`/`GetHashCode`, `==`/`!=`, `ToString`, `with` expression support, `Deconstruct` (for positional), a copy constructor.
- Immutability is *conventional*: `init`-only properties (from positional params) unless you add settable ones — records do NOT enforce immutability.
- `with { }` — non-destructive mutation (copy-on-write).
- Inheritance works on records; `record struct` gives value-type storage.

**Class (reference type with mutable state):**

- Identity semantics — two instances with equal fields are still different *things* (e.g., two patient visits).
- EF Core tracks entities by reference identity; records-as-entities get weird (change tracking + value equality conflict).

**Domain decisions:**

| Type of thing | Choice | Why |
|---|---|---|
| API request/response DTO | `record` | value semantics, `with`, concise |
| Domain event | `record` | immutable, transportable, comparable |
| Value object (no identity) | `record` / `record struct` | equality by content |
| Entity (has identity) | `class` | change tracking, identity |
| Service / component | `class` | lifecycle, DI |

### Real World Example (Healthcare)

```csharp
// Entity: class with identity
public sealed class Patient
{
    public Guid Id { get; private set; } = Guid.NewGuid();
    public string MRN { get; private set; } = "";
    public string GivenName { get; private set; } = "";
    // behavior methods mutate state
    public void UpdateName(string given, string family) { GivenName = given; FamilyName = family; }
}

// Event/DTO: record
public sealed record PatientAdmitted(Guid PatientId, DateTimeOffset AdmittedAt, string Ward);
public sealed record CreatePatientRequest(string MRN, string GivenName, string FamilyName, DateOnly? Dob);
```

### Production Code Example

```csharp
// Value object: record struct with validation in factory
public readonly record struct Icd10Code
{
    public string Code { get; }
    private Icd10Code(string code) => Code = code;

    public static Icd10Code Parse(string input)
    {
        // ICD-10 pattern: letter + 2 digits + optional extension (e.g., E11.9)
        if (input is { Length: >= 3 } && char.IsLetter(input[0]))
            return new Icd10Code(input);
        throw new FormatException($"Invalid ICD-10 code: {input}");
    }
}

// Using `with` for audit-correct updates (no mutation of the original)
var updated = patientDemographics with { GivenName = "Ana Sofia" };
```

**Key lines explained:**

- `readonly record struct` + private ctor + static factory → invariant enforced ("a valid ICD-10 code exists only as a valid code").
- `with` produces a new instance — the original is untouched (important when a DTO was already dispatched to a downstream system).
- Entity as `class` with behavior methods keeps change-tracking friendly for EF Core.

### Internal Working

- `record` emits a copy constructor (`protected Record(Record original)`) used by `with`.
- Value equality walks properties via generated `EqualityContract` checks + per-property comparers.
- Records still allocate on the heap (they're reference types); `record struct` avoids that.

### Advantages

- Records: concise, correct equality, `with`, printer-friendly `ToString`.
- Classes: mutable state, identity, lifecycle, familiar change tracking.

### Disadvantages

- Records: immutability is not enforced; equality on large graphs is expensive; `with` copies everything.
- Classes: equality-by-default is identity (surprise if you expected value semantics); mutable state = threading concerns.

### Best Practices

- DTOs, events, commands, queries → `record`.
- Entities → `class` with encapsulated mutation.
- Value objects → `readonly record struct` with factory validation.
- Don't use `record` for EF entities unless you understand change-tracking implications.

### Common Mistakes

- Making EF entities `record` and hitting "value equality broke change tracking" bugs.
- Expecting `record` to be truly immutable (init-only is not enforced).
- `record struct` used where large (copy cost).

### Interview Follow-up Questions

1. Is a `record` immutable by design? (Conventional; `init` only — not enforced.)
2. What does `with` compile to? (Copy constructor + field assignment.)
3. `record class` vs `record struct` for a DTO? (class for large DTOs, struct for small value objects.)
4. When is a domain entity better as a class? (Identity + mutation + change tracking.)

### Senior Level Talking Points

> "The modern line: *events, commands, and contracts are records; entities and services are classes.* The reason isn't taste — it's that value equality and `with` semantics map perfectly to immutable, transmittable messages, while identity and change tracking map to mutable entities. In a FHIR-heavy system the domain boundary is exactly this: resources you transmit are records, entities you persist and mutate are classes. Getting this wrong produces equality bugs in event replay or change-tracking bugs in persistence — both are nasty, expensive clinical bugs."

### Memory Trick

**"Events travel (records); entities persist (classes)."**

---

## Chapter 2 Wrap-Up

### Top 10 Interview Questions From This Chapter

1. Explain the four pillars of OOP with C# examples.
2. What is the difference between encapsulation and abstraction?
3. Explain SOLID and give a healthcare example of each principle.
4. When should you use an interface vs. an abstract class?
5. Overloading vs. overriding — how does each work under the hood?
6. What is the fragile base class problem?
7. Composition over inheritance — when does inheritance still win?
8. Why are sealed types faster? When does the JIT devirtualize?
9. What is high cohesion and loose coupling, and how do you measure them?
10. Record vs. class — when do you use each in domain modeling?

### Revision Notes (1 page)

- **Pillars:** Encapsulation hides state (private + properties); Abstraction exposes contracts (interfaces); Inheritance = IS-A + code reuse, single base; Polymorphism = compile-time (overload) + runtime (virtual/interface dispatch via vtable).
- **SOLID:** S — one reason to change; O — extend without modifying (strategies, template method); L — subtype substitution must not break contracts; I — no fat interfaces; D — depend on abstractions, inject details.
- **Interface vs abstract:** interface = capability contract, many per type, no state; abstract = shared implementation + state, one base. Prefer interfaces for seams/DI; abstract classes for template methods.
- **Polymorphism internals:** overloads resolved at compile time (most-specific match); overrides via vtable (runtime type). `new`-hiding is static — a Base reference calls the Base version.
- **Composition over inheritance:** inheritance couples to base internals and caps you at one ancestry; composition delegates to injectable collaborators. Inheritance still right for template methods and framework bases (`BackgroundService`).
- **sealed/static/partial:** sealed = final + devirtualizable; static = no instances, stateless utilities only; partial = split source across files, `partial void` hooks get removed if unimplemented.
- **Cohesion/coupling:** functional cohesion (members serve one purpose) + loose coupling (narrow contracts) are the true quality targets; tight forms = content/common/control coupling; loose forms = data/message coupling.
- **Records vs classes:** records = value semantics, `with`, structural equality → DTOs/events/value objects; classes = identity + mutation → entities/services. `readonly record struct` + factory = validated value objects.

### Things Interviewers Expect From 5+ Years Experience

- You can defend design decisions with tradeoffs, not just recite definitions.
- You know when *not* to apply a principle (over-abstraction, interface-everything, record-everything).
- You connect OOP to framework mechanics: DI, EF change tracking, JIT devirtualization.
- You model healthcare domain types correctly: entities vs. events vs. DTOs vs. value objects.
- You articulate that SOLID is in service of cohesion/coupling, not an end in itself.

### Cheat Sheet

```
PILLARS:  Encapsulate(hide)  Abstract(contract)  Inherit(IS-A)  Polymorph(dispatch)

SOLID:    S one reason  O extend-don't-modify  L substitutable
          I small interfaces  D depend on abstractions

Interface/Abstract:
  capability + many per type + no state      → interface
  shared implementation + IS-A hierarchy     → abstract class
  (default interface methods = versioning tool, not design tool)

Dispatch:
  overload  → compile time (most specific)
  override  → runtime vtable
  new-hide  → static (!! Base ref calls Base member)

Inheritance is right when:
  template method, framework base, genuine IS-A with shared code
Otherwise: compose (constructor-inject collaborators)

sealed   → final + JIT devirtualization
static   → stateless utilities only (no global state!)
partial  → generated/hand-written split; partial void removes if unimplemented

Coupling:  content > common > control > stamp > data > message (loose=good)
Cohesion:  coincidental < logical < temporal < procedural < communicational < functional

RECORD = value semantics  → DTO / event / value object
CLASS  = identity + state → entity / service
```

### Flash Cards

**Q1:** Which pillar hides state from callers? **A:** Encapsulation (private fields + property guards).

**Q2:** LSP violation example? **A:** `Square : Rectangle` changing width also changes height.

**Q3:** Abstract class with only abstract members — why not interface? **A:** Single-inheritance slot consumed; better to use interface.

**Q4:** `new` keyword vs `override`? **A:** `new` hides (static dispatch); `override` participates in vtable (dynamic).

**Q5:** Why sealed enables devirtualization? **A:** JIT proves exact type → replaces indirect call with direct call.

**Q6:** What is common coupling? **A:** Modules sharing global mutable state.

**Q7:** A FHIR `Observation` entity → record or class? **A:** Class (identity + mutation); its `Quantity` value object → record struct.

**Q8:** What does `with` compile to? **A:** Copy constructor + field/property assignment (new instance).

**Q9:** Template method pattern — inheritance or composition? **A:** Inheritance (shared skeleton, polymorphic hooks).

**Q10:** Strategy pattern — how is it OCP? **A:** Adding a strategy = new class, no modification of the context.

### Interview Confidence Score

**Medium.** Every interviewer asks at least one OOP/SOLID question. The differentiator for senior candidates is concrete examples from real systems and an honest discussion of tradeoffs — memorized definitions alone land at "junior."

---

*Continue → Chapter 3: Advanced C#*
