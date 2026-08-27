# CQRS Guidelines

## Core Rules

- A command changes state and may return an error.
- A query reads state and should not perform business mutations.
- Split read and write models when it reduces complexity or coupling.
- Treat CQRS as a pragmatic structural tool, not a mandatory architecture religion.

## Naming

- Use business names, not CRUD defaults.
- Prefer `ScheduleTraining` over `CreateTraining`.
- Prefer `CancelTraining` over `DeleteTraining`.
- Prefer query names that describe the information being asked for, not the storage mechanism.

## Packaging

Common layout:

```text
internal/trainings/app/
  command/
  query/
```

- Keep one handler per command or query when dependencies or rules differ.
- Let each handler define the interfaces it needs.
- Let ports call the relevant handler directly instead of routing everything through one wide service type.

## When CQRS Helps

- One application service has too many unrelated methods.
- Write rules are complex but reads are simple and numerous.
- Commands and queries need different dependencies or models.
- Tests are painful because every use case depends on a wide shared interface.

## When CQRS Is Probably Too Much

- The service is plain CRUD with little behavior.
- Authorization or login is the main concern and command/query separation adds no clarity.
- Separate packages would only add indirection without shrinking complexity.

## Useful Extensions

- Asynchronous command buses for slow commands.
- Separate query storage when read performance or filtering needs diverge.
- Event-driven synchronization when you accept eventual consistency.

Add those only when the simpler synchronous setup is no longer enough.
