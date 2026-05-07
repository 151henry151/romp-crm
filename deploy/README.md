# Deploying on hromp.com (`/romp-crm`)

Run these steps **on the server**. This repo’s OTP application name is **`:romp_crm`** (release binary **`romp_crm`**); public URLs use **`/romp-crm`**.

## Step 1 — Nginx

1. Edit the TLS `server { ... }` block for **hromp.com**.
2. Use **`nginx-location-romp-crm.conf`** as the `location` block (same pattern as other proxied apps).
3. Redirect any legacy alternate mount URLs to **`/romp-crm`** (see comments in `nginx/conf.d/00-hromp.com.conf` in the webserver repo).
4. Validate and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

## Step 2 — Environment file + release + systemd

1. Clone or sync this repo to **`/home/henry/romp-crm`** (see parent rename/migration notes in changelog).

2. Secrets file (never commit the real file):

```bash
cp deploy/romp-crm.env.example /home/henry/romp-crm/.env.production
chmod 600 /home/henry/romp-crm/.env.production
```

Fill in **`SECRET_KEY_BASE`**, **`DATABASE_PATH`**, SMTP, Twilio, Anthropic, etc.

3. Build release on the server:

```bash
cd /home/henry/romp-crm
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

4. Install **systemd**:

```bash
sudo install -m 644 deploy/romp-crm.service /etc/systemd/system/romp-crm.service
sudo systemctl daemon-reload
sudo systemctl enable --now romp-crm
sudo systemctl status romp-crm
```

5. **Twilio:** point **“A message comes in”** at:

`https://hromp.com/romp-crm/webhooks/twilio/sms` (HTTP POST).

Either set it in the Twilio Console on your SMS-capable number (**+18022780965** recommended), or from the repo with secrets exported:

```bash
cd /home/henry/romp-crm
set -a && source .env.production && set +a
TWILIO_WEBHOOK_PUBLIC_URL="https://hromp.com/romp-crm/webhooks/twilio/sms" mix twilio.configure_sms
```

Match **`TWILIO_WEBHOOK_PUBLIC_URL`** in `.env.production` to that exact URL if you use signature validation. Set **`TWILIO_ACCOUNT_SID`**, **`TWILIO_AUTH_TOKEN`**, and **`TWILIO_MESSAGING_FROM`** (`+18022780965`) so the CRM can send confirmation and clarification replies (`TWILIO_SMS_REPLIES_ENABLED=false` disables outbound SMS).
