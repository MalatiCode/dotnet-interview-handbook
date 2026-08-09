# The Complete .NET Interview Handbook

**For Experienced .NET Developers (5+ Years) Targeting L2 (Mid/Senior) Roles in Healthcare**

A professional, publishing-grade technical book covering every topic a Mid/Senior .NET developer must master before a healthcare software engineering interview. Written in the voice of an experienced architect, this handbook goes beyond interview questions: it teaches concepts the way senior engineers think about them.

---

## How To Use This Book

- Study chapters in order for a structured 6–8 week plan, or jump directly to weak areas.
- Every question is answered in a 30–45 second "Interview Answer" plus a deep-dive explanation with enterprise healthcare examples, production code, internal workings, tradeoffs, and senior-level talking points.
- Drill with the Flash Cards at the end of each chapter.
- Practice coding problems in Chapter 40 in a real environment (LeetCode style, but with production-grade solutions).

## Table of Contents

| # | Chapter | File |
|---|---------|------|
| 1 | C# Fundamentals | [chapters/01-csharp-fundamentals.md](chapters/01-csharp-fundamentals.md) |
| 2 | Object-Oriented Programming | [chapters/02-oop.md](chapters/02-oop.md) |
| 3 | Advanced C# | [chapters/03-advanced-csharp.md](chapters/03-advanced-csharp.md) |
| 4 | LINQ | [chapters/04-linq.md](chapters/04-linq.md) |
| 5 | Collections | [chapters/05-collections.md](chapters/05-collections.md) |
| 6 | Memory Management & Garbage Collection | [chapters/06-memory-management-gc.md](chapters/06-memory-management-gc.md) |
| 7 | Multithreading | [chapters/07-multithreading.md](chapters/07-multithreading.md) |
| 8 | Dependency Injection | [chapters/08-dependency-injection.md](chapters/08-dependency-injection.md) |
| 9 | ASP.NET Core | [chapters/09-aspnet-core.md](chapters/09-aspnet-core.md) |
| 10 | Middleware | [chapters/10-middleware.md](chapters/10-middleware.md) |
| 11 | Authentication & Authorization | [chapters/11-authentication-authorization.md](chapters/11-authentication-authorization.md) |
| 12 | JWT & OAuth | [chapters/12-jwt-oauth.md](chapters/12-jwt-oauth.md) |
| 13 | Entity Framework Core | [chapters/13-entity-framework-core.md](chapters/13-entity-framework-core.md) |
| 14 | SQL Server | [chapters/14-sql-server.md](chapters/14-sql-server.md) |
| 15 | Performance Optimization | [chapters/15-performance-optimization.md](chapters/15-performance-optimization.md) |
| 16 | Caching | [chapters/16-caching.md](chapters/16-caching.md) |
| 17 | Logging & Monitoring | [chapters/17-logging-monitoring.md](chapters/17-logging-monitoring.md) |
| 18 | Docker | [chapters/18-docker.md](chapters/18-docker.md) |
| 19 | Kubernetes | [chapters/19-kubernetes.md](chapters/19-kubernetes.md) |
| 20 | Redis | [chapters/20-redis.md](chapters/20-redis.md) |
| 21 | RabbitMQ | [chapters/21-rabbitmq.md](chapters/21-rabbitmq.md) |
| 22 | Kafka | [chapters/22-kafka.md](chapters/22-kafka.md) |
| 23 | SignalR | [chapters/23-signalr.md](chapters/23-signalr.md) |
| 24 | gRPC | [chapters/24-grpc.md](chapters/24-grpc.md) |
| 25 | Background Services | [chapters/25-background-services.md](chapters/25-background-services.md) |
| 26 | Clean Architecture | [chapters/26-clean-architecture.md](chapters/26-clean-architecture.md) |
| 27 | Repository Pattern | [chapters/27-repository-pattern.md](chapters/27-repository-pattern.md) |
| 28 | Unit of Work | [chapters/28-unit-of-work.md](chapters/28-unit-of-work.md) |
| 29 | MediatR | [chapters/29-mediatr.md](chapters/29-mediatr.md) |
| 30 | Microservices | [chapters/30-microservices.md](chapters/30-microservices.md) |
| 31 | API Design | [chapters/31-api-design.md](chapters/31-api-design.md) |
| 32 | API Versioning | [chapters/32-api-versioning.md](chapters/32-api-versioning.md) |
| 33 | Swagger | [chapters/33-swagger.md](chapters/33-swagger.md) |
| 34 | Rate Limiting | [chapters/34-rate-limiting.md](chapters/34-rate-limiting.md) |
| 35 | Health Checks | [chapters/35-health-checks.md](chapters/35-health-checks.md) |
| 36 | Serilog | [chapters/36-serilog.md](chapters/36-serilog.md) |
| 37 | Polly | [chapters/37-polly.md](chapters/37-polly.md) |
| 38 | Security | [chapters/38-security.md](chapters/38-security.md) |
| 39 | Healthcare Best Practices | [chapters/39-healthcare-best-practices.md](chapters/39-healthcare-best-practices.md) |
| 40 | Common Interview Coding Problems | [chapters/40-interview-coding-problems.md](chapters/40-interview-coding-problems.md) |
| 41 | System Design | [chapters/41-system-design.md](chapters/41-system-design.md) |
| 42 | Behavioral Questions | [chapters/42-behavioral-questions.md](chapters/42-behavioral-questions.md) |

## Repository Layout

```
dotnet-interview-handbook/
├── README.md               # You are here
├── chapters/               # One Markdown file per chapter
├── images/                 # Static images (logos, screenshots)
├── diagrams/               # ASCII + Mermaid source diagrams
├── code/                   # Runnable C# examples referenced in chapters
└── build/                  # PDF build output (combined.md + handbook.pdf)
```

## How The PDF Is Produced

1. Chapters are authored as maintainable, version-controlled Markdown.
2. A build script concatenates chapters in order into `build/combined.md`.
3. `pandoc` (with a professional template) converts `combined.md` into a single professionally formatted PDF.

## Healthcare Context

All enterprise examples in this book draw from real healthcare systems:

- **FHIR** (Fast Healthcare Interoperability Resources) for patient data exchange
- **HL7 v2** for legacy messaging
- **HIPAA / HITECH** (US) and **GDPR** (EU) compliance requirements
- **PHI/PII** (Protected Health Information / Personally Identifiable Information)
- **DICOM** for imaging data
- Audit logging, data retention, and ePHI-at-rest/in-transit encryption
- High-availability requirements for clinical systems (patient safety is non-negotiable)

---

## Authoring Status

Each chapter is released one at a time. Type **"Continue"** to receive the next chapter.

- [x] Structure & README
- [x] Chapters 1–42 (complete)

---

## License

Personal study material. For individual preparation use only.
