---
name: backend-design-patterns
description: Guide and evaluate backend architecture and code design using 10 proven backend design patterns (Repository, Factory, Singleton, Strategy, Observer, Builder, Adapter, Decorator, CQRS, Circuit Breaker). Use when designing backend services, refactoring tangled logic, reviewing PRs for architectural debt, resolving coupling issues, or decoupling business logic from third-party integrations and databases.
---

# Backend Design Patterns Guide

Use this skill to advise, refactor, and architect backend systems. Apply patterns strictly to solve identifiable architectural friction, not for speculative abstraction.

## Core Principles

1. **Problem-First Selection:** Never introduce a design pattern without an explicit architectural friction or code smell (e.g., tight coupling, cascading failure risk, untestable logic).
2. **The Reliability Standard:** Working code is only the starting line. All architectural recommendations must satisfy:
   - **Understandable:** Single Responsibility and clear boundaries.
   - **Testable:** Decoupled dependencies allow mocking/isolation.
   - **Reliable:** Resilience against cascading failures and traffic spikes.
3. **Avoid Over-Engineering:** Do not apply complex enterprise patterns (like CQRS or Event Streaming) to simple CRUD domains.

---

## Pattern Decision Matrix & Trigger Heuristics

| Symptom / Friction in Codebase | Recommended Pattern | Architectural Seam |
| :--- | :--- | :--- |
| SQL queries / ORM calls mixed in Controllers or Services | **Repository Pattern** | Decouple Data Access from Domain Logic |
| Instantiating different third-party SDKs using inline conditionals | **Factory Pattern** | Centralize Object Creation |
| Repeatedly recreating costly shared managers (config, cache, logger) | **Singleton Pattern** | Enforce single instance via DI container |
| Cascading `if-else` or `switch-case` computing rules/algorithms | **Strategy Pattern** | Isolate swappable algorithms behind an interface |
| A core domain service directly triggers 5+ unrelated downstream actions | **Observer Pattern** | Decouple using domain events (Pub/Sub, Brokers) |
| Constructors with 8+ parameters or many optional parameters | **Builder Pattern** | Step-by-step fluent construction |
| Third-party API schemas/types leaking into internal core logic | **Adapter Pattern** | Anti-Corruption Layer / Translator |
| Service classes bloated with Logging, Caching, Auditing, or Auth | **Decorator Pattern** | Wrap service or leverage Framework Middleware |
| Massive read traffic degrading write performance, or mismatched models | **CQRS** | Separate Command (Write) from Query (Read) models |
| External HTTP/RPC dependency latency causing thread starvation | **Circuit Breaker** | Fail fast, return fallback, protect main threads |

---

## Deep Dive: The 10 Patterns & Implementation Rules

### 1. Repository Pattern
* **Context:** Separates data mapping and queries from core business workflows.
* **Rules:**
  - Controllers/Services must interact with an interface (e.g., `UserRepository`), never raw DB drivers or concrete ORM contexts directly.
  - Keep domain logic out of repositories; keep query semantics out of services.
* **Test Seam:** The repository must be mockable with an in-memory substitute for fast unit testing.

### 2. Factory Pattern
* **Context:** Decouples caller code from specific provider subclasses (e.g., Stripe, PayPal, Razorpay).
* **Rules:**
  - Callers request an abstraction (e.g., `PaymentGateway`) via a factory method or registry.
  - Adding a new provider must only require adding the new class and updating the factory registration (Open/Closed Principle).

### 3. Singleton Pattern
* **Context:** Shared lifecycle resources (e.g., Configuration, Cache Client, Loggers).
* **Rules:**
  - Prefer Framework-level Dependency Injection (DI) scopes (e.g., NestJS `@Injectable()`, Spring `@Singleton`, ASP.NET Core `AddSingleton`).
  - Do not hide dependencies in static state; inject the singleton via constructor.

### 4. Strategy Pattern
* **Context:** Interchangeable algorithms (e.g., discount calculations, shipping rates, auth strategies).
* **Rules:**
  - Encapsulate each algorithm variant into its own class implementing a shared interface.
  - The context class delegates execution to the selected strategy.

### 5. Observer Pattern (Event-Driven)
* **Context:** Side-effects after state changes (e.g., `OrderPlaced` -> send email, update inventory, notify CRM).
* **Rules:**
  - The producer emits a typed Event and immediately finishes its primary responsibility.
  - Use message brokers (Kafka, RabbitMQ, SNS/SQS, Pub/Sub) for inter-service communication, or internal event emitters for intra-process dispatch.

### 6. Builder Pattern
* **Context:** Complex object construction with numerous optional properties.
* **Rules:**
  - Provide a fluent chaining API (`.setName().setEmail().build()`).
  - Validate invariants and required fields inside `.build()`.

### 7. Adapter Pattern
* **Context:** Third-party integrations or legacy systems with differing schemas/formats.
* **Rules:**
  - Acts as a translator layer. Internal codebase must never directly reference third-party DTOs.
  - If the external vendor updates their API version, only the Adapter class changes.

### 8. Decorator Pattern
* **Context:** Cross-cutting concerns (Caching, Logging, Metrics, Rate-limiting, Retries).
* **Rules:**
  - Wrap the target interface with identical methods, executing extra behavior before/after delegating to the wrapped instance.
  - In modern web backends, prioritize idiomatic middleware, interceptors, or decorators provided by the framework.

### 9. CQRS (Command Query Responsibility Segregation)
* **Context:** High-throughput systems where read access vastly outnumbers writes or requires denormalized views.
* **Rules:**
  - Commands mutate state (void return or ID return only); Queries fetch data without side effects.
  - **Anti-Pattern Warning:** Strictly DO NOT recommend CQRS for standard CRUD applications. Only suggest it when high load or complex projections justify the overhead.

### 10. Circuit Breaker Pattern
* **Context:** Distributed systems and microservices subject to remote network failures or cascading latency.
* **Rules:**
  - Track failure counts/rates. Transitions:
    - `Closed`: Normal traffic flows.
    - `Open`: Fast-fail immediately, return cached/fallback responses.
    - `Half-Open`: Route canary requests to test downstream health before fully closing.
  - Recommend standard libraries (e.g., Resilience4j, Polly, or service mesh configurations like Istio/Envoy).

---

## Agent Output Workflow

When asked to advise on an architecture or refactor code:
1. **Assess the Problem & Context:** Identify bottlenecks (coupling, testing friction, cascading failure).
2. **Propose the Pattern:** State the matching pattern from the 10 Backend Patterns with rationale.
3. **Illustrate Before / After:** Show concise code snippets highlighting the seam separation.
4. **Evaluate Testability & Longevity:** Explain how this refactor improves unit testing and protects the system under scaling.
