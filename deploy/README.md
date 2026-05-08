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

**Open registration:** leave **`ENFORCE_REGISTRATION_ALLOWLIST`** unset or **`false`** (default). Set **`ENFORCE_REGISTRATION_ALLOWLIST=true`** and **`ALLOWED_REGISTRATION_EMAILS`** only if you want to lock sign-ups to a fixed email list.

**PayPal subscription paywall (hosted product):** export **`PAYPAL_CLIENT_ID`** and **`PAYPAL_CLIENT_SECRET`** (Live app from developer.paypal.com), then:

```bash
set -a && source .env.paypal.local && set +a   # or export manually
PAYPAL_MODE=live mix paypal.provision
```

Merge **`deploy/paypal-provision-result.env`** (and the client id/secret) into **`.env.production`**. The file includes **`PAYPAL_TRIAL_DAYS`** (default **14** in the task) so the app’s copy matches the trial on the **PayPal billing plans**. Default webhook URL is **`https://rompcrm.com/romp-crm/webhooks/paypal`** — override with **`PAYPAL_WEBHOOK_URL`** if your public host differs.

After changing trial length or prices, run **`mix paypal.provision`** again and update **`PAYPAL_PLAN_*`** IDs in **`.env.production`** — existing subscribers stay on old plans until PayPal migrates them (typically you leave old plans in place for legacy subscribers only).

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

**Messaging Service:** If **`+18022780965`** is attached to a Twilio Messaging Service (common for A2P outbound), Twilio may **not** call the number's **SmsUrl** for inbound unless **“Defer to sender’s webhook”** / **`UseInboundWebhookOnNumber`** is enabled on that service, or you set the service **Inbound Request URL**. After exporting `.env.production`, run:

```bash
TWILIO_MESSAGING_SERVICE_SID='MG…' mix twilio.messaging_service_inbound
```

(or enable **Defer to sender’s webhook** in Console → Messaging → your Service → Integration).
