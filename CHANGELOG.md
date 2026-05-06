# Changelog

## [Unreleased]
### Changed
- Scope modal dialog content with `data-theme="light"` and explicit text color so DaisyUI field labels stay readable on the white modal when the app uses a dark theme

### Added
- Forward `/dev/mailbox` to `Plug.Swoosh.MailboxPreview` when dev routes are enabled so local adapter emails are viewable in the browser
- Google Keep integration via `gkeepapi` — read, append, and overwrite Keep notes
- Keyring-based authentication — master token stored securely in system keyring
- CLI (`jgs-crm list`, `read`, `append`, `write`) for interacting with Keep notes
