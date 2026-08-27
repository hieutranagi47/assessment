# Infra And Delivery

## Principles

- Infrastructure exists to support architecture, not replace it.
- Keep infrastructure configuration in version control.
- Prefer declarative definitions and reusable modules over manual console changes.

## Patterns That Fit This Style

- Terraform manages project, APIs, Cloud Run services, and related wiring.
- Repeated Cloud Run service setup is wrapped in a Terraform module.
- Service-to-service addresses are passed as explicit environment variables.
- Explicit Terraform dependencies are used when provider-level defaults hide ordering.

## Cloud Run Style

- Separate public HTTP and internal gRPC exposure when their concerns differ.
- Keep auth configuration explicit instead of assuming defaults.
- Keep service wiring obvious through configuration and outputs.

## CI And Delivery

- Put tests in the pipeline early, before the project quietly drifts.
- Avoid a pipeline where tests are so slow or flaky that people stop trusting them.
- Keep local and CI environments close enough that adapter-level tests remain realistic.

## Good Review Questions

- Can the environment be reproduced from code?
- Are permissions explicit and scoped?
- Is service discovery visible in configuration?
- Can one service be validated without a full integrated environment when it should be?
