# Contributing

## Principles

1. Keep public behavior equivalent across Go, Java, Node, Python, PHP, and .NET.
2. Do not add a status without updating `spec/event.schema.json`, `docs/data-model.md`, and all SDKs.
3. Do not hard-code real credentials or patient data.
4. Prefer backward-compatible changes.
5. Add tests for retry/error classification changes.

## Branch / PR

- Create a feature branch.
- Update tests and documentation.
- Run the relevant SDK test command.
- Explain migration impact in the pull request.

## Versioning

Semantic Versioning is recommended:

- PATCH: bugfix/internal change;
- MINOR: backward-compatible feature;
- MAJOR: breaking SDK contract/schema change.
