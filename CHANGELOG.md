# Changelog

## [Unreleased]

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
