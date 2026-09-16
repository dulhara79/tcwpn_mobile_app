# ClinAnx Phase 6 Live Contract Completion Design

**Date:** 2026-09-16
**Repository:** `dulhara79/tcwpn_mobile_app`
**Target branch:** `integration/clinanx-p6-live-contract`
**Base commit:** `2b9e8927eb5b4f0e50bfae0ef9cab2b7f9b82202`
**Status:** Approved approach in chat; written specification for implementation review

## 1. Purpose

Phase 6 mobile notification infrastructure is already merged into `main`. The remaining work is not to redesign notification UX; it is to complete the production transport only when the Central Backend exposes a verified persistent `AttentionEvent` contract.

The target end-to-end path is:

```text
Central Backend persistent OPEN AttentionEvent
        -> verified AttentionEventRepository transport
        -> foreground/resume polling in ClinAnx
        -> one local OS notification per server event_id
        -> authenticated notification tap
        -> canonical event detail fetch
        -> server ACK / RESOLVE mutations
        -> canonical actor/timestamp/state returned
```

ClinAnx never creates authoritative escalation events, never infers event state from risk colour/score, and never converts notification delivery or dismissal into acknowledgement or resolution.

## 2. Current verified state

### 2.1 ClinAnx main

Current `main` is `2b9e8927eb5b4f0e50bfae0ef9cab2b7f9b82202`, which merged Phase 6 notification delivery.

Already implemented and retained:

- `AttentionNotificationGateway` abstraction;
- `FlutterAttentionNotificationGateway` using `flutter_local_notifications`;
- generic PHI-minimized notification text;
- event ID as notification payload;
- local notification-delivery dedupe scoped by clinician;
- pending-open persistence for cold-start navigation;
- foreground polling every 30 seconds;
- immediate poll when polling starts;
- poll on app resume;
- no background reliability claim;
- no local event lifecycle mutation;
- notification tap opens `AttentionEventDetailScreen.production(eventId)`;
- authority regression tests preventing local clinical authority.

### 2.2 Current production contract gate

`CentralBackendAttentionEventRepository` deliberately returns `ApiFailure.notConfigured` for:

```text
openEvents()
activity()
eventById()
acknowledge()
resolve()
```

This gate is correct while the backend contract is unverified and must remain until exact implemented routes and response shapes are confirmed.

### 2.3 Central Backend recheck

At design time, visible `UVINDUSEN/component4final` `main` is still `a1ceef8daba268dac24d81aedd76c89e7c9ccc6a`.

Verified existing backend capabilities include subjects, ingestion, fusion, patient risk, clinician timeline, evidence, verdicts and audit logging. The visible current database schema and routes do not expose a verified persistent `AttentionEvent` model with assignment-scoped list/detail/acknowledge/resolve operations.

Therefore this ClinAnx branch must not invent endpoint paths, wrappers, event types, assignment semantics, actor fields, concurrency behavior or push-token APIs from handbook examples.

## 3. Source-of-truth invariants

The following rules are non-negotiable:

- The Central Backend owns event creation and escalation policy.
- The Central Backend owns clinician assignment filtering.
- `AttentionEvent.id` is server-owned and is the dedupe/navigation identity.
- The server owns lifecycle state: `OPEN -> ACKNOWLEDGED -> RESOLVED`.
- The server owns `acknowledged_by`, `acknowledged_at`, `resolved_by`, and `resolved_at`.
- Mobile notification delivery bookkeeping is not clinical state.
- Missing/unavailable/stale data is never converted into Low/Green/0/safe.
- A RED UI band does not create an event.
- A notification tap does not acknowledge an event.
- A failed/offline mutation does not queue or display a fake committed lifecycle transition.
- A concurrent server update wins over the local clinician's intended transition.
- Patient name, MRN, note text and model detail must not be embedded in notification payloads.

## 4. Contract verification gate

Before any production route is wired, the exact backend implementation/OpenAPI must verify all of the following.

### 4.1 Authentication and authorization

- how ClinAnx authenticates the clinician to these routes;
- whether the backend derives clinician identity from the authenticated principal;
- assignment enforcement for event list, event detail and mutations;
- exact `401` and `403` semantics.

### 4.2 Event retrieval

Verify exact route, method and response wrapper for:

- assignment-scoped open events;
- activity/history events;
- event detail by `event_id`;
- optional subject filtering if implemented.

### 4.3 Lifecycle mutation

Verify exact route, method, body and response for:

- acknowledge;
- resolve;
- conflict/concurrency response;
- current canonical event returned after mutation;
- actor and timestamp fields.

### 4.4 Error semantics

Verify server behavior for:

```text
400/422 request validation
401 expired/invalid authentication
403 valid clinician without permission/assignment
404 missing event
409 stale/conflicting lifecycle transition, if used
5xx backend failure
network timeout/offline
```

Do not encode assumptions where the backend differs.

## 5. Repository implementation design

Only `CentralBackendAttentionEventRepository` should learn the verified HTTP transport. Existing controllers and screens continue to depend on `AttentionEventRepository`.

Production repository requirements:

- use the existing `ApiClient` rather than direct `http` calls;
- parse through the existing `AttentionEvent.fromJson` contract;
- preserve exact server event IDs and lifecycle provenance;
- never supply client-generated final actor/time/state;
- map list/detail/mutation wrappers only as actually implemented by the backend;
- treat malformed success payloads as explicit contract/service failure, not empty/safe data;
- retain `notConfigured` for any operation whose contract remains unverified.

No new model-service direct call is permitted.

## 6. Polling and notification behavior

The existing Phase 6 polling implementation remains the design unless verification exposes a concrete defect.

`AttentionNotificationController.pollOnce()` must continue to:

1. reject overlapping polls;
2. call only `repository.openEvents()`;
3. notify only server events whose status is exactly `OPEN`;
4. skip empty event IDs;
5. dedupe by exact event ID using local delivery bookkeeping;
6. mark delivered only after OS notification display succeeds;
7. retry after notification transport failure because the event was not marked delivered;
8. retain honest `ApiFailure` state when backend/auth/offline errors occur;
9. never call acknowledge or resolve.

The app shell remains foreground/resume polling only for this phase. FCM/WebSocket/background delivery is not required unless a separately verified requirement is introduced.

## 7. Notification privacy and routing

Notification content remains generic:

```text
Title: ClinAnx
Body: New attention event available.
Payload: <event_id>
```

No patient name, MRN, note, score, forecast detail or model detail is placed in the OS notification payload.

On open:

1. persist/obtain the event ID;
2. complete consent/auth flow first;
3. open `AttentionEventDetailScreen.production(eventId)`;
4. fetch canonical event detail through the production repository;
5. do not acknowledge automatically.

## 8. Concurrency behavior

For multiple clinicians assigned to one patient:

- both may receive the same server event if the backend assignment policy permits it;
- ACK/resolve must be atomic server operations;
- if the server reports a conflict/stale transition, the client reloads the canonical event;
- display the server-provided clinician actor/time;
- local state never overwrites a newer server state.

Existing P4 conflict handling should be reused rather than introducing notification-specific mutation logic.

## 9. TDD requirements

Implementation uses RED -> GREEN -> REFACTOR.

### 9.1 Repository tests

Before wiring each verified operation, add a failing test proving the exact contract:

- open-event route/method/auth and response wrapper;
- activity route/method and optional subject query behavior;
- detail route and event-ID encoding;
- acknowledge route/body and canonical response parsing;
- resolve route/body and canonical response parsing;
- `401/403/404/409/5xx` mapping;
- malformed success payload does not become an empty/safe event set.

If the backend has no verified contract for an operation, its test must continue to assert `ApiFailure.notConfigured`.

### 9.2 Notification regression tests

Retain/add tests proving:

- duplicate event is notified once per clinician scope;
- delivery-store recreation preserves dedupe;
- different clinician scope can receive the event independently;
- only exact server `OPEN` status notifies;
- notification show failure does not mark delivered;
- backend failure creates no local event or safe-state fallback;
- overlapping poll is suppressed;
- tap/cold-start routing uses the same exact event ID;
- tap does not ACK/resolve.

### 9.3 Authority tests

The active notification and event paths must reject:

```text
ClinicalAlert(...)
AlertBandX.fromScore
locally generated current_score / forecast_score authority
client-written acknowledged_by / resolved_by
client timestamps for lifecycle completion
direct /predict calls
guessed event endpoints
```

The guessed-route CI guard may be narrowed only after the exact backend paths are verified and covered by contract tests.

## 10. CI and verification

Before PR creation, run fresh checks on the final branch head:

```bash
flutter pub get
flutter test <focused P0-P6 contract/controller/widget tests>
flutter analyze
flutter test
Phase 6 authority/forbidden-pattern checks
```

The full suite and analysis must be reported truthfully. If a check fails, the PR must state the failure and Phase 6 must not be described as complete.

GitHub Actions should include this branch in the clinician integration workflow while development is active.

## 11. Files expected to change

If the backend contract becomes available, likely modifications are limited to:

```text
lib/data/repositories/central_backend_repositories.dart
test/repositories/... or the existing repository contract test location
test/p6_notification_authority_test.dart
.github/workflows/p1_p2_dashboard_ci.yml
```

Additional existing test files may be extended for exact backend failure/wrapper behavior. Notification gateway/controller/store files should not be rewritten without a demonstrated defect.

Documentation for this phase is stored under `docs/superpowers/`.

## 12. Explicit non-goals

This ClinAnx change does not:

- modify `UVINDUSEN/component4final`;
- create backend database tables;
- invent clinician assignment policy;
- create escalation events in Flutter;
- derive alerts from fusion scores or colours;
- add FCM, WebSockets or background service execution;
- alter fusion thresholds;
- alter TC-WPN inference;
- redesign P4 event lifecycle UI;
- implement Phase 7 hardening or Phase 8 release work.

## 13. Stop condition

If the Central Backend still lacks a concrete implemented AttentionEvent contract at implementation time:

- do not remove the contract gate;
- do not create guessed transport code;
- do not open a misleading PR claiming live Phase 6 completion;
- record the exact backend SHA inspected and the missing operations;
- leave the already-merged mobile Phase 6 infrastructure intact.

A documentation-only blocker branch may be kept, but it must not be described as production completion.

## 14. Acceptance criteria for a real Phase 6 completion PR

A Phase 6 completion PR is valid only when all are true:

1. Exact persistent AttentionEvent backend routes and JSON shapes have been verified from implemented backend code/OpenAPI.
2. ClinAnx production `openEvents()` uses the verified assignment-scoped server source.
3. Activity/detail/ACK/resolve operations used by the notification path are live-wired only where verified.
4. `AttentionEvent.id` is preserved from server to notification payload to detail fetch.
5. Only server `OPEN` events create notifications.
6. Notification delivery is deduplicated per clinician and event ID.
7. Sensitive patient data is absent from the notification payload.
8. Notification taps fetch authenticated canonical event detail and never implicitly ACK.
9. ACK/resolve use server mutations and canonical returned state.
10. Concurrent mutation behavior reconciles to server state.
11. Offline/auth/server failures do not fabricate event or safe clinical state.
12. Focused Phase 6 tests pass.
13. Full Flutter tests pass, or any unrelated failure is explicitly reported and treated according to the release policy.
14. `flutter analyze` passes.
15. Authority guards pass.
16. PR targets `main` and is not merged by the implementation agent.

Until criterion 1 becomes true, the correct production behavior remains the existing explicit `notConfigured` contract gate.
