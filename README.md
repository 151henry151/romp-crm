# JgsCrm

Phoenix CRM for **JGS Mechanical** — jobs list, auth, and inbound SMS leads via Twilio + Anthropic Claude.

## Quick start (local)

* Run `mix setup` to install and setup dependencies
* Start the server with `mix phx.server` or `iex -S mix phx.server`
* Open [http://localhost:4000](http://localhost:4000)

---

## Deploying under a subpath (`https://hromp.com/jgs-crm/`)

Phoenix keeps routes at **`/`** on the app server. Your **reverse proxy** must forward `https://hromp.com/jgs-crm/...` to **`http://127.0.0.1:4000/...`** by **stripping** the `/jgs-crm` prefix. Public URLs (links, assets, LiveView websocket) use the prefix via **`Endpoint` URL config** (`path_prefix` in prod).

### Nginx example

```nginx
location /jgs-crm/ {
    proxy_pass http://127.0.0.1:4000/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSockets (LiveView)
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

The trailing slash on **`proxy_pass http://127.0.0.1:4000/;`** makes nginx map `/jgs-crm/foo` → `/foo` on the upstream.

Then:

1. Build a **production** release (or run `MIX_ENV=prod mix phx.server`) so `config/prod.exs` applies (`path_prefix` is `/jgs-crm`).
2. Set **`PHX_HOST=hromp.com`** (and **`SECRET_KEY_BASE`**, **`DATABASE_PATH`**, etc.) per `config/runtime.exs`.
3. Restart the app and nginx; open **`https://hromp.com/jgs-crm/`**.

If you still see **404**, nginx is likely forwarding **`/jgs-crm/...`** unchanged to Phoenix — fix the **`proxy_pass`** strip above.

---

## Inbound SMS (Twilio → CRM job)

Webhook URL (what Twilio calls):

**`https://hromp.com/jgs-crm/webhooks/twilio/sms`** — HTTP POST — must hit nginx → stripped → Phoenix **`/webhooks/twilio/sms`**.

### Environment variables

| Variable | Purpose |
| -------- | ------- |
| `TWILIO_AUTH_TOKEN` | From Twilio Console; verifies `X-Twilio-Signature` |
| `ANTHROPIC_API_KEY` | [Anthropic Console](https://console.anthropic.com/) API key |
| `ANTHROPIC_MODEL` | Optional; default `claude-sonnet-4-20250514` |
| `TWILIO_WEBHOOK_PUBLIC_URL` | Optional; set to the **exact** webhook URL Twilio signs (`https://hromp.com/jgs-crm/webhooks/twilio/sms`) if signature checks fail behind proxies |
| `SKIP_TWILIO_SIGNATURE_VALIDATION` | `true` **only** for local/ngrok debug — **never** in production |

Development reads these when set before `mix phx.server` (`config/dev.exs`). Production sets them on the host / release (`config/runtime.exs` prod section).

---

## Production checklist (hromp.com)

**Step-by-step (nginx, env file, systemd, release):** see [deploy/README.md](deploy/README.md).

* `DATABASE_PATH`, `SECRET_KEY_BASE`, `PHX_HOST`
* `TWILIO_AUTH_TOKEN`, `ANTHROPIC_API_KEY` (after SMS + AI setup)
* Subpath: nginx strips `/jgs-crm` to Phoenix; prod `path_prefix` in `config/prod.exs`

See [Phoenix deployment](https://hexdocs.pm/phoenix/deployment.html).
