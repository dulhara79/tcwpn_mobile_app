# Handbook Phase 7 Push / Realtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the ClinAnx mobile side of System Integration Handbook Phase 7 with FCM push delivery, `/v1/device-tokens` registration, PHI-free event payloads, notification-tap routing, and the existing polling fallback.

**Architecture:** The Central Backend remains the only clinical authority and persists every AttentionEvent. One Firebase Messaging project is active in any installed build because the FlutterFire `firebase_messaging` plugin does not support runtime multi-project messaging instances. The source supports two build-time Firebase slots (`primary` and `secondary`) so a disaster-recovery APK can be built against the second project; runtime resilience is provided by persistent server events plus polling. FCM carries only a generic notification plus `type=attention_event` and `event_id`.

**Tech Stack:** Flutter >=3.27.0, Dart >=3.5.0, firebase_core ^4.15.0, firebase_messaging ^16.7.0, flutter_local_notifications, existing ApiClient, SharedPreferences notification dedupe, GitHub Actions.

**Spec:** `R26-DS-012_System_Integration_Implementation_Handbook.pdf` Phase 7 — Device-token registry + push delivery + polling fallback.

## Global Constraints

- Do not use Firebase Realtime Database, Firestore, Storage, Functions, or Firebase Authentication.
- Do not put patient name, MRN, note text, scores, fusion values, model outputs, or clinical details in push payloads.
- Push delivery is never acknowledgement/resolution; only the Central Backend AttentionEvent lifecycle is authoritative.
- Keep the existing 30-second foreground polling fallback.
- Register device tokens only after clinician authentication.
- Revoke the current registration on explicit sign-out without allowing a network failure to block sign-out.
- Include the active Firebase `provider_project_id` in `/v1/device-tokens` registrations so primary and DR tokens cannot be mixed server-side.
- Do not claim seamless runtime switching between Firebase projects; secondary is a build-time disaster-recovery slot.
- Do not add this feature branch to workflow push triggers; let the full workflow run on the PR to `main` to avoid repeated failure-email noise.

---

### Task 1: Freeze push payload and device-token contracts

**Files:**
- Create: `lib/core/notifications/push_attention_message.dart`
- Create: `lib/domain/contracts/device_token_registration.dart`
- Create: `lib/domain/repositories/device_token_repository.dart`
- Test: `test/p7_push_payload_test.dart`
- Test: `test/device_token_registration_coordinator_test.dart`

**Interfaces:**
- `PushAttentionMessage.tryParse(Map<String, dynamic>) -> PushAttentionMessage?`
- `DeviceTokenRegistration.toJson() -> Map<String, dynamic>`
- `DeviceTokenRepository.upsert(DeviceTokenRegistration)`

- [ ] Write tests that accept only `type=attention_event` with nonblank `event_id`, ignore extra PHI-like fields, and serialize only provider/project/platform/token/active fields.
- [ ] Verify tests are RED because the new contract files do not exist.
- [ ] Implement the minimal pure-Dart contracts.
- [ ] Re-run focused tests and verify GREEN.

### Task 2: Add token lifecycle coordinator and Central Backend adapter

**Files:**
- Create: `lib/core/notifications/device_token_registration_coordinator.dart`
- Create: `lib/data/repositories/central_backend_device_token_repository.dart`
- Test: `test/device_token_registration_coordinator_test.dart`

**Interfaces:**
- `register(String token)` sends `active=true`.
- `rotate(String newToken)` deactivates the old token and activates the new token.
- `revoke()` sends `active=false` for the last registered token.
- Backend route is exactly `/v1/device-tokens`.

- [ ] Write lifecycle tests using a fake repository.
- [ ] Verify RED.
- [ ] Implement coordinator and adapter.
- [ ] Verify GREEN.

### Task 3: Add build-time primary/secondary Firebase slots

**Files:**
- Modify: `lib/core/config/env.dart`
- Create: `lib/core/notifications/push_firebase_config.dart`
- Modify: `pubspec.yaml`
- Test: `test/p7_push_realtime_authority_test.dart`

**Interfaces:**
- `PUSH_FIREBASE_SLOT=primary|secondary`.
- Each slot supplies API key, app ID, sender ID, project ID, and optional iOS bundle ID via `--dart-define`.
- `PushFirebaseConfig.options` creates the one active FirebaseOptions object for the installed build.

- [ ] Write source/contract tests proving two slots exist and Firebase DB/Storage/Functions are absent.
- [ ] Add current stable FlutterFire dependencies.
- [ ] Implement slot selection with empty configuration meaning push-disabled rather than crash.
- [ ] Verify focused tests.

### Task 4: Add Firebase Messaging transport

**Files:**
- Create: `lib/core/notifications/attention_push_service.dart`
- Create: `lib/core/notifications/firebase_attention_push_service.dart`
- Modify: `lib/data/api/session.dart`
- Test: `test/session_sign_out_test.dart`
- Test: `test/p7_push_realtime_authority_test.dart`

**Interfaces:**
- `initialize()` configures only the active Firebase project.
- `activateAuthenticatedSession()` gets the FCM token and registers it with the backend.
- token refresh rotates registrations.
- `foregroundEventIds` emits only validated event IDs from `onMessage`.
- `openedEventIds` emits only validated event IDs from notification taps.
- `takeInitialOpenedEventId()` handles terminated-app notification launch.
- Session sign-out runs a best-effort pre-sign-out hook to deactivate the device token, then always clears credentials.

- [ ] Add sign-out-hook and push-transport authority tests.
- [ ] Verify RED.
- [ ] Implement minimal transport and lifecycle.
- [ ] Verify GREEN.

### Task 5: Integrate push with existing polling/local notification path

**Files:**
- Modify: `lib/state/attention_notification_controller.dart`
- Modify: `lib/features/shell.dart`
- Modify: `lib/main.dart`
- Test: `test/attention_notification_controller_test.dart`
- Test: `test/p7_push_realtime_authority_test.dart`

**Interfaces:**
- Foreground FCM event -> existing generic local notification -> delivery dedupe store.
- Background/terminated system notification tap -> event ID -> authenticated canonical event-detail fetch.
- Push open marks the event locally delivered so the next poll does not duplicate the notification.
- Polling remains 30 seconds while the shell is foregrounded.

- [ ] Add failing dedupe/route tests.
- [ ] Implement `deliverEventId` in the notification controller.
- [ ] Subscribe shell to push foreground/open streams and register token after authentication.
- [ ] Initialize push before app render when a stored authenticated session exists.
- [ ] Verify focused tests.

### Task 6: CI and security guardrails

**Files:**
- Modify: `.github/workflows/p1_p2_dashboard_ci.yml`
- Modify: `.gitignore`
- Test: full repository suite through GitHub Actions.

- [ ] Add Phase 7 push tests to the focused workflow command without adding the feature branch to push triggers.
- [ ] Add forbidden-pattern checks preventing PHI fields in push modules and preventing Firebase database/storage/functions dependencies.
- [ ] Ignore Firebase service configuration and service-account files if generated locally.
- [ ] Open PR to `main`.
- [ ] Require PR CI: focused tests, authority/privacy checks, full tests, and `flutter analyze` all green before claiming completion.

## Acceptance Criteria

- An authenticated Android/iOS build with valid active-slot Firebase identifiers can obtain and register an FCM token through `/v1/device-tokens`.
- The backend receives the active Firebase project ID with every token registration.
- Foreground push produces the same generic local notification used by polling and is deduplicated by event ID.
- Background/terminated notification taps route only by event ID and fetch sensitive details from the authenticated Central Backend path.
- Push loss/throttling does not lose events because server persistence plus polling remains intact.
- Explicit sign-out performs best-effort token deactivation and still signs out when token revocation cannot reach the backend.
- Source supports a primary and secondary Firebase build slot, but does not make the unsupported claim that FlutterFire Messaging can switch projects at runtime.
- No Firebase database/storage/functions product is introduced.
