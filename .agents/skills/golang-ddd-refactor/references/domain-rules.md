# Domain Rules

## Rule 1: Reflect Business Logic Literally

- Model behavior with business verbs such as `ScheduleTraining`, `CancelTraining`, `ApproveReschedule`.
- Prefer types with behavior over passive data containers with setters and getters.
- Ask whether a non-technical stakeholder could roughly understand the important method names.

## Rule 2: Keep A Valid State In Memory

- Validate invariants at construction time when possible.
- Keep fields private if direct mutation would bypass business rules.
- Make illegal state transitions impossible or at least explicit.
- Favor behavior methods over sequences of `if` checks in calling code.

## Rule 3: Keep The Domain Database-Agnostic

- Do not let Firestore, SQL, protobuf, or JSON tags define the shape of the domain.
- Create persistence models when storage and business needs diverge.
- Defer database decisions when the domain is still being discovered.

## Signs The Domain Is Missing

- Handlers or repositories contain large validation trees.
- Repositories know too much about business rules.
- The same struct is tagged for database and transport and also carries business logic.
- Tests need running infrastructure just to verify basic business behavior.

## Helpful Test Style

- Test exported behavior as a black box.
- Use table-driven tests for corner cases.
- Use domain-specific helpers to make scenarios readable.
- Keep domain tests free of mocks and infrastructure.
