# Deploying on hromp.com (`/jgs-crm`)

Run these steps **on the server** over SSH. We cannot configure your live nginx from this repo.

## Step 1 — Nginx

1. Edit the TLS `server { ... }` block for **hromp.com**.
2. Paste **`nginx-location-jgs-crm.conf`** into that block (inside `server`, alongside other `location`s).
3. Validate and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Step 2 — Environment file + release + systemd

1. Directories:

```bash
sudo mkdir -p /etc/jgs-crm /var/lib/jgs-crm
sudo chown www-data:www-data /var/lib/jgs-crm
```

2. Secrets file (keep private; never commit):

```bash
sudo cp deploy/jgs-crm.env.example /etc/jgs-crm/jgs-crm.env
sudo chmod 600 /etc/jgs-crm/jgs-crm.env
sudo nano /etc/jgs-crm/jgs-crm.env
```

Fill in:

- **`SECRET_KEY_BASE`** — run `mix phx.gen.secret` and paste.
- **`DATABASE_PATH`** — e.g. `/var/lib/jgs-crm/jgs_crm.db`

3. Copy the **production release** to the server (from your dev machine after `MIX_ENV=prod mix release`):

```bash
# Example: rsync the release folder to /opt/jgs-crm
sudo mkdir -p /opt/jgs-crm
sudo rsync -a _build/prod/rel/jgs_crm/ /opt/jgs-crm/
sudo chown -R www-data:www-data /opt/jgs-crm
```

4. Install **systemd** (adjust paths in **`jgs-crm.service`** if you use something other than `/opt/jgs-crm`):

```bash
sudo install -m 644 deploy/jgs-crm.service /etc/systemd/system/jgs-crm.service
sudo systemctl daemon-reload
sudo systemctl enable --now jgs-crm
sudo systemctl status jgs-crm
```

5. **Migrations** (once per deploy, after copying a new release):

```bash
sudo -u www-data bash -c 'set -a; source /etc/jgs-crm/jgs-crm.env; set +a; /opt/jgs-crm/bin/jgs_crm eval "JgsCrm.Release.migrate"'
```

## Step 3 — Twilio + Anthropic (you)

Add **`TWILIO_AUTH_TOKEN`**, **`ANTHROPIC_API_KEY`**, and optionally **`TWILIO_WEBHOOK_PUBLIC_URL`** to `/etc/jgs-crm/jgs-crm.env`, then:

```bash
sudo systemctl restart jgs-crm
```

Configure Twilio’s **“A message comes in”** webhook to:

`https://hromp.com/jgs-crm/webhooks/twilio/sms` (HTTP POST).
