---
goal: Separate developer instructions from end-user README content
version: 1.0
date_created: 2026-09-30
last_updated: 2026-09-30
owner: etnt
status: 'Completed'
tags: [refactor, documentation]
---

# Introduction

![Status: Completed](https://img.shields.io/badge/status-Completed-brightgreen)

Move app development, build, test, architecture, and release guidance from `README.md` to `DEVELOPERS.md`, while keeping end-user instructions in the README.

## 1. Requirements & Constraints

- **REQ-001**: Keep app overview, screenshots, operation instructions, installation guidance, free-versus-premium information, and license information in `README.md`.
- **REQ-002**: Move technical architecture, dependencies, development setup, device setup, testing, simulator, and signing instructions to `DEVELOPERS.md`.
- **REQ-003**: Link `DEVELOPERS.md` from `README.md`.
- **CON-001**: Preserve existing development instructions without changing their meaning.
- **GUD-001**: Use clear section headings and relative links within the repository.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Separate end-user and developer documentation.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Move technical and contributor sections from `README.md` into `DEVELOPERS.md`, retaining free-versus-premium information in the README. | ✅ | 2026-09-30 |
| TASK-002 | Add a README link to `DEVELOPERS.md` and retain user-facing app instructions, downloads, and license details. | ✅ | 2026-09-30 |
| TASK-003 | Review both documents for retained content, correct links, and clear audience separation. | ✅ | 2026-09-30 |

## 3. Alternatives

- **ALT-001**: Keep all content in one README; not selected because developer setup obscures user instructions.

## 4. Dependencies

- **DEP-001**: No package or runtime dependencies.

## 5. Files

- **FILE-001**: `README.md` — retain end-user content and link to developer documentation.
- **FILE-002**: `DEVELOPERS.md` — hold development, build, test, and release guidance.
- **FILE-003**: `plan/refactor-readme-developers-1.md` — track this documentation refactor.

## 6. Testing

- **TEST-001**: Inspect the README to confirm it contains user-facing content and a working relative link to `DEVELOPERS.md`.
- **TEST-002**: Inspect `DEVELOPERS.md` to confirm moved development instructions remain present and readable.

## 7. Risks & Assumptions

- **RISK-001**: Cutting and pasting sections can omit text; compare both resulting documents with the original README content.
- **ASSUMPTION-001**: The existing README's user-operation and installation guidance remains useful to app users.

## 8. Related Specifications / Further Reading

- [My Football README](../README.md).
- [Developer guide](../DEVELOPERS.md).
