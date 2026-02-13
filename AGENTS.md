# iOS Engineering Rules (umaptest + IMap)

These rules apply to all work in this repository. They are intentionally strict to keep the app production-grade.

## 1) Architecture and Boundaries

- Keep `umaptest` app code focused on product flow and UI composition.
- Keep reusable map logic in `IMap/Sources/MapPack`; do not leak app-specific behavior into the package.
- Depend on protocols at boundaries (`providers`, `services`, `managers`) and inject dependencies for testability.
- Keep files small and cohesive:
  - One primary type per file.
  - Split files once a type starts owning multiple responsibilities.

## 2) Swift and API Design

- Follow Swift API Design Guidelines.
- Prefer value types (`struct`, `enum`) unless reference semantics are required.
- Prefer `final` for classes that are not designed for inheritance.
- Ban unsafe shortcuts in production code:
  - No `try!`
  - No `as!`
  - No force unwraps (`!`) except in tightly controlled test code
- Favor explicit naming over comments that restate code.

## 3) Concurrency and Thread Safety

- UI-facing view models and view state updates must run on `@MainActor`.
- Use structured concurrency (`Task`, task groups); avoid detached tasks unless there is a clear lifecycle owner.
- Handle task cancellation for long-running operations.
- Do not block the main thread with heavy parsing, IO, or geometry calculations.

## 4) Errors, Logging, and Observability

- Model failure states explicitly with typed errors.
- Surface recoverable failures to callers; do not swallow errors silently.
- Use `Logger`/`os_log` for runtime diagnostics in production paths.
- Avoid `print` in shipped code.

## 5) Security and Privacy

- Never commit secrets, API keys, or tokens.
- Store sensitive data in Keychain, not `UserDefaults`.
- Request only required permissions and include clear usage descriptions.
- Minimize location data retention and avoid unnecessary persistence.

## 6) UI/UX and Accessibility

- Support Dynamic Type and scalable layouts.
- Ensure VoiceOver labels/hints for interactive controls.
- Maintain color contrast and do not rely on color alone to express state.
- Keep navigation and map interactions responsive under load.

## 7) Testing Requirements

- Every bug fix needs at least one regression test.
- Add/maintain unit tests for services, managers, and map-session logic.
- Add integration tests for critical flows:
  - route load
  - location updates
  - tracking start/stop
- Do not merge behavior changes without test updates.

## 8) Performance Requirements

- Avoid repeated heavy work in render/update loops.
- Throttle/debounce high-frequency location updates when possible.
- Reuse map overlays/markers where practical instead of recreating every update.
- Treat dropped frames, memory growth, and battery drain as release blockers for navigation flows.

## 9) Definition of Done (PR Gate)

- Build passes with zero new warnings.
- Tests pass for touched modules.
- Public API/documentation updated for behavior changes in `IMap`.
- No TODO/FIXME without a linked issue reference.

## 10) Quality Command

Run the local quality gate before opening a PR:

```bash
./scripts/quality-gate.sh
```
