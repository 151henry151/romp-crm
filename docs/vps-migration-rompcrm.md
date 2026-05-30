# Romp CRM + rompcrm.com — migration to a new VPS

This checklist is for operators (or an agent with **root SSH** on **both** the old and new servers) moving the hosted product from one Debian-style VPS to another with **minimal downtime** and **no loss of customer data**. The app uses **SQLite** (`DATABASE_PATH`), a **Phoenix release** behind **nginx**, and static marketing files for **rompcrm.com**.

## Repositories (source of truth)

| Piece | Repository / path | Notes |
|--------|---------------------|--------|
| Phoenix app + migrations + deploy unit | **`https://github.com/151henry151/romp-crm`** | Clone to `/home/henry/romp-crm` (or agreed `$HOME`) on the new host. |
| Marketing / landing static site (HTML, `media/`, `.well-known`) | **`https://github.com/151henry151/romp-crm-website`** (private) | Deploy tree should match what nginx `root` serves (see below). |
| Example nginx for this server’s layout | **`my-webserver-setup`** — `nginx/conf.d/00-rompcrm.com.conf` | **Copy and edit** on the new host; do not bind the old VPS IP. |

## Secrets and environment (do not commit real values)

### Primary file (required)

| Location (typical) | Purpose |
|--------------------|---------|
| **`/home/henry/romp-crm/.env.production`** | **`SECRET_KEY_BASE`**, **`DATABASE_PATH`**, **`PHX_HOST`**, **`PORT`**, SMTP, Twilio, Anthropic, optional **`GOOGLE_MAPS_API_KEY`**, PayPal (if paywall on), admin emails, optional `EMAIL_*`, `PHX_CHECK_ORIGINS`, etc. |

**Critical:** reuse the **same** **`SECRET_KEY_BASE`** from production when cut over, or all existing sessions and signed tokens become invalid immediately.

Create on the new host:

```bash
install -d -m 755 /home/henry/romp-crm/data
install -m 600 /dev/null /home/henry/romp-crm/.env.production
# paste production values (from a secure export off the old server)
chmod 600 /home/henry/romp-crm/.env.production
```

Template for missing keys: **`deploy/romp-crm.env.example`** in the **romp-crm** repo. Full semantics: **`config/runtime.exs`**.

### Optional local-only files (old server)

| Path | Purpose |
|------|---------|
| **`/home/henry/romp-crm/.env.paypal.local`** | Sourced when running **`mix paypal.provision`** (not required at runtime if vars are already in `.env.production`). |

### systemd

| Path | Purpose |
|------|---------|
| **`/etc/systemd/system/romp-crm.service`** | Installed from repo **`deploy/romp-crm.service`**; references **`EnvironmentFile=/home/henry/romp-crm/.env.production`**. |

### TLS

| Path | Purpose |
|------|---------|
| **`/etc/letsencrypt/live/rompcrm.com/`** | **`fullchain.pem`**, **`privkey.pem`** for nginx `server_name rompcrm.com www.rompcrm.com`. |

Prefer **re-issuing** certs on the new host with **certbot** and **webroot** pointing at the static site’s **`.well-known/acme-challenge/`** once DNS points here, instead of copying private keys, unless you need a hot standby before DNS moves.

### Third-party dashboards (no files on VPS)

Update only if the **public URL** of webhooks changes (usually it does **not** if the domain stays **rompcrm.com**):

- **Twilio** — SMS (and optional voice) webhook URLs documented in **`deploy/README.md`**.
- **PayPal** — live webhook URL (see **`deploy/README.md`** / **`PAYPAL_WEBHOOK_URL`**).

## What runs where (production reference)

| Component | Typical bind / path |
|-----------|---------------------|
| Phoenix release | **`127.0.0.1:${PORT}`** (e.g. **`40175`** from `.env.production`); **`PHX_HOST=rompcrm.com`** for canonical product host. |
| SQLite database file | **`DATABASE_PATH`** (e.g. **`/home/henry/romp-crm/data/romp_crm.db`**). |
| nginx `root` (static site) | e.g. **`/home/henry/webserver/domains/com/rompcrm.com/public_html`** — align with checkout of **romp-crm-website** or rsync deploy. |
| nginx `location ^~ /romp-crm/` | **`proxy_pass http://127.0.0.1:${PORT}/`** with WebSocket headers (see **`00-rompcrm.com.conf`**). |

**Important:** the checked-in nginx sample may contain **`listen <OLD_VPS_IP>:443 ssl`**. On the new VPS replace with **`listen 443 ssl`** (and **`listen [::]:443 ssl`** as needed) or the new public IPv4, then **`sudo nginx -t`** and reload.

## Pre-migration (before DNS moves)

1. **DNS TTL:** Lower **A** / **AAAA** TTLs for **rompcrm.com** and **www.rompcrm.com** at least **24 hours** ahead (e.g. 300s) so cutover propagates quickly.
2. **New VPS baseline:** Debian 12 (or same family as old), **nginx**, **certbot**, **Elixir/Erlang** toolchain for **`MIX_ENV=prod mix release`** (see **`deploy/README.md`**), non-root deploy user (e.g. **henry**) with **`sudo`** for nginx/certbot.
3. **Firewall:** Only **80/443** public; app port (**`PORT`**) must stay **localhost-only** (nginx proxies).
4. **Clone repos** on the new host:
   - `git clone https://github.com/151henry151/romp-crm.git /home/henry/romp-crm`
   - `git clone https://github.com/151henry151/romp-crm-website.git` → sync into the nginx `root` directory (same file layout as current **`public_html`**).
5. **Install `.env.production`** on the new host (same **`SECRET_KEY_BASE`**, same **`DATABASE_PATH`** path *or* update path consistently in unit + env). Set **`PHX_HOST=rompcrm.com`** (and **`PORT`** as chosen).
6. **Build release** on the new host:

   ```bash
   cd /home/henry/romp-crm
   MIX_ENV=prod mix deps.get
   MIX_ENV=prod mix assets.deploy
   MIX_ENV=prod mix release
   ```

7. **Install systemd** unit from **`deploy/romp-crm.service`**, **`daemon-reload`**, **`enable`** — **do not** `start` until DB is in place (or start against a throwaway DB only for smoke tests on a scratch **`DATABASE_PATH`**).

## Database migration (SQLite — customer data)

SQLite is a **single file** (often **`…/data/romp_crm.db`** plus **`-wal`/`-shm`** if WAL mode is on).

### Recommended: short maintenance window

1. **Announce** a brief window (minutes) if users are active.
2. On **old** server:

   ```bash
   sudo systemctl stop romp-crm
   ```

3. Still on **old** server, copy the DB file **after** stop (ensures no half-written WAL):

   ```bash
   install -d -m 755 /tmp/romp-crm-migrate
   cp -a /home/henry/romp-crm/data/romp_crm.db /tmp/romp-crm-migrate/
   # If present, copy WAL/SHM only if you use a raw copy while stopped (optional):
   # cp -a /home/henry/romp-crm/data/romp_crm.db-wal /tmp/romp-crm-migrate/ 2>/dev/null || true
   ```

   Alternatively use **`sqlite3 … ".backup '/tmp/romp-crm-migrate/romp_crm.db'"`** while stopped.

4. **Transfer** the backup to the new host ( **`scp`**, **`rsync`**, or encrypted volume). Example:

   ```bash
   scp /tmp/romp-crm-migrate/romp_crm.db NEWUSER@NEWIP:/home/henry/romp-crm/data/romp_crm.db
   ```

5. On **new** server:

   ```bash
   chown henry:henry /home/henry/romp-crm/data/romp_crm.db
   chmod 600 /home/henry/romp-crm/data/romp_crm.db
   ```

6. **Start** app on new host:

   ```bash
   sudo systemctl start romp-crm
   sudo systemctl status romp-crm
   curl -sI -o /dev/null -w "%{http_code}\n" http://127.0.0.1:40175/romp-crm/   # use $PORT from .env
   ```

7. On **old** server after DNS is fully moved and verified: keep **`romp-crm`** stopped or uninstall to avoid split-brain if something still points at old IP.

### Optional: rsync without stopping (higher risk)

For a **first** copy while old site still runs, rsync the DB file, then plan a **final** stop + copy for a consistent delta. SQLite on live writes can produce an inconsistent file if copied naïvely — prefer **stop → copy** for the final handoff.

## nginx + TLS on the new host

1. Install site config (adapted from **`00-rompcrm.com.conf`**): `root`, **`location ^~ /romp-crm/`**, logs, **remove old-IP-specific `listen`**.
2. **`sudo nginx -t && sudo systemctl reload nginx`**
3. **TLS:** After **A/AAAA** records point to the new VPS, run **certbot** webroot against **`/.well-known/acme-challenge/`** for **rompcrm.com** and **www.rompcrm.com**, then set **`ssl_certificate`** paths like the old config.

## DNS cutover (minimal downtime sequence)

1. New host passes **local** checks: **`curl -I http://127.0.0.1:$PORT/romp-crm/`**, static **`https://NEW_IP/`** (with **`-k`** if using temporary self-signed) or via **hosts file** override from a laptop.
2. **Stop** **`romp-crm`** on old server; **final DB copy**; **start** on new server; confirm **`journalctl -u romp-crm -n 50`** clean.
3. **Point DNS** A/AAAA to new VPS.
4. Wait for propagation; verify **`curl -sI https://rompcrm.com/romp-crm/`** and log in.
5. **Reload nginx** if needed; confirm **wss** / LiveView works in browser.

**Downtime** ≈ DNS TTL + minutes for stop/copy/start if done tightly.

## Post-cutover verification

- [ ] **`https://rompcrm.com/`** — landing loads (from **romp-crm-website** deploy).
- [ ] **`https://rompcrm.com/romp-crm/`** — app loads, log in, LiveView socket works.
- [ ] **Magic-link email** arrives and renders.
- [ ] **Twilio inbound SMS** creates jobs (signature URL unchanged if domain unchanged).
- [ ] **PayPal** webhooks (if paywall enabled) show delivery in PayPal dashboard.
- [ ] **Data spot-check** — known user / job count vs pre-migration notes.

## Rollback

If the new host fails after DNS change: revert DNS to old VPS IP, start **`romp-crm`** on old server (restore DB from the pre-cutover backup if it was modified on the new host). Keep the **pre-migration** DB copy until the new site is stable for several days.

## Related documentation

- **`deploy/README.md`** — build, systemd, Twilio, PayPal.
- **`docs/self-hosting-rompcrm.com.html`** — end-user self-host guide (also published as **`/self-hosting.html`** on the marketing site).
