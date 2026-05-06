# Changelog

## [Unreleased]
### Changed
- Align `Jobs` context tests and `JobsFixtures` with `create_job/1`, `list_jobs/0`, and no user scope on jobs
- Expect authenticated session for `GET /` controller test so it matches the jobs LiveView route
- Replace default Phoenix navbar with JGS logo (`/images/jgs_logo.png`), app name, and theme toggle only; remove Phoenix Website, GitHub, and Get Started links
- Show the same logo in the jobs dashboard header and set the default browser title suffix to `JGS Mechanical · CRM`
- Scope modal dialog content with `data-theme="light"` and explicit text color so DaisyUI field labels stay readable on the white modal when the app uses a dark theme

### Added
- Forward `/dev/mailbox` to `Plug.Swoosh.MailboxPreview` when dev routes are enabled so local adapter emails are viewable in the browser
- Google Keep integration via `gkeepapi` — read, append, and overwrite Keep notes
- Keyring-based authentication — master token stored securely in system keyring
- CLI (`jgs-crm list`, `read`, `append`, `write`) for interacting with Keep notes
