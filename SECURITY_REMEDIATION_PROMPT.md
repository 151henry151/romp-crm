# Security Remediation Agent Prompt — romp-crm

## Context

This is a Phoenix 1.8 / LiveView / Elixir application (`romp_crm`) that serves as a field-service CRM at `rompcrm.com`. It uses SQLite via Ecto, Twilio for SMS/voice webhooks, Anthropic Claude for AI SMS parsing, PayPal for subscriptions, and Swoosh for email. The app is multi-tenant (data isolated by `business_id`).

An automated security scan and manual code review identified a set of real issues. **Do not make any changes beyond what is explicitly described below.** Do not refactor unrelated code, add comments, create new abstractions, or alter test files beyond what is specified.

---

## Issue 1 — TwiML XML Injection in Voice Webhook

**File:** `lib/romp_crm_web/controllers/twilio_webhook_controller.ex`  
**Line:** 111  
**Severity:** Medium — code correctness / defense-in-depth

### What is wrong

The `voice_twiml_dial/1` function interpolates the `e164` phone number directly into an XML string without escaping:

```elixir
defp voice_twiml_dial(e164) when is_binary(e164) do
  ~s(<?xml version="1.0" encoding="UTF-8"?><Response><Dial answerOnBridge="true">#{e164}</Dial></Response>)
end
```

`e164` is sourced from `Application.get_env(:romp_crm, :twilio_voice_forward_e164, "+18024587299")` (i.e., the `TWILIO_VOICE_FORWARD_E164` environment variable). If that value ever contains XML-special characters — `<`, `>`, `&`, `"`, `'` — the resulting TwiML would be malformed or exploitable. Phone numbers normally don't contain these characters, but relying on that assumption is fragile.

### The fix

Escape the `e164` value before interpolation. Elixir's `Plug.HTML.html_escape/1` is already available in the project and produces a safe string. Apply it in `voice_twiml_dial/1`:

```elixir
defp voice_twiml_dial(e164) when is_binary(e164) do
  safe_e164 = Plug.HTML.html_escape(e164)
  ~s(<?xml version="1.0" encoding="UTF-8"?><Response><Dial answerOnBridge="true">#{safe_e164}</Dial></Response>)
end
```

This is a single-line change. No other code in this file or module needs to change.

---

## Issue 2 — Photo Upload: No Explicit File Size Limit or MIME Validation

**Files:**  
- `lib/romp_crm_web/endpoint.ex` (lines 47–51)  
- `lib/romp_crm_web/controllers/job_photo_controller.ex` (lines 24–55)  
- `lib/romp_crm/jobs.ex` (lines 413–445)

**Severity:** Medium — potential for disk exhaustion and storing non-image files

### What is wrong

**A) No explicit upload size limit.** `Plug.Parsers` at `endpoint.ex:47` has no `:length` option, which means it falls back to the Plug default of 8 MB. For a photo-upload endpoint that stores files to disk (`priv/static/uploads/job-photos/`), 8 MB per request is a reasonable upper bound, but the limit is invisible — anyone maintaining this code could add a second multipart route without realising the default applies, or the default could change in a future Plug version. The limit should be explicit.

**B) No MIME type or magic bytes validation.** In `job_photo_controller.ex` line 26, the `content_type` is accepted directly from `Plug.Upload` (user-supplied) and passed through to `Jobs.add_job_photo/5`. In `jobs.ex` lines 454–463, `ext_from_content_type/1` uses the content-type string to decide the file extension but performs no check that the actual bytes match a known image format. An authenticated user could upload a non-image file (e.g., an SVG containing JavaScript, an HTML file, or a binary executable) and it would be stored on the server's static file path.

Although Plug.Static serves these files with a content-type derived from the extension (so a `.jpg` file is always served as `image/jpeg` regardless of byte content), storing arbitrary binary data on the server's static path is still undesirable and could be exploited if the serving configuration ever changes.

### The fixes

**Fix A — Make the size limit explicit in `endpoint.ex`.**

Find `Plug.Parsers` configuration at lines 47–51:
```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library(),
  body_reader: {RompCrmWeb.CacheRawBodyReader, :read_body, []}
```

Add a `:length` option that caps the total upload body at 8 MB (matching the Plug default, but making it explicit and visible):
```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library(),
  body_reader: {RompCrmWeb.CacheRawBodyReader, :read_body, []},
  length: 8_000_000
```

**Fix B — Validate MIME type in `job_photo_controller.ex`.**

In `do_upload/4`, after matching `%Plug.Upload{path: path, content_type: ct}`, add a guard that rejects content types that are not in the allowed image set. Replace the current `do_upload` body (starting at line 24) with:

```elixir
@allowed_image_types ~w(image/jpeg image/png image/gif image/webp image/jpg)

defp do_upload(conn, business_id, job_id, params) do
  case {Integer.parse(to_string(job_id)), params["photo"]} do
    {{jid, _}, %Plug.Upload{path: path, content_type: ct}} ->
      normalized_ct = ct |> to_string() |> String.downcase() |> String.split(";") |> List.first() |> String.trim()

      if normalized_ct not in @allowed_image_types do
        conn
        |> put_flash(:error, "Only image files (JPEG, PNG, GIF, WebP) may be uploaded.")
        |> redirect(to: ~p"/")
      else
        bytes = File.read!(path)
        wi_id = parse_optional_int(Map.get(params, "job_work_item_id"))

        case Jobs.get_job(jid, business_id) do
          nil ->
            conn
            |> put_flash(:error, "Job not found.")
            |> redirect(to: ~p"/")

          job ->
            case Jobs.add_job_photo(job, business_id, bytes, normalized_ct, wi_id) do
              {:ok, _} ->
                conn
                |> put_flash(:info, "Photo uploaded.")
                |> redirect(to: ~p"/")

              {:error, reason} ->
                conn
                |> put_flash(:error, "Could not save photo (#{inspect(reason)}).")
                |> redirect(to: ~p"/")
            end
        end
      end

    _ ->
      conn
      |> put_flash(:error, "Choose a photo file to upload.")
      |> redirect(to: ~p"/")
  end
end
```

The `@allowed_image_types` module attribute is placed directly before `defp do_upload`. No other functions in this module change. Pass `normalized_ct` (not the raw `ct`) into `Jobs.add_job_photo/5` to ensure the stored content type is clean.

---

## Issue 3 — SSRF Risk in MMS Photo Fetch

**File:** `lib/romp_crm/jobs.ex`  
**Lines:** 468–490  
**Severity:** Low-Medium — mitigated in practice by Twilio signature validation, but unvalidated URL fetch

### What is wrong

`add_job_photo_from_url/4` fetches an arbitrary URL from Twilio's `MediaUrl` parameter:

```elixir
case Req.get(url, headers: [{"authorization", "Basic #{auth}"}], receive_timeout: 60_000) do
```

The URL is extracted from `params["MediaUrl0"]` etc. in `twilio_webhook_controller.ex` line ~190. Twilio signature validation on the incoming webhook guards against unauthenticated callers, and Twilio itself rewrites MMS attachment URLs to its own CDN (`https://api.twilio.com/...` or `https://mms.twilio.com/...`). However, there is no code-level check that the URL is actually a Twilio CDN URL before the HTTP request fires.

If Twilio's URL format ever changes, or if the signature validation is bypassed in some edge case, this function could be tricked into making authenticated HTTP requests (with your Twilio credentials in the `Authorization` header) to arbitrary hosts.

### The fix

Add a URL allowlist check in `add_job_photo_from_url/4` before issuing the HTTP request. In `lib/romp_crm/jobs.ex`, modify the function body to validate the URL scheme and host:

```elixir
@twilio_media_hosts ~w(api.twilio.com mms.twilio.com media.twiliocdn.com)

def add_job_photo_from_url(%Job{} = job, business_id, url, work_item_id \\ nil)
    when is_binary(url) do
  account_sid = Application.get_env(:romp_crm, :twilio_account_sid)
  token = Application.get_env(:romp_crm, :twilio_auth_token)

  if is_nil(account_sid) or account_sid == "" or is_nil(token) or token == "" do
    {:error, :missing_twilio_credentials}
  else
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when host in @twilio_media_hosts ->
        auth = Base.encode64("#{account_sid}:#{token}")

        case Req.get(url, headers: [{"authorization", "Basic #{auth}"}], receive_timeout: 60_000) do
          {:ok, %{status: 200, body: body, headers: h}} when is_binary(body) ->
            ct = content_type_from_headers(h)
            add_job_photo(job, business_id, body, ct, work_item_id)

          {:ok, %{status: s}} ->
            {:error, {:download_failed, s}}

          {:error, reason} ->
            {:error, {:download_failed, reason}}
        end

      _ ->
        {:error, :invalid_media_url}
    end
  end
end
```

Place the `@twilio_media_hosts` module attribute near the top of the module with the other module attributes, or directly before the function definition. No other functions in this module change.

---

## Issue 4 — Consent Audit Persistence (GDPR Compliance)

**Files:**
- `lib/romp_crm/accounts/user.ex`
- `priv/repo/migrations/` (new migration needed)
- `lib/romp_crm_web/controllers/user_registration_controller.ex`
- `deploy/legal/privacy-policy.html` (line 49 references implicit consent)

**Severity:** High (compliance) — automated scan flagged this as the highest-priority finding

### What is wrong

The privacy policy at `deploy/legal/privacy-policy.html:49` states: *"By using the Service, you agree to this Privacy Policy."* However, there is no backend record of when a user first accepted the terms. The user schema (in `lib/romp_crm/accounts/user.ex`) has no `terms_accepted_at` or equivalent field. If a regulator or user dispute requires proof that consent was collected at a specific moment with a specific version of the policy, there is currently no audit trail.

### The fix

**Step 1 — Add a migration.**

Create a new migration file at `priv/repo/migrations/<timestamp>_add_consent_fields_to_users.exs` (use the current UTC timestamp for the filename, e.g., `20260518120000`):

```elixir
defmodule RompCrm.Repo.Migrations.AddConsentFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :terms_accepted_at, :utc_datetime, null: true
      add :terms_version, :string, null: true
    end
  end
end
```

**Step 2 — Update the User schema.**

In `lib/romp_crm/accounts/user.ex`, add the two fields to the schema block:

```elixir
field :terms_accepted_at, :utc_datetime
field :terms_version, :string
```

**Step 3 — Record consent on registration.**

In `lib/romp_crm_web/controllers/user_registration_controller.ex`, find where `Accounts.register_user/1` is called (likely passing a map of user params). Add `terms_accepted_at` and `terms_version` to that call. The current policy is version `"2026-05-18"` (match the date shown in the privacy policy's "Last Updated" header, or use whatever version string is in the policy). Example:

```elixir
user_params
|> Map.put("terms_accepted_at", DateTime.utc_now() |> DateTime.truncate(:second))
|> Map.put("terms_version", "2026-05-18")
|> Accounts.register_user()
```

You will need to inspect the exact flow in `user_registration_controller.ex` to find the right location. Look for the `create` action and the `register_user` call inside it.

**Step 4 — Allow these fields through the User changeset.**

In `lib/romp_crm/accounts/user.ex`, find the registration changeset function (likely `registration_changeset/2` or similar). Add `:terms_accepted_at` and `:terms_version` to the `cast/3` fields list so they are accepted and stored. Do not add them to any validation that requires them to be present — they should be set by the server, not the client.

**Important:** Do not add a UI checkbox to the registration form. The implicit-consent model ("by using the service you agree") is already in the privacy policy. The goal of this change is simply to record the timestamp at which the user account was created so there is a server-side audit record.

---

## Issue 5 — Phone Number Logged in Plaintext

**File:** `lib/romp_crm_web/controllers/twilio_webhook_controller.ex`  
**Line:** 233–235  
**Severity:** Low — privacy hygiene

### What is wrong

The `deliver_inbound_sms/3` function logs the raw phone number and SMS body in plaintext at the INFO level:

```elixir
Logger.info(
  "Twilio SMS inbound: sid=#{message_sid} to=#{inspect(to_num)} user_id=#{user.id} business_id=#{business_id} from=#{from} body=#{inspect(body_text)}"
)
```

The `from` value is the raw E.164 phone number (e.g., `+12025551234`). In production, logs may be aggregated by external services (Papertrail, Datadog, etc.). Storing raw phone numbers in logs is a GDPR/CCPA data minimization concern.

### The fix

Replace `from=#{from}` with a partially redacted form, and drop the SMS body from the INFO-level log (the body is not needed for diagnostics at INFO level — it was already logged at higher granularity by the AI extraction step):

```elixir
redacted_from = redact_phone(from)

Logger.info(
  "Twilio SMS inbound: sid=#{message_sid} to=#{inspect(to_num)} user_id=#{user.id} business_id=#{business_id} from=#{redacted_from}"
)
```

Add a private helper at the bottom of the module (near `defp first_nonempty/1`):

```elixir
defp redact_phone(phone) when is_binary(phone) and byte_size(phone) > 4 do
  String.slice(phone, 0, byte_size(phone) - 4) <> "****"
end
defp redact_phone(phone), do: "****"
```

Also remove `body=#{inspect(body_text)}` from that specific log line. The body is already logged at the point where AI extraction fires and in the audit log, so the INFO-level inbound line does not need it.

---

## Issue 6 — Hardcoded Support Phone Number in Source

**File:** `lib/romp_crm_web/controllers/twilio_webhook_controller.ex`  
**Line:** 77  
**Severity:** Informational

### What is wrong

```elixir
forward_to =
  Application.get_env(:romp_crm, :twilio_voice_forward_e164, "+18024587299")
```

The literal fallback `"+18024587299"` appears to be a real phone number (the support line). It is hardcoded in the source, meaning it will appear in git history and any forks or clones of the repository.

### The fix

Remove the hardcoded default. Instead, if the env var is not set, treat it as unconfigured and return a TwiML response that says the number is not in service, rather than falling back to a hardcoded number:

```elixir
def voice(conn, _params) do
  # ... (existing signature validation cond block stays unchanged) ...
  true ->
    case Application.get_env(:romp_crm, :twilio_voice_forward_e164) do
      e164 when is_binary(e164) and e164 != "" ->
        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(200, voice_twiml_dial(e164))

      _ ->
        Logger.warning("Twilio voice webhook: TWILIO_VOICE_FORWARD_E164 not configured")

        conn
        |> put_resp_content_type("text/xml")
        |> send_resp(200, voice_twiml_not_configured())
    end
end

defp voice_twiml_not_configured do
  ~s(<?xml version="1.0" encoding="UTF-8"?><Response><Say>This number is not currently in service.</Say></Response>)
end
```

Also update `config/runtime.exs` or `config/dev.exs` if there is a place where this env var is documented, to note it is required for voice forwarding. **Do not add a fallback phone number anywhere in the codebase.**

---

## What NOT to Do

The automated scan flagged several items that are **not real problems** in this codebase and should **not** be addressed:

- **Missing `.repobility/access.yml`** — this is a scanner-specific documentation artifact. The app has proper authorization via `EmployeePermissions` and LiveView `on_mount` hooks. Do not create this file.
- **"Admin routes lack super-admin separation"** — the flagged routes (`/users/settings`, `/users/log-in`, `/gift/redeem/:token`) are standard user-facing routes, not admin-only. The scanner misidentified them. Do not add extra auth gates to these routes.
- **"Sensitive routes lack elevated authorization"** — the flagged routes (`/subscribe`, `/gift/claim/:token`, `/users/log-in`) are intentionally public. They must be publicly accessible. Do not add auth guards.
- **robots.txt missing sitemap** — the `priv/static/robots-9e2c81b0855bbff2baa8371bc4a78186.txt` file is a digested asset. A sitemap does not exist and adding one is outside the scope of this remediation.
- **Missing CI/CD** — this is a real operational gap but is not a security remediation task and should be tracked separately.
- **Code duplication in AI modules** — the duplicated blocks in `lib/romp_crm/ai/` are a code quality issue and are not a security concern. Do not refactor them here.
- **No authorization-focused tests** — adding tests is a separate task and out of scope for this remediation.

---

## Summary of Changes

| Priority | Issue | Files Changed |
|----------|-------|---------------|
| 1 | XML injection in TwiML | `twilio_webhook_controller.ex` line 111 |
| 2 | Explicit upload size limit | `endpoint.ex` lines 47–51 |
| 2 | MIME type validation on uploads | `job_photo_controller.ex` |
| 3 | SSRF URL allowlist for MMS fetch | `jobs.ex` |
| 4 | Consent audit persistence | new migration, `user.ex`, `user_registration_controller.ex` |
| 5 | Phone number log redaction | `twilio_webhook_controller.ex` lines 233–235 |
| 6 | Remove hardcoded phone number | `twilio_webhook_controller.ex` line 77 |

After making all changes, run `mix ecto.migrate` to apply the new migration, then run `mix test` to verify nothing is broken.
