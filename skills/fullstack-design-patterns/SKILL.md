---
name: fullstack-design-patterns
description: Guide, evaluate, and architect fullstack applications covering modern Frontend UI component design, state management, and robust Backend architecture. Use when designing end-to-end features, refactoring component hierarchies, decoupling API/data access layers, reviewing PRs for architectural debt, or solving frontend-backend integration friction.
---

# Fullstack Design Patterns Guide

Use this skill to advise, architect, and refactor end-to-end fullstack systems. Apply patterns strictly to solve identifiable architectural friction, not for speculative abstraction.

## Core Principles

1. **Problem-First Selection:** Never introduce a design pattern without an explicit architectural friction or code smell (e.g., prop drilling, bloated god-components, tight API coupling, untestable logic, cascading network failures).
2. **Clear Architectural Seams:** Maintain clear boundaries between:
   - **View / Presentation:** Dumb, declarative components driven by props.
   - **Client State & Interaction:** Headless hooks, centralized stores, and server-state caching.
   - **API / Contract Layer:** Typed schemas, DTO adapters, and anti-corruption layers.
   - **Domain & Data Access:** Decoupled business rules and repository-backed database access.
3. **Avoid Over-Engineering:** Do not apply complex enterprise abstractions (like micro-frontends, CQRS, or distributed pub/sub) to simple CRUD pages or standard web apps.

---

## Pattern Decision Matrix & Trigger Heuristics

| Layer | Symptom / Friction in Codebase | Recommended Pattern | Architectural Seam |
| :--- | :--- | :--- | :--- |
| **Frontend UI** | God-component mixing API fetching, formatting, and JSX layout | **Container / Presentational** | Separate UI rendering from data fetching |
| **Frontend UI** | Tightly coupled styling inside interactive components (modals, dropdowns) | **Headless Component / Custom Hooks** | Isolate state and keyboard/interaction logic |
| **Frontend UI** | Rigid component APIs needing flexible sub-elements | **Compound Components** | Declarative parent-child state sharing (e.g., Tabs, Select) |
| **Frontend UI** | Deep prop drilling or out-of-sync multi-component UI states | **Observer / Store (Zustand/Redux/Context)** | Centralize shared client state |
| **Fullstack API** | Backend API schema changes break frontend UI components | **Adapter Pattern (Data Mapper)** | Anti-Corruption Layer translating DTO to View Model |
| **Fullstack API** | UI waits on slow networks before confirming user action | **Optimistic UI with Rollback** | Immediate UI response backed by transactional rollback |
| **Backend** | SQL/ORM calls scattered inside route handlers or services | **Repository Pattern** | Decouple persistence queries from business rules |
| **Backend** | Instantiating different third-party SDKs using inline `if-else` | **Factory Pattern** | Centralize object and client creation |
| **Backend** | Cascading `if-else` / `switch` computing pricing, auth, or algorithms | **Strategy Pattern** | Encapsulate interchangeable algorithms behind an interface |
| **Backend / Distributed** | Core business action triggers 5+ unrelated side-effects | **Observer / Event-Driven (Pub/Sub)** | Decouple side-effects via domain events or message queues |
| **Backend / Distributed** | External API latency causing thread starvation and cascading downtime | **Circuit Breaker** | Fast-fail, fallback response, and downstream health probing |

---

## Deep Dive: Fullstack Patterns & Implementation Rules

### 1. Frontend: Container / Presentational Pattern
* **Context:** Components growing beyond 200 lines by combining `useEffect`, queries, data transformations, and layout JSX.
* **Rules:**
  - **Presentational Component:** Receives data and callbacks via props only; pure, easily testable in Storybook without API mocks.
  - **Container (or Page Hook):** Fetches server data, manages loading/error states, and passes transformed data down.

### 2. Frontend: Headless Component & Custom Hook Pattern
* **Context:** Complex interactive behaviors (autocomplete, multi-step wizards, accordion) requiring reuse across different visual designs.
* **Rules:**
  - Extract state, keyboard handlers, and ARIA attributes into a headless custom hook (e.g., `useAutocomplete`, `useDisclosure`).
  - Keep styling and DOM markup completely in the consumer's hands.

### 3. Frontend: Compound Components
* **Context:** Components with deeply related sub-parts needing cohesive internal state without passing dozens of configuration props.
* **Rules:**
  - Leverage React Context to communicate implicitly between parent and child (`<Accordion><Accordion.Item /><Accordion.Panel /></Accordion>`).

### 4. Integration: Adapter Pattern (Anti-Corruption Layer)
* **Context:** Third-party REST/GraphQL payloads leaking directly into UI component props or core domain models.
* **Rules:**
  - Never let raw backend DTO keys dictate frontend component prop shapes.
  - Create explicit mapper functions (e.g., `toUserViewModel(dto: UserApiDto): UserVM`) to shield UI components from schema shifts.

### 5. Integration: Optimistic UI with Rollback
* **Context:** Frequent user interactions (likes, toggles, task completion, reordering) where network latency harms responsiveness.
* **Rules:**
  - Update local state immediately on interaction.
  - Queue server mutation; if it rejects, rollback to the previous snapshot and notify the user non-intrusively.

### 6. Backend: Repository Pattern
* **Context:** Business logic intertwined with ORM queries (Prisma, TypeORM, Drizzle, SQL).
* **Rules:**
  - Services interact solely with an interface (e.g., `OrderRepository`).
  - Keep domain logic out of repositories; keep query building out of services.

### 7. Backend: Strategy & Factory Patterns
* **Context:** Swappable providers (payment gateways, notification channels, file storage).
* **Rules:**
  - Standardize behavior through a common interface (`PaymentGateway`).
  - Use a Factory/Registry to resolve concrete implementations based on configuration or tenant.

### 8. Backend: Circuit Breaker Pattern
* **Context:** External microservices or third-party APIs suffering intermittent downtime or severe latency.
* **Rules:**
  - Track failure thresholds. Transitions: `Closed` (normal) -> `Open` (fast-fail, return cached/fallback) -> `Half-Open` (canary probe).

---

## Agent Output Workflow

When asked to advise on architecture or refactor fullstack code:
1. **Identify the Seam & Bottleneck:** Pinpoint whether friction lies in UI rendering, state synchronization, API contract mismatch, or backend coupling.
2. **Select the Matching Pattern:** Propose the pattern with a clear rationale addressing the specific code smell.
3. **Provide Before / After Examples:** Provide concise, idiomatic code snippets demonstrating decoupled responsibilities.
4. **Highlight Testability & Maintainability:** Explain how the refactoring simplifies unit/component testing and shields against future changes.
