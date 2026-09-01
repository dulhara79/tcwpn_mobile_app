# Clinician-Supportive UX Redesign

## Goal
Transform the existing doctor app into a clinician-first decision-support product while preserving the working data, authentication, QR pairing, note analysis, alerting, evidence retrieval, and backend contracts already present on `demo/investor-mobile-ready`.

The redesign must remove research/engineering jargon from normal doctor workflows and replace it with actionable patient insight, clearer hierarchy, and simpler navigation.

## Branching
- Source branch: `demo/investor-mobile-ready`
- Redesign branch: `ux/clinician-supportive-redesign`
- Do not modify `main`, `tcwpn/test_patch`, or `demo/investor-mobile-ready`.

## Product principles
1. Speak in clinical workflow language, not implementation language.
2. Lead with what needs attention and what changed.
3. Do not expose component numbers, wire keys, backend names, model architecture, or research metrics in routine use.
4. Preserve uncertainty and safety information that is clinically meaningful.
5. Never relabel a clinical-note score as fusion or overall risk.
6. Show overall risk only when an actual overall/fusion result exists.
7. Keep research and infrastructure diagnostics out of primary clinician navigation.

## Navigation
Replace the current six-item bottom navigation with five clinician-oriented destinations:
- Home
- Patients
- Alerts
- Assistant
- More

The separate Dashboard tab is folded into Home. Settings moves under More. `Ask CARE` becomes `Clinical Assistant`.

## Home
Home replaces the research-oriented Caseload experience.

### Top summary
Show:
- Active patients
- Needs review
- Awaiting assessment
- Recent changes

These values should be derived from currently available patient and clinical-note data. When fusion is unavailable, clinical-note risk remains explicitly labelled as clinical-note risk.

### Needs attention
Create a ranked list of useful patient insights using plain language, for example:
- Latest note indicates high anxiety
- Risk increased since previous assessment
- No current assessment recorded
- New alert awaiting review

Each item should take the clinician directly to the relevant patient chart.

### Remove from Home
- Framework panel
- Component 1/2/3/4 references
- modality counts
- fusion weighting explanations
- AUROC/model validation terminology
- protocol RED/DARK RED wording
- support-set shortcut

## Patient list
Patient cards should prioritise:
- patient name
- identifier and basic demographics
- latest available risk level
- trend
- last assessment time
- clear attention state

Do not show modality counts or fusion internals in the patient list.

Use clinician-friendly severity wording such as Low, Moderate, High, Very high/Urgent where appropriate and consistent with the underlying source.

## Patient chart
Restructure the patient chart into:
- Overview
- Notes
- History

### Overview
Answer four questions immediately:
1. How is this patient now?
2. Is the patient improving or worsening?
3. When was the last assessment?
4. What needs attention?

If a valid fusion result exists, show it as `Overall risk`. If not, say that an overall assessment is not currently available rather than explaining fusion gates or modality requirements.

Remove routine display of:
- fusion gate
- modality diagnostics
- backend provenance
- wire keys
- component numbering
- model/service names

### Notes
Show note history in clinician language. Each note should show useful status, date, risk level, and whether it needs re-analysis.

Remove the support-set panel from the normal notes workflow.

### History
Use this area for clinically meaningful longitudinal information such as assessment changes, prior note scores, alerts, and relevant activity already available in the app.

Remove the current research-placeholder Intervention screen that describes SHAP, DiCE, FAISS, conformal prediction, or future component integrations.

## Clinical note entry
Rename and simplify the screen around the task `New clinical note`.

Keep:
- note type
- note text
- word count
- privacy/de-identification warning
- Save draft
- Analyse note
- edit/delete lifecycle

Change technical copy such as `Running TC-WPN` to clinician-facing language such as `Reviewing clinical note...`.

Remove support-set readiness, prototype, K-shot, and model-architecture language from routine use.

## Clinical note result
Lead with the clinically useful result, for example:
- High anxiety signal
- current probability/score
- confidence warning when genuinely useful

Primary sections:
- What this suggests
- Change from previous assessment
- Key phrases
- Doctor review
- Submitted note

Do not expose in the normal result screen:
- TC-WPN
- support-set influence
- prototype distances
- K/shots
- entropy
- raw threshold diagnostics
- calibration plumbing
- model version/debug metadata
- framework composite terminology

Retain uncertainty warnings and clinician-judgement messaging where clinically relevant.

## Alerts
Use clinician-friendly language rather than protocol colour names.

Examples:
- High risk
- Urgent review
- Needs attention

Change `Acknowledge` to `Mark reviewed` unless the underlying audit semantics require the stronger term internally. Preserve acknowledgement data and audit behaviour.

## Clinical Assistant
Rename `CARE-AnxRAG` / `Ask CARE` to `Clinical Assistant` with a subtitle such as `Evidence support`.

Keep grounded evidence retrieval and citations unchanged underneath.

Add useful starter prompts, for example:
- What should I monitor when anxiety is worsening?
- What does current evidence say about panic attacks?
- What follow-up may be appropriate after a high anxiety assessment?

Replace technical status copy such as `Retrieving and appraising evidence` and `Local generation` with concise clinician-facing progress text.

Crisis/safety states must use direct clinical language such as `Urgent safety concern detected` rather than implementation terminology like `crisis pre-screen matched`.

## More / Settings
Primary doctor-facing More screen should contain:
- Profile
- Notifications
- Privacy & data
- Help
- About
- Sign out

Remove from normal doctor-facing settings:
- backend URLs
- service names
- model health payloads
- wire keys
- TLS/certificate pinning panels
- infrastructure connectivity internals
- raw model metadata

Development troubleshooting capability may remain in code or be moved to a clearly separated developer-only/debug surface, but must not be part of routine clinician navigation.

## Visual design
Preserve the existing calm clinical palette and design tokens where practical.

Improve:
- spacing and scanability
- information hierarchy
- larger status headers
- consistent patient cards
- meaningful icons
- compact trend indicators
- actionable empty states
- consistent severity chips
- touch targets

Avoid decorative elements that do not support clinical scanning or action.

## Jargon guard
Add regression coverage to prevent routine doctor-facing screens from reintroducing terms including:
- Component 1 / Component 2 / Component 3 / Component 4
- TC-WPN
- CARE-AnxRAG
- fusion gate
- conformal
- SHAP
- DiCE
- FAISS
- wire key
- AUROC
- renormalised / renormalized
- support set
- meta-trained prototypes
- Central Backend
- modality / modalities where plain clinical wording is sufficient

Technical terms may remain in internal comments, domain models, APIs, tests, architecture documentation, and intentionally developer-only surfaces.

## Data and safety boundaries
- Do not change model scoring behaviour as part of this UX redesign.
- Do not fabricate clinical insight.
- Insights must be derived from existing patient, clinical-note, alert, and fusion data.
- A clinical-note score must remain labelled as clinical-note risk/signal.
- Overall risk must only come from an actual fusion/overall result.
- Existing note persistence and error recovery must remain intact.
- Existing login and logout behaviour must remain intact.
- Existing QR/patient pairing flow must remain intact.
- Existing evidence citations must remain intact.

## Verification
Implementation should include:
- regression tests for clinician-facing wording
- navigation structure tests
- Home insight derivation tests
- existing clinical dashboard tests
- existing session/login tests
- existing gateway contract tests where unaffected
- Flutter test run on the redesign branch
- compile/build verification where supported

No completion claim should be made without fresh verification evidence.
