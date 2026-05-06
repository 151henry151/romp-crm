# Changelog

## [Unreleased]

## [0.5.3] - 2026-05-06

### Changed

- Remove the temporary JGS logo from the jobs header and simplify the new-job control to a compact `+` button
- Remove the duplicate jobs-header log-out link so mobile shows only the global account menu action

## [0.5.2] - 2026-05-06

### Changed

- Add dashboard header hint linking SMS intake number `(802) 278-0970` and clarify it accepts both new jobs and updates

## [0.5.1] - 2026-05-06

### Changed

- Standardize jobs dashboard priority and status badges to fixed-size rounded rectangles for consistent sizing across labels

## [0.5.0] - 2026-05-06

### Added

- Parse multi-operation SMS payloads into an ordered `actions` list so one inbound text can create and update multiple jobs
- Apply each parsed SMS operation independently in the Twilio webhook with per-operation logging

### Changed

- Update Anthropic extraction prompt to emit `actions` arrays for multi-job messages while preserving single-action compatibility

## [0.4.0] - 2026-05-06

### Added

- Enforce registration email allowlist (configurable via `ALLOWED_REGISTRATION_EMAILS` in production)
- Reject inbound Twilio SMS from numbers outside `TWILIO_SMS_ALLOWED_FROM` before parsing
- Add `JgsCrm.Twilio.Phone.normalize_us/1` for comparing formatted North-American caller IDs

## [0.3.0] - 2026-05-06

### Changed

- Pass live `Jobs.snapshot_for_sms_ai/0` JSON into Anthropic SMS extraction so updates select `job_id` by semantic match against CRM rows (typos, informal references)
- Validate `job_id` against the snapshot before applying Twilio SMS patches; keep heuristic `match` map path as fallback
- Extend deterministic SMS stub with `STUB_JSON` test prefix and `STUB_UPDATE` job_id shape

## [0.2.9] - 2026-05-06

### Changed

- Normalize `work_description_snippet` matching so phrases like "water shut off" or "water shut-off" align with CRM text stored as "water shutoff"
- Document work-snippet normalization in the Anthropic SMS system prompt

## [0.2.8] - 2026-05-06

### Changed

- Raise `work_description_snippet` SMS match weight so task-only references can reach the match threshold
- Treat a single above-threshold job as the SMS update target even when its score is below 52 (keeps requiring a clear margin when multiple jobs score)
- Extend Anthropic SMS prompt with indirect job references and a water-shutoff address-correction example

## [0.2.7] - 2026-05-05

### Fixed

- Scope expanded job detail rows with explicit Tailwind text color and `data-theme="light"` so Address, Work, Priority, Status, and other values stay visible on white cards when the root uses DaisyUI dark theme

## [0.2.6] - 2026-05-06
### Fixed
- Refresh job list from DB when toggling row expand or filters so SMS and other server-side updates show immediately in the dashboard

### Changed
- Label mobile summary line as Work; show optional Notes under the name only when the notes field has content
- Add Work and Status rows to the mobile expanded panel; render priority with standard HEEx control flow

### Added
- Add stable ids for mobile and desktop expanded-detail blocks for LiveView tests

## [0.2.5] - 2026-05-06
### Added
- Log full Twilio inbound SMS body, `MessageSid`, `From`, and create/update parse and database outcomes in `TwilioWebhookController` for production debugging

### Changed
- Assert SMS pipeline log lines in Twilio webhook controller tests (`capture_log`)

## [0.2.4] - 2026-05-05
### Changed
- Make jobs dashboard rows expandable so selecting a job reveals all fields inline
- Add mobile stacked job cards (no horizontal scroll) with expandable details and mobile edit/delete actions
- Reflow dashboard header controls for narrow screens to avoid account-text overlap

### Added
- Add LiveView test coverage for row expand/collapse behavior on the jobs screen

## [0.2.3] - 2026-05-05
### Added
- Resolve inbound SMS updates against existing jobs via Claude `match` hints and `SmsMatch` scoring; apply patches with `find_job_for_sms_update/1`
- Extend Anthropic SMS extractor prompt for `intent` create vs update and add `STUB_UPDATE` JSON prefix on deterministic stub for update-path tests
- Add SMS-match scoring tests and Twilio webhook update-flow tests

### Fixed
- Stop applying shell `PORT` to the endpoint in `:test` so test runs do not collide with a running release on the same host

### Changed
- Normalize SMS extractor output to explicit create/update intents before controller handling
- Route Twilio webhook create and update intents to `create_job/1` or `update_job/2` with no-match/ambiguous logging
- Relax `SmsMatchTest` combined-hint assertion to match actual scoring weights

## [0.2.2] - 2026-05-06
### Added
- Add `deploy/` with nginx location snippet, `jgs-crm.env.example`, systemd unit, and server runbook
- Add `JgsCrm.Release` for `bin/jgs_crm eval "JgsCrm.Release.migrate"` in production

## [0.2.1] - 2026-05-06
### Changed
- Document reverse-proxy stripping for `/jgs-crm` instead of mounting routes under a scope (fixes verified routes / prod compile; nginx `proxy_pass` trailing slash)

## [0.2.0] - 2026-05-06
### Changed
- Add `req` dependency for outbound Anthropic API calls
- Align `Jobs` context tests and `JobsFixtures` with `create_job/1`, `list_jobs/0`, and no user scope on jobs
- Expect authenticated session for `GET /` controller test so it matches the jobs LiveView route
- Replace default Phoenix navbar with JGS logo (`/images/jgs_logo.png`), app name, and theme toggle only; remove Phoenix Website, GitHub, and Get Started links
- Show the same logo in the jobs dashboard header and set the default browser title suffix to `JGS Mechanical · CRM`
- Scope modal dialog content with `data-theme="light"` and explicit text color so DaisyUI field labels stay readable on the white modal when the app uses a dark theme

### Added
- Twilio inbound SMS webhook at `POST /webhooks/twilio/sms` with optional `X-Twilio-Signature` verification and empty TwiML responses
- SMS-to-job pipeline using Anthropic Claude with configurable model and field extraction for CRM jobs
- Deterministic extractor stub for tests (`sms_job_extractor_adapter`)
- Forward `/dev/mailbox` to `Plug.Swoosh.MailboxPreview` when dev routes are enabled so local adapter emails are viewable in the browser
