# Changelog

## [0.16.2] - 2026-07-20

### Fixed

- Store live workday timeclock punches as local wall-clock times (user SMS reminder timezone) instead of UTC digits in naive columns
- Prefill job-hours `datetime-local` defaults from local wall clock instead of UTC

### Added

- `RompCrm.LocalWallClock` helper for business-local naive datetimes

## [0.16.1] - 2026-07-20

### Fixed

- Keep job `notes` on the job row after expand-edit save instead of overlaying linked client notes via `merge_client_onto_job`
- Stop copying client `notes` onto linked jobs during client contact sync

## [0.16.0] - 2026-07-18

### Added

- Per-job "Print job" PDF download on the jobs list (`GET /jobs/:job_id/print`) with contact, schedule, status, work items, materials, hours logged, notes, and embedded photos
- `RompCrm.JobPrint` report builder and HTML document for single-job PDFs (reuses the print-reports PDF adapter)

## [0.15.1] - 2026-07-17

### Changed

- Default Anthropic model fallback strings to `claude-sonnet-4-6` across extractors, dev config, and self-hosting docs
- Redirect calendar settings actions with verified routes (`~p"/users/settings"`)

## [0.15.0] - 2026-07-17

### Changed

- Route contractor SMS turn handling through unified extractor `turn_intent` (confirm pending jobs/booking outreach, slot approve/reject, playbook update, scheduling setup reply, or normal CRM ops) instead of regex short-circuits before AI
- Pass pending-turn context (pending job creates, booking outreach, slot approval, setup session) into the unified SMS extractor prompt
- Classify dual-role phone routing with `SmsRoleClassifier` (Anthropic) instead of keyword regexes
- Drop keyword-based booking consent gating; keep AI-emitted `booking_initiate` and build pending proposals from `proposed_booking_initiates` / undated creates
- Apply slot approvals via AI `turn_intent` (`slot_approve` / `slot_reject`) rather than yes/no regex matching

### Added

- `turn_intent` on unified SMS extraction results
- `RompCrm.Ai.SmsRoleClassifier` with Anthropic and DeterministicStub adapters
- `SlotApprovals.handle_contractor_decision/3`

## [0.14.2] - 2026-07-17

### Fixed

- Continue normal SMS extraction when customer scheduling SMS is disabled and there is no pending booking proposal, instead of always replying that scheduling texts are turned off
- Treat booking-confirm SMS only as short start-anchored affirmatives so phrases like "do it tomorrow" or "Ok don't text…" do not hijack the confirm path
- Sync SMS job contact updates (phone, name, address, …) onto the linked client so `merge_client_onto_job` does not blank them on the next read

### Added

- `Clients.update_job_contact_and_sync/2` for job patches that include client contact fields

## [0.14.1] - 2026-07-15

### Changed

- Print report PDF header: show only `Report for {date range}` (activity) or `Customer list`; omit Romp CRM branding, workspace name, and generated timestamp
- Customer list PDF: omit workspace name from each customer card
- Activity PDF: omit New leads and Jobs worked on sections (covered by job hours and open jobs)
- Activity PDF Jobs section: rename from open-only title; include open jobs plus jobs marked done with `updated_at` in the report range

## [0.14.0] - 2026-07-15

### Added

- Settings **Print reports (PDF)**: download Activity or Customer list as a real PDF attachment (ChromicPDF + system Chromium)
- **`RompCrm.PrintReports`**: activity report over a date range (job hours, clock punches, new leads, jobs worked on) plus open non-completed leads/jobs; full customer list with contact and address fields
- **`POST /users/settings/reports`**: owner-workspace-scoped PDF download

### Changed

- Start ChromicPDF in the application supervision tree when `chromic_pdf_enabled` is true (disabled in test; stub PDF adapter used there)

## [0.13.3] - 2026-07-15

### Added

- Chats compose: attach image button on the **agent** thread and on taken-over client threads; upload to `uploads/chat-media/`
- Agent chat MMS: pass attached images through the same vision pipeline as inbound SMS
- Client chat MMS: send attached images via Twilio (`MediaUrl`)
- **`Messages.send_mms/3`**: outbound MMS with optional caption and media URLs
- **`ChatMedia`**: store chat attachment bytes and build public HTTPS URLs

### Changed

- **`AgentChat.send_message/4`**: accept optional `media_urls`; allow photo-only sends
- **`ClientChats.send_human_message!/5`**: accept optional `media_urls`; allow photo-only sends
- **`SmsMms.extract_media_urls/1`**: include `/uploads/chat-media/` URLs in chat bubble photo thumbnails
- **`MmsImageDownload`**: read local chat-media files for vision (no Twilio round-trip)

## [0.13.2] - 2026-07-15

### Fixed

- Detect MMS image media type from file magic bytes before sending to Anthropic so mislabeled Twilio Content-Type headers (e.g. JPEG labeled as PNG) no longer return HTTP 400

## [0.13.1] - 2026-07-15

### Changed

- Disable customer scheduling SMS by default (`customer_scheduling_sms_enabled` / `CUSTOMER_SCHEDULING_SMS_ENABLED`); gate booking initiate, client booking replies, escalation relays, slot offers, and web booking confirmation texts until explicitly re-enabled

## [0.13.0] - 2026-06-11

### Added

- **Scheduling setup (SMS)**: gate first customer scheduling text behind a one-time contractor onboarding thread (work hours, outreach style A/B/C, optional open-ended playbook description)
- **`scheduling_playbook_rules`**: persist greeting templates, confirm-before-offer, min lead days, scheduling bias, and custom instructions extracted from natural language
- **`SchedulingPlaybookExtractor`**: parse structured setup replies, open-ended playbook text, and ongoing preference updates from contractor SMS
- **`TimezoneInference`**: default scheduling time zone from phone area code (or connection IP on settings save) — no timezone prompt during setup
- **`booking_slot_approvals`**: when confirm-before-offer is enabled, hold customer slot offers until contractor replies YES via SMS
- **Settings**: customer outreach style, minimum days notice, slot preference, and playbook rule list with remove action

### Changed

- **`ClientInvitationSms`**: honor outreach style and custom greeting templates from playbook
- **`AvailabilitySummary`**: enforce `min_lead_days` and `scheduling_bias` on slot lists before AI or customer SMS see them
- **Customer booking AI**: inject `scheduling_playbook` context; support `request_slot_approval` action when confirm-before-offer is active
- **Unified contractor SMS AI**: include scheduling prefs/playbook snapshot in extraction context

## [0.12.11] - 2026-06-11

### Changed

- **Chats mobile thread**: restore inner rounded border on the message panel; keep outer thread card borderless on small screens

## [0.12.10] - 2026-06-11

### Fixed

- **Chats mobile thread**: remove negative-margin bleed that clipped content under `overflow-hidden` parents; use compact main padding instead; use `svh` viewport and safe-area footer inset

## [0.12.9] - 2026-06-11

### Changed

- **Chats mobile thread**: remove outer rounded card border and bleed content closer to screen edges; drop inner message panel border on small screens

## [0.12.8] - 2026-06-11

### Fixed

- **Chats thread scroll on mobile**: cap app shell at `h-dvh` instead of `min-h-dvh`; give thread card `flex-1` on all breakpoints; use flex column with `flex-1 basis-0` message panel
- **Chat compose**: disable textarea resize so it cannot expand the thread layout

## [0.12.7] - 2026-06-11

### Fixed

- **Chats scroll**: use viewport-filling app layout and CSS grid (`minmax(0, 1fr)` message row) so long threads scroll inside the message panel instead of growing the page

## [0.12.6] - 2026-06-11

### Fixed

- **Chats mobile thread**: pin active conversation to viewport height with message list scrolling inside `#chats-panel`; remove nested scroll on `chat_thread`

## [0.12.5] - 2026-06-11

### Changed

- **Chats mobile layout**: show full-width conversation list or full-width active thread (with back button); keep side-by-side sidebar on `md` and wider

## [0.12.4] - 2026-06-11

### Fixed

- **Chats takeover confirm dialog**: use standard modal component with solid `bg-base-100` panel and dimmed backdrop instead of transparent daisyUI `modal-box`

## [0.12.3] - 2026-06-11

### Fixed

- **Chats human takeover**: record inbound customer SMS during takeover after the booking link is already `booked` (previously only `pending` links routed client SMS, so replies like Jasmine's were dropped)
- **`ClientChats.record_inbound_while_taken_over`**: key off active takeover rows instead of pending booking links
- **`SmsInboundRoleRouter`**: route to client scheduling when a phone has an active takeover even without a pending link

## [0.12.2] - 2026-06-11

### Fixed

- **Scheduling agent test workspace**: fix contractor escalation replies silently failing — outer `case` only matched 2-tuples, so handled escalations returning `{:ok, state, meta}` crashed the LiveView
- **Scheduling agent test workspace**: show friendly AI error messages instead of raw `inspect/1` tuples when Anthropic calls fail

## [0.12.1] - 2026-06-11

### Fixed

- **Scheduling agent test sandbox**: escalate client scope questions to the contractor pane; notify contractor on confirmed bookings and soft availability (mirrors production `EscalationCoordinator` / technician booking SMS)
- **Customer booking AI prompt**: treat added work beyond the original job as `escalate_question`, not silent `job_updates`
- **Chats takeover**: fix 500 after confirming takeover when reloading sidebar (`get_in` on `Takeover` struct)
- **Twilio webhook**: match `{:ok, :human_takeover_silent}` before generic `{:ok, _reply}` clause

## [0.12.0] - 2026-06-11

### Added

- **Chats page** (`/chats`, `/chat` alias): sidebar to switch between the RompCRM agent and customer scheduling SMS threads
- **Client chat takeover**: pause the scheduling agent, text the customer live by SMS, and hand off back with customer notifications; full thread history (agent, customer, and human) feeds back into the scheduling agent via `list_client_turns_for_ai/3`
- **`ClientChats`** and **`client_chat_takeovers`** table to track active human takeover per business + client phone
- **`SmsConversations.list_client_thread_messages/3`**: load client scheduling threads for the Chats UI
- **`Conversations.format_client_thread_rows/2`**: messenger rows for customer SMS threads

### Changed

- Rename nav **Chat** → **Chats**; route primary path to `/chats`
- **`CustomerBookingProcessor`**: when a thread is human-taken-over, record inbound SMS without scheduling-agent auto-reply
- **`SmsConversations`**: support `sms_human` channel for live technician outbound; PubSub on client thread updates
- **Customer booking AI prompt**: label prior human messages as "Team member" in thread context

### Removed

- **`AgentChatLive`** (replaced by **`ChatsLive`**)

## [0.11.0] - 2026-06-11

### Added

- **Scheduling agent test workspace** (`/scheduling-agent-test`): two-pane sandbox from Settings to preview contractor ↔ agent and client ↔ scheduling assistant without creating real jobs, clients, or SMS; session stored in `scheduling_agent_test_sessions`
- **`Bookings.ClientInvitationSms`**: shared first-customer scheduling SMS composer used by production orchestrator and the test sandbox

### Changed

- **Settings → Scheduling & calendars**: add link and explainer to open the scheduling agent test workspace
- **`ChatComponents`**: optional `submit_event` on compose forms and configurable typing-indicator label
- **Booking orchestrator**: delegate first-customer SMS text to `ClientInvitationSms`

## [0.10.6] - 2026-06-11

### Added

- **`Bookings.AvailabilitySummary`**: compute `open_slots`, `local_slot_offerings`, and contractor phrasing from the real availability engine (concrete appointment times, not workday bounds)
- **`Bookings.JobScheduleSync`**: when a booking is confirmed, set the linked job's `scheduled_on`, `scheduled_time`, work-item dates, and move `lead` → `pending`

### Changed

- **Customer booking SMS AI**: only offer times from `local_slot_offerings` / `open_slots`; forbid inventing broad windows like "8am–3:30pm today"
- **Contractor booking ask SMS**: list specific local appointment times instead of vague "Thursday morning/afternoon" day-parts
- **Confirmed bookings** (SMS, web, technician confirm): sync schedule onto the linked job via `JobScheduleSync`

## [0.10.5] - 2026-06-11

### Added

- **Pending booking proposals** (`sms_pending_booking_proposals`): when a contractor adds a lead with customer phone and no visit date, store a proposed customer scheduling text until they reply YES (or similar); apply via `SmsPendingBookingProposals`
- **`SmsBookingConsent`**: block same-turn `booking_initiate` with new job creates unless the contractor explicitly asked to text/schedule; skip outreach when the create carries a `scheduled_on` or timed work item
- **`Bookings.OpeningsPreview`**: shared openings phrase for contractor ask-SMS and first customer booking SMS

### Changed

- **Contractor SMS booking flow**: ask before texting customers to schedule; suggest calendar openings in the ask; only send the customer SMS after confirmation (or explicit same-message consent)
- **Unified extractor prompt**: use `proposed_booking_initiates` instead of auto-`booking_actions` on new leads; do not offer scheduling when the contractor already stated a visit date/time
- **Removed** server-side `SmsBookingInitiateInference` auto-initiate on job create

## [0.10.4] - 2026-06-11

### Added

- **SMS inbound role router**: when a phone number is both a registered Romp CRM user and an active client in a booking conversation, default inbound SMS to the **client scheduling** thread; ask a clarifying question when the message clearly targets contractor CRM work (`SmsInboundRoleRouter`, `sms_inbound_role_prompts`)
- **Booking initiate inference**: when contractor SMS creates a lead with customer phone and work description but the AI omits `booking_actions`, synthesize a `booking_initiate` op server-side unless the contractor said lead-only (`SmsBookingInitiateInference`)

### Changed

- **Twilio SMS webhook**: route through `SmsInboundRoleRouter` before contractor vs client processors
- **Unified extractor prompt**: default to create + booking initiate when the contractor supplies customer name, phone, and work (unless they explicitly want a lead only)

## [0.10.3] - 2026-06-10

### Added

- **Scheduling question escalations**: when a client asks something the booking agent cannot answer (pricing, policies, disposal fees, etc.), escalate via `escalate_question` instead of guessing — reply to the client that a live team member is checking, text the contractor with the question and client phone, and track open escalations in `booking_escalations`
- **Contractor escalation replies**: contractor SMS is routed through `EscalationCoordinator` when open escalations exist — handle direct outreach, provide an answer, confirm whether to save a **scheduling memory**, then relay the answer to the client
- **Per-business scheduling memories** (`scheduling_memories`): stored answers from escalations; included in customer booking AI context so similar future questions can be answered without re-escalating

### Changed

- **Customer booking extractor prompt**: check `scheduling_memories` before escalating; never invent pricing or policy answers
- **Contractor SMS inbound**: try booking escalation handling before the unified CRM extractor when the workspace has open escalations

## [0.10.2] - 2026-06-10

### Added

- **Jobs**: `customer_comments` text field — verbatim issue or work-request description from the customer during SMS self-scheduling
- **Booking intake**: `Bookings.Intake` snapshot and `job_updates` handling in the customer booking SMS agent — collects work description, service address confirmation, email, and billing address (same as service or different); persists to the linked job and client; creates a job row when the booking link has none yet
- **Booking links**: `intake_flags_json` to track billing-address confirmation during the conversation

### Changed

- **Customer booking extractor prompt**: instruct the agent to ask for missing intake in one fluid message when possible, confirm on-file addresses/email, and populate `job_updates` from customer replies (may accompany a scheduling action)
- **Jobs UI / export**: show and export `customer_comments` alongside work description

## [0.10.1] - 2026-06-10

### Changed

- **Booking initiate**: link the booking to a job created by the same inbound agent message (matched by phone, else client name) and reuse that job's client; otherwise reuse an existing business client matched by normalized phone before creating a new one — pass `created_jobs` from `SmsInboundProcessor` job results into `Bookings.Orchestrator`
- **First customer SMS**: include up to two concrete openings ("We have openings Tuesday afternoon or Wednesday morning") computed from merged busy blocks and the technician's scheduling prefs over the next 7 days, and introduce the sender as "the scheduling assistant for <business>"
- **Technician booking confirmations** (SMS and web bookings): rephrase as "I reached out to <client> and we've scheduled the <job> for <window>", append the service address from the linked job or client when available (`Bookings.service_address_for_link/1`), and add a reply-to-reschedule prompt
- **Unified extractor prompt**: document that one message may emit both a `job_actions` create and a `booking_actions` initiate (server links them by phone), and instruct the model to ask for a corrected phone number instead of emitting `initiate` when the stated phone is not a valid US number

## [0.10.0] - 2026-06-10

### Added

- **Customer self-scheduling**: booking links (`booking_links`), confirmed appointments (`bookings`), and soft-availability requests (`booking_requests`) with a public mobile-first LiveView at **`/book/:token`** (slot picker, soft availability form, invalid/expired/booked states) and an nginx short link **`https://rompcrm.com/book/<token>`**
- **Technician AI booking actions**: `booking_actions` in the unified SMS extractor (`initiate`, `update_duration`, `confirm_soft`, `cancel`) executed by **`Bookings.Orchestrator`** — AI estimates a duration range, creates the link, and texts the client an opening SMS with the booking URL
- **Client-side AI SMS booking**: **`CustomerBookingProcessor`** routes inbound SMS from phones with active booking links (Twilio webhook unknown-sender branch) through **`CustomerBookingExtractor`** (Anthropic + deterministic stub); supports hard bookings with conflict checks, soft availability capture, and cancellations, recording exchanges on a separate `client` SMS thread (`thread_kind` column)
- **Multi-business collision handling**: when one client phone has active booking links with several businesses on the shared Twilio number, the AI asks a clarifying question and no booking action runs until the business is resolved
- **Availability engine**: **`RompCrm.Scheduling.AvailabilityEngine`** (merge busy blocks, generate open slots from working-hour prefs, conflict check) with **`Prefs`** (timezone, workday hours, work days, buffer) stored on `users.scheduling_prefs_json`
- **External calendars (read-only free/busy)**: `CalendarSource` behaviour with **`InternalJobsSource`** (scheduled jobs + confirmed bookings), **`GoogleCalendarSource`** (OAuth freebusy with transparent token refresh), and **`AppleCalendarSource`** (iCloud CalDAV via app-specific password); credentials AES-256-GCM encrypted at rest (`calendar_credentials` table); **`RompCrm.Scheduling.combined_busy_blocks/4`** merges all sources and degrades gracefully when a provider errors
- **Settings**: Scheduling & calendars section — working hours/work days/buffer/timezone form, Google Calendar connect/disconnect (OAuth, `calendar.freebusy` scope), Apple Calendar connect/disconnect (Apple ID + app-specific password)
- **Bookings page** (`/bookings`): pending availability replies with pick-a-time confirm flow, open booking links with duration edit and cancel, upcoming bookings with cancel; confirmations and cancellations text the client
- **Expiry sweep**: scheduler tick marks pending booking links past `expires_at` as expired
- **Env**: `GOOGLE_CALENDAR_CLIENT_ID` / `GOOGLE_CALENDAR_CLIENT_SECRET` / `GOOGLE_CALENDAR_REDIRECT_BASE`, `CALENDAR_CREDENTIALS_KEY`, `BOOKING_LINK_BASE_URL` documented in `deploy/romp-crm.env.example`

### Changed

- **SMS conversations**: contractor-thread queries filter on `thread_kind = "contractor"`; add `record_client_message/5` and `list_client_turns_for_ai/3` for client threads

## [0.9.112] - 2026-06-09

### Fixed

- **Registration**: when the same email registers again during an active cardless free trial, resend the magic link and redirect to log-in instead of sending the user to PayPal checkout
- **Subscribe page**: hide PayPal resume checkout when the pending account already has active trial access
- **Registration form**: disable submit button after first click to reduce accidental double registration

## [0.9.111] - 2026-06-06

### Added

- **Clients**: persistent client records per workspace with **`/clients`** list/expand/edit/delete, linked jobs, and **+ Job** per row
- **Jobs**: optional client picker on create; AI/deterministic match when typing new contact details; confirmation dialog when editing contact fields on linked jobs (updates client and all linked jobs)
- **SMS AI**: clients snapshot in unified inbound extraction; optional **`client_id`** on job creates; server links or creates clients after SMS job creates
- **Data export**: **`clients.csv`** checkbox in Settings → Data export (email, download, and scheduled exports)

### Changed

- **Jobs export**: backfill migration links existing jobs to deduped client rows

### Fixed

- **`Clients.delete_client_and_jobs/1`**: reload linked jobs before delete so orphaned job rows are removed
- **`JobsList.effective_schedule_date/1`**: treat unloaded **`work_items`** as empty

## [0.9.110] - 2026-05-30

### Added

- **Accounts**: email **`SIGNUP_NOTIFY_EMAILS`** (comma-separated) when a new user registers, joins via invitation, or is created from gift redemption

### Fixed

- **Migrations**: rename duplicate **`20260530120000`** SMS channel migration to **`20260530120001`**

## [0.9.109] - 2026-05-30

### Changed

- **README**: trim screenshots to four landing-page highlights (jobs list, job detail, tasks/materials, SMS lead capture); remove **hromp.com** references from public URL and Twilio examples

## [0.9.108] - 2026-05-30

### Changed

- **README**: replace outdated screencaps with the 22 landing-page screenshots; remove the screencast video section and retire old `docs/screencaps/1000001495*` assets

## [0.9.107] - 2026-05-30

### Changed

- **Jobs (web form)**: rename work item date label from "Scheduled (optional)" to "Scheduled"

## [0.9.106] - 2026-05-30

### Added

- **Agent / SMS AI**: include recently deleted jobs (from audit log) in extraction context so the model knows when a job from chat history was removed
- **Demo scripts**: `seed_demo_workspace.exs`, `seed_demo_reminders.exs`, and helpers to dedupe/fix demo job names

### Fixed

- **Jobs (web form)**: drop blank default work-item rows from indexed form params so save no longer crashes with `NOT NULL` on `job_work_items.title`
- **Jobs**: allow creating a lead with only address, work summary, phone, or notes (client name optional); reject saves with no identifying details
- **Agent / SMS AI**: instruct model to use **create** for new jobs when no snapshot row matches, including reusing a client name after delete (duplicate names allowed)

## [0.9.104] - 2026-05-30

### Fixed

- **Chat**: fix 500 on `/chat` caused by `attr` declarations bound to the wrong component (`chat_compose` missing `placeholder`)

## [0.9.103] - 2026-05-30

### Added

- **Agent / SMS AI**: enrich partial address updates with existing job context, US address parsing, and geocoding to fill structured fields and ZIP
- **Agent / SMS AI**: shared work-description ↔ work-item guidance for creates, add-on scope, and description-only edits (`WorkItemsPrompt`)
- **SMS replies**: confirm service and billing address updates with the full formatted address saved on the job
- **Chat**: show the user’s message immediately on send and a “RompCRM is typing…” indicator while the agent responds
- **Chat compose**: Enter sends, Shift+Enter inserts a newline (`ChatCompose` hook)
- **Jobs**: phone and email validation (E.164 / pattern) on forms and inline edit; `ContactInfo` module and `PhoneField` component
- **Jobs**: inline expanded edit guard (one field at a time; flash save/cancel when switching with unsaved edits)
- **Jobs**: billing-address toggle hook and programmatic Google Places autocomplete (`AutocompleteSuggestion` dropdown)

### Changed

- **Google address autocomplete**: parse `addressComponents` / `postalAddress`; fix selection via `pointerdown`; improve billing toggle wiring
- **Agent prompts**: require structured address fields, snapshot merge examples, and full-address confirmation copy
- **Jobs expanded card**: single-column layout on desktop so edit pencils align; photo section tweaks

### Fixed

- **Chat**: avoid blocking the LiveView until the agent finishes by processing sends asynchronously

## [0.9.102] - 2026-05-18

### Added

- **Jobs**: structured service and optional billing addresses (line 1/2, city, state, ZIP) with Google Places Autocomplete and geocode confirmation (“Use what I entered” vs “Use suggested address”)
- **SMS AI**: accept structured address fields, flat `address`, and separate billing address on create/update
- **Docs**: Google Maps Platform API key setup in self-hosting guide, `deploy/README.md`, env examples, and VPS migration checklist

### Changed

- **Jobs list / form**: replace single address text field with structured address UI; legacy `address` column kept in sync for sorting

## [0.9.96] - 2026-05-18

### Changed

- **Chat**: restore comfortable bubble padding (`px-3 py-1.5`, `leading-snug`) now that empty-bubble whitespace no longer inflates vertical space

## [0.9.95] - 2026-05-18

### Fixed

- **Chat**: fix 500 on `/chat` when a message has no display text (photo-only or empty SMS) by using boolean-safe content checks instead of `&&`/`or`

## [0.9.94] - 2026-05-18

### Fixed

- **Chat**: remove extra blank space in bubbles caused by `whitespace-pre-wrap` on the bubble container preserving template newlines; skip empty bubbles

## [0.9.93] - 2026-05-18

### Changed

- **Chat**: reduce vertical padding inside message bubbles

## [0.9.92] - 2026-05-18

### Changed

- **Chat**: label your own messages **You** (in-app) or **You (sms)** instead of **You (name)**

## [0.9.91] - 2026-05-18

### Changed

- **Chat**: tighten bubble padding, increase corner radius, and use solid outgoing colors for readable dark-mode text

## [0.9.90] - 2026-05-18

### Added

- **Chat** page (`/chat`): messenger-style agent thread combining SMS and in-app messages for the workspace
- **`RompCrm.Conversations`**, **`RompCrmWeb.ChatComponents`**, and **`RompCrm.SmsInboundProcessor`** for modular future client chat threads
- **`sms_conversation_messages.channel`**: distinguish `sms` vs `in_app` delivery

## [0.9.89] - 2026-05-18

### Changed

- **Web job photo lightbox**: full-viewport black overlay; photo fills the screen; minimal chevron nav, top-right close, bottom-right download icon; pinch (and trackpad wheel) zoom instead of +/- controls

## [0.9.88] - 2026-05-18

### Changed

- **Web job photos**: show **Download all (zip archive)** only in photo edit mode; rename button label

## [0.9.87] - 2026-05-18

### Added

- **Web job photos**: two-step confirmation before delete-all (step 1 Continue, step 2 permanent delete)
- **Web job photos**: **Download all** on each job (ZIP with a folder for that job); **Download** in the lightbox for one photo
- **Settings → Data export**: **Download all photos (ZIP)** for selected owner workspaces (one folder per job); photos are not included in CSV email/scheduled exports

## [0.9.86] - 2026-05-18

### Changed

- **Web job photos**: restore thumbnail grid as the default view (click opens lightbox); green pencil enters edit mode with ↑/↓ reorder and per-photo delete
- **Web job photos**: add red × on the section header to delete all photos with a two-step confirmation banner
- **Web job photos**: remove delete from the lightbox viewer

## [0.9.85] - 2026-05-18

### Added

- **Web job photos**: lightbox viewer with zoom (pinch, wheel, +/- controls), prev/next within the job, and keyboard arrows
- **Web job photos**: delete photos from the gallery row or lightbox; reorder with ↑/↓ controls
- **DB**: add `sort_order` on `job_photos` for manual gallery ordering

## [0.9.84] - 2026-05-18

### Fixed

- **Web job photos (mobile)**: surface server/nginx upload errors in the modal (including photo too large)
- **Web job photos**: include `_csrf_token` in multipart POST body as well as the CSRF header

## [0.9.83] - 2026-05-18

### Fixed

- **Web job photos (mobile)**: replace LiveView uploads with direct `fetch` POST to `/jobs/:id/photos` (JSON response); gallery and camera use native overlaid file inputs (iOS-compatible)
- **Web job photos (mobile)**: show **Use camera** as a native capture input on small screens; desktop keeps webcam capture

## [0.9.82] - 2026-05-18

### Fixed

- **Web job photos (mobile)**: accept all `image/*` types; wrap gallery file input inside the button label (iOS picker registration)
- **Web job photos (mobile)**: disable modal click-away dismiss so returning from the native camera does not cancel the upload
- **Web job photos (camera)**: pass upload name `job_photos` to client hooks (was incorrectly using upload ref)
- **Web job photos (camera)**: on mobile, **Use camera** opens the phone camera directly; on desktop, opens webcam capture automatically

### Changed

- **Web job photos**: save each photo automatically when upload completes; modal shows saved count and a **Done** button instead of manual **Upload N photo(s)**

## [0.9.81] - 2026-05-18

### Added

- **Web job photos**: add **Add photos…** on expanded jobs; modal supports gallery pick, drag-and-drop, webcam capture, and phone camera (`capture="environment"`)
- **Jobs**: broadcast `{:updated, job}` after a photo is saved so the list refreshes without reload

## [0.9.80] - 2026-05-29

### Added

- **SMS MMS vision**: send inbound images to Claude; classify SMS/email screenshots and handwritten notes
- **SMS proposed leads**: extract lead/job fields from correspondence images into `proposed_job_creates`; store pending until contractor replies CONFIRM (or yes/create); attach source image to each created job
- **DB**: `sms_pending_job_proposals` table for per-phone pending proposals

## [0.9.79] - 2026-05-29

### Fixed

- **SMS replies**: when photos were saved but the model's `assistant_sms` is still a "which job?" style question, send the save confirmation instead of the clarify text

## [0.9.78] - 2026-05-29

### Fixed

- **SMS MMS photos**: record Twilio `source_media_url` on `job_photos` and skip re-downloading the same URL on a job (prevents duplicate files when the user clarifies the job in a follow-up text)
- **SMS AI**: instruct model to ask which job before attaching when ambiguous, and not to re-attach URLs already saved on that job in the thread

## [0.9.77] - 2026-05-29

### Fixed

- **Job photos**: store and serve uploads from persistent `var/static` (or `JOB_PHOTO_STATIC_DIR`) instead of the versioned release `priv/static` tree, so photos survive `mix release` upgrades
- **Job photos**: add `scripts/migrate-job-photo-uploads-to-var-static.sh` to recover files left under old release directories

## [0.9.76] - 2026-05-29

### Fixed

- **SMS MMS orphan attach**: do not attach photo-only messages using client names from older texts; require a caption on the current MMS; attach only this message's `MediaUrl`, not URLs from prior inbound rows

## [0.9.75] - 2026-05-29

### Fixed

- **SMS MMS**: parse `Content-Type` from Twilio/Req download responses when the header value is a list (e.g. `["image/jpeg"]`), so orphan photo attach no longer crashes the webhook before the reply SMS is sent

## [0.9.74] - 2026-05-29

### Fixed

- **SMS MMS**: store non-empty inbound body text (attachment URLs) when Twilio sends an image-only message; avoid HTTP 500 from blank `body` validation
- **SMS MMS**: attach photos from current webhook or recent conversation URLs when the AI omits `attach_photo` but job context is inferable from recent messages
- **Jobs UI**: serve job photo thumbnails and links with the app path prefix (`PathPrefix.static_upload_path/1`)

## [0.9.73] - 2026-05-20

### Changed

- **PayPal billing**: set `PAYPAL_TRIAL_DAYS` default to 0 and provision plans without a PayPal trial cycle (in-app signup trial remains 30 days via `SIGNUP_TRIAL_DAYS`)
- **Config**: decouple `signup_trial_days` from `paypal_trial_days` in `runtime.exs`

## [0.9.72] - 2026-05-19

### Changed

- **Registration**: all hosted sign-ups receive a 30-day trial with no credit card; PayPal billing is required only after trial expiry via the subscription page
- **Trial defaults**: set `PAYPAL_TRIAL_DAYS` and `signup_trial_days` default to 30 (was 14)

## [0.9.71] - 2026-05-19

### Added

- **Registration**: grant 30-day cardless trial (no PayPal) for `jvzieger@icloud.com` and `jzieger2@gmail.com` on normal sign-up, matching the signed promo link flow

## [0.9.70] - 2026-05-17

### Added

- **Workday timeclock**: manually edit past punches and log past shifts on `/my-timeclock`; owners can manage entries on employee detail
- **Employee time audit**: structured audit `changes` with `record_kind`, `via`, and field-level diffs distinguishing live punches, SMS punches, shift logs, and later adjustments
- **SMS employee time**: `log_shift` (e.g. "Bob worked 8am–4pm") and `adjust_entry` intents; employee snapshot includes `recent_entries` for corrections
- **DB**: `clock_in_kind` / `clock_out_kind` on `employee_time_entries` (`live_punch`, `sms_punch`, `manual_entry`, `sms_shift`)

### Changed

- **SMS unified prompt**: clarify workday timeclock vs job `time_actions`; document new employee intents

## [0.9.69] - 2026-05-17

### Added

- **Jobs**: add optional **`client_email`** on job/customer records (migration, forms, inline edit, CSV export, SMS AI snapshot and extractor)

## [0.9.68] - 2026-05-16

### Added

- **`RompCrm.BusinessAuditLogs.Detail`**: build human-readable **`summary`**, structured **`changes`** (materials with quantity/description, work items, field updates), and optional **`sms_inbound`** / **`sms_outbound`** on audit metadata
- **`audit_log.csv` export**: add **`summary`**, **`changes`**, **`sms_inbound`**, and **`sms_outbound`** columns (full JSON remains in **`metadata`**)

### Changed

- **SMS (`TwilioWebhookController`)**: record inbound/outbound message text on each successful SMS audit row; compute job create/update **`changes`** from the AI patch and before/after job snapshots (material lines appended on update)
- **Web (`JobsLive`, `JobFormComponent`)**: audit material edit/delete, job delete, and root materials list replacements with explicit **`changes`**

## [0.9.67] - 2026-05-15

### Fixed

- **`Jobs.update_job/2`**: when **`materials`** are present (e.g. SMS add), **append** new material rows after existing ones instead of deleting all job materials and inserting only the new lines

### Changed

- **SMS Anthropic prompts**: document that **`updates.materials`** must list **only new** lines (server appends; repeating snapshot rows would duplicate)

## [0.9.66] - 2026-05-15

### Fixed

- **`SmsJobExtractor.normalize_materials_for_patch/1`**: forward **`quantity`** from SMS/AI JSON into job create/update patches so **`Jobs.normalize_material_specs/1`** persists counts greater than one (previously only **`description`** was kept and quantity fell back to **1** when the count was not duplicated at the start of the description)

## [0.9.65] - 2026-05-14

### Added

- **`docs/vps-migration-rompcrm.md`**: operator checklist for moving **`rompcrm.com`**, nginx, TLS, SQLite, **`romp-crm`** release, and secrets to a new VPS with minimal downtime
- **`deploy/README.md`**: link the VPS migration doc from the deploy guide

### Changed

- **`RompCrm.EmailHtml`**: simplify transactional email layout to a **light** palette (aligned with app light mode); keep the **`email_logo_url`** image with a visible **“Romp CRM”** wordmark and **light** header cell so blocked images do not leave a dark placeholder; tighten typography; use **underlined** footer and fallback links for clarity
- **`UserNotifier`**: align gift callout inline styles with the light email palette

## [0.9.63] - 2026-05-08

### Changed

- **`User.profile_changeset`**: clearer **`phone_normalized`** uniqueness copy when the number is already on another account
- **`SmsAssistantIntroComponent`**: flash the first profile validation error (e.g. duplicate mobile) when **Save and text me** fails
- **`UserSettingsController`**: flash the first profile validation error on failed **Save profile**
- **Account Settings** help text: document one mobile number per product account

## [0.9.62] - 2026-05-08

### Added

- **`Businesses.ensure_default_workspace_if_empty/1`**: when **`User.may_create_business?/1`** and the user has no memberships, create **`My workspace`** (same as **`create_business/2`**) so **`UserAuth.on_mount :ensure_business_scope`** never redirects new owners away from Jobs before the first-login SMS intro finishes

## [0.9.61] - 2026-05-08

### Changed

- **README.md**: refresh overview (public hosts, self-hosting pointers, Twilio/Paywall env summary, features pointer to **CHANGELOG**)
- **deploy/README.md**: document **rompcrm.com** mount, self-host **`SUBSCRIPTION_PAYWALL_ENABLED`** default, link **docs/self-hosting-rompcrm.com.html**, Twilio webhook examples for **hromp.com** or **rompcrm.com**
- **deploy/romp-crm.env.example**: expand commented blocks for mail, voice, PayPal paywall, admin, and email branding
- **docs/self-hosting-rompcrm.com.html**: add maintained self-hosting HTML guide (canonical live URL **https://rompcrm.com/self-hosting.html**)

## [0.9.60] - 2026-05-08

### Added

- **Cardless 30-day promo registration**: signed query param **`t`** on **`GET /users/register`** (session **`cardless_trial_signup`**) hides PayPal plan UI; **`POST`** creates the user, sets **`gift_access_until`** 30 days ahead via **`Accounts.apply_cardless_promo_trial/2`**, and emails the magic link; when the email already had an abandoned paywall row (**`register_user/2`** returns that user), redirect to **`/subscribe`** without stacking the promo; add **`mix romp_crm.cardless_trial_link`** (and **`bin/romp_crm rpc`** per task moduledoc) to print the HTTPS URL

## [0.9.59] - 2026-05-08

### Added

- **Jobs list job hours**: edit (pencil) and remove (red X) actions per row; **Edit job hours** reuses the time modal with **Update job hours**; optional **End** left blank keeps an in-progress row open

### Changed

- **Jobs list delete job**: replace single **Delete** text control with **`RompCrmWeb.JobDeleteBar`** — explicit **Delete job** / **Continue** / **Delete job permanently** flow (**three steps** with **Cancel delete**); remove delete control from the collapsed table header cell (desktop) so the flow lives in the expanded panel with room for warnings

## [0.9.58] - 2026-05-08

### Changed

- **Transactional email**: send **multipart HTML + plain text** for magic link, confirmation, email change, data export, gift subscription, and workspace invitations; add **`RompCrm.EmailHtml`** layout with **logo**, **rompcrm.com** palette (navy panel, sky CTA), and configurable **`email_logo_url`** / **`email_brand_base_url`** (optional production overrides **`EMAIL_LOGO_URL`**, **`EMAIL_BRAND_BASE_URL`**)

## [0.9.57] - 2026-05-08

### Changed

- **LiveView disconnect toasts**: use **`alert-info`** styling and copy **`Reconnecting...`** (no error title) for transient client/server disconnect banners

## [0.9.56] - 2026-05-14

### Fixed

- **Workday timeclock**: auto-link **`employees`** row to the logged-in user when the roster **`email`** matches and **`user_id`** was unset (e.g. owner adds themselves by email only); **`EmployeePermissions`** and **`MyTimeclockLive`** use **`get_or_link_employee_for_user/2`**

## [0.9.55] - 2026-05-08

### Fixed

- **SMS `reminder_actions`**: interpret **naive** `fire_at` strings as wall clock in the user’s **SMS reminder profile time zone** (Settings), not as **`Etc/UTC`**; prevents immediate delivery when the model meant local afternoon (e.g. 3:30pm)

## [0.9.54] - 2026-05-08

### Added

- **`/reminders`** LiveView: list pending SMS reminders, create (date + optional time in profile time zone), edit, delete
- **`jobs.scheduled_time`** and **`job_work_items.scheduled_time`**: optional wall time next to schedule date in Jobs UI (compact date + time inputs)
- **SMS schedule nudges** for **work items** with their own **`scheduled_on`** when it differs from the job’s date (same calendar date still uses the job-only ping to avoid duplicates); job SMS lines include optional time

### Changed

- **Gift email links** use **`/gift/claim/:token`**: new recipients get a confirmed account and login in one step; existing users are sent to login with email prefilled and return to claim
- **Workspace nav**: **Reminders** link next to Job list

## [0.9.53] - 2026-05-14

### Added

- **Admin** (`/admin`): dashboard for configured admin emails only — user counts, subscription status breakdown, per-user workspace/job counts, gift-subscription sender
- **`gift_subscriptions`** table and **`users.gift_access_until`**: gift tokens emailed to recipients; redeem (logged in or at registration) grants access without PayPal; **`Billing.subscription_active?/1`** treats unexpired gift access like an active subscription
- **Gift redemption** at **`/gift/redeem/:token`** (public page + POST when logged in); registration with **`?gift=`** skips hosted PayPal when the token is valid
- **`config :romp_crm, :admin_emails`** (default **`151henry151@gmail.com`**); production override via **`ADMIN_EMAILS`** (comma-separated) in **`config/runtime.exs`**
- Footer **Admin** link for admin users only

## [0.9.52] - 2026-05-14

### Changed

- Shorten in-app helper copy (settings, SMS intro modal/flashes, support, job form, subscribe) and outbound welcome SMS; tighten data-export email bodies and settings/export controller flashes

## [0.9.51] - 2026-05-08

### Added

- **`users.data_export_kinds_json`** and **`users.data_export_business_ids_json`**: persist export checkbox selections for scheduled emails

### Changed

- **`DataExport.deliver_email_export/1`** (scheduled): use saved kinds and workspace ids (same as settings checkboxes); default remains all kinds and all owned workspaces when columns are unset
- **`UserSettings`**: one **Data export** form saves schedule plus workspace/table checkboxes; update copy for scheduled runs and ZIP email behavior
- **`UserNotifier.deliver_data_export_csvs/2`**: when **more than two** CSVs are generated, attach a **single ZIP** instead of separate files; refresh email body copy

## [0.9.50] - 2026-05-08

### Changed

- **`JobExpandLists`**: one **Edit** control per work item row (title + scheduled date in a single form) and per material row (quantity + description); replace per-field edit keys with **`JobExpandEditKeys.wi_edit/1`** and **`mat_edit/1`**
- **`JobsLive`**: replace **`job_expand_commit_wi_title`**, **`job_expand_commit_wi_scheduled`**, **`job_expand_commit_material_qty`**, and **`job_expand_commit_material_desc`** with **`job_expand_commit_wi_row`** and **`job_expand_commit_material_row`**

## [0.9.49] - 2026-05-08

### Added

- **`tzdata`** dependency and **`config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase`** for IANA zones
- **SMS reminder profile**: time zone `<select>` and **`send_hour_local`** (clock hour in that zone); **`Reminders.profile_timezone_select_options/0`** and **`valid_profile_timezone?/1`**
- **`Reminders.local_send_hour_matches_now?/2`** for the scheduler (and tests)

### Changed

- **`Reminders`**: default prefs use **`America/New_York`** and **9:00** local; job pings run when the user’s **local** hour matches (DST-aware); legacy JSON with only **`send_hour_utc`** maps to **`Etc/UTC`** and the same hour
- **`UserSettings`**: merge **`sms_reminder_timezone`** and **`sms_reminder_send_hour_local`** into prefs JSON; drop UTC-only copy

## [0.9.48] - 2026-05-08

### Changed

- **`UserSettings` profile form**: replace SMS reminder **JSON** field with checkboxes (relative days before the job) and a **UTC hour** select; merge synthetic params into `sms_reminder_prefs_json` in **`UserSettingsController`**
- **`Layouts.app`**: keep **mobile workspace hamburger** to the **left** of the logo via **`app_workspace_nav_mobile_drawer/1`**; render **`app_workspace_nav/1`** on **large screens only**
- **`Reminders`**: document **`decode_prefs_json/1`** for use from settings templates

## [0.9.47] - 2026-05-08

### Added

- **`SupportLive`** at **`/support`**: phone **(802) 278-0965** (same as SMS line) and **support@rompcrm.com**
- **Twilio voice webhook** **`POST|GET /webhooks/twilio/voice`**: returns TwiML **`Dial`** to **`TWILIO_VOICE_FORWARD_TO`** (default **`+18024587299`** / 802-458-7299); does not change SMS handling
- **`mix twilio.configure_voice`**: sets **`VoiceUrl`** / **`VoiceMethod`** on the Twilio incoming number via REST (leaves **`SmsUrl`** unchanged)
- **Config**: **`twilio_voice_webhook_public_url`**, **`twilio_voice_forward_e164`** (env **`TWILIO_VOICE_WEBHOOK_PUBLIC_URL`**, **`TWILIO_VOICE_FORWARD_TO`**)

### Changed

- **`AppWorkspaceNav`**: **Support** navigates to **`/support`** (same pill style as other workspace links); remove expandable **`SupportContact`** disclosure component

## [0.9.46] - 2026-05-08

### Added

- **First-login SMS assistant intro**: modal on paid LiveView pages asks for a mobile number (or skip); on save, send welcome SMS via Twilio when outbound SMS is enabled
- **`users.sms_assistant_intro_completed_at`**: migration backfills existing users so only new accounts see the intro
- **`RompCrm.SmsAssistantIntro`**: welcome SMS body and **`send_welcome_sms/1`**
- **`RompCrmWeb.SmsAssistantIntroComponent`**, **`UserAuth.on_mount :assign_sms_assistant_intro`**, **`UserAuth.apply_sms_assistant_intro_assigns/2`**
- **`Twilio.Phone.to_e164/1`**: shared E.164 helper for outbound SMS

### Changed

- **`Accounts`**: add **`skip_sms_assistant_intro/1`**, **`complete_sms_assistant_intro_with_phone/2`**, **`mark_sms_assistant_intro_completed/1`**
- **`Reminders`**: use **`Phone.to_e164/1`** instead of a private helper
- **`Layouts.app`**: optional **`socket`** and **`show_sms_assistant_intro_modal`**; render intro **`live_component`** when both apply
- **Authenticated `live_session`s**: mount **`assign_sms_assistant_intro`** after subscription check
- **`JobsLive`**, **`BusinessesLive`**, **`TimeLogLive`**, **`MyTimeclockLive`**, **`EmployeesLive`**, **`EmployeeDetailLive`**: handle **`{:sms_assistant_intro, :updated, user}`** and pass new layout assigns
- **`UserSessionControllerTest`**: stop asserting signed-in jobs HTML includes the account email (header does not render it)

### Added

- **`RompCrmWeb.SupportContact`**: extracted **Support** disclosure (used from workspace nav)

### Changed

- **`Layouts.app`**: single compact header row — **logo** (slightly shorter), workspace nav, **theme toggle**, then **Settings** / **Log out** as **icon-only** buttons; drop duplicate **Support** from header rail (**Support** stays on desktop nav and in the **mobile hamburger** menu)
- **`Layouts.root`**: hide top email / text **Settings** / **Log out** for signed-in users (guest **Register** / **Log in** bar unchanged); shorten **`<.live_title>`** suffix
- **`AppWorkspaceNav`**: **hamburger-only** summary (no “Menu” label); **Support** inside mobile drawer; **Settings** removed from pill list (header icons replace it)
- **`JobsLive`**: remove **`header_extras`** SMS / tagline block and related assigns

## [0.9.44] - 2026-05-14

### Changed

- **`JobExpandLists`**: allow **work item titles** and **material descriptions** to **wrap** across lines instead of **`truncate`**; use **`flex-wrap`** and **`items-start`** on rows so long names stay readable on narrow screens

## [0.9.43] - 2026-05-14

### Added

- **`RompCrmWeb.JobExpandEditKeys`**: stable string keys for expanded-job edit mode
- **`JobsLive`** **`job_expand_editing`** (**`MapSet`**) with **`job_expand_edit_start`**, **`job_expand_edit_cancel`**, and **`job_expand_commit_*`** events

### Changed

- **`JobExpandedInlineFields`** and **`JobExpandLists`**: expanded job fields default to **read-only**; **pencil** (green) enters edit mode, **check** saves via **`phx-submit`**, **×** cancels; pass **`edit_keys`** from **`JobsLive`**
- **`JobsLive`**: clear **`job_expand_editing`** when toggling expanded row; remove **`inline_job_update`** and immediate **`phx-change`** handlers for job fields, work item title/date, and material qty/description (**checkboxes**, **delete**, and **`material_unit_price`** unchanged)

## [0.9.42] - 2026-05-13

### Changed

- **`jobs_live.html.heex`**: keep job status (and priority) pills a fixed width on small screens — **`shrink-0`**, **`w-28`**, **`box-border`**, **`self-start`** on the badge; give the mobile text column **`flex-1 min-w-0`** so only the left block shrinks instead of the pill

## [0.9.41] - 2026-05-13

### Added

- **`RompCrm.Jobs.MaterialSmsNormalize`**: derive **`quantity`** and **`description`** when SMS/AI sends count inside **`description`** or omits **`quantity`**
- **`JobsLive`** **`work_item_title`** and **`material_description`** events for inline edits in **`JobExpandLists`**

### Changed

- **`JobExpandLists`**: editable **work item title** and **material description** inputs (when **`can_edit_jobs`**) with **`phx-debounce`**
- **`Jobs.normalize_material_specs`** / **`sync_material_specs_list`**: persist **`quantity`** from extraction JSON; apply **`MaterialSmsNormalize`** before insert
- **`sms_unified_inbound_extractor` / `sms_job_extractor` Anthropic prompts**: document **`quantity`** + **`description`** rules and examples for materials

## [0.9.40] - 2026-05-13

### Changed

- **`jobs_live.html.heex`**: remove **Hours on this job** heading, timeclock explanatory copy, and **View all job hours** link from expanded job rows; keep **Add job hours…**, total, and recent entries table

## [0.9.39] - 2026-05-13

### Added

- **`RompCrmWeb.JobExpandedInlineFields`**: edit **client**, **address**, **phone**, **priority**, **status**, **referred by**, **next action**, **work description**, **job scheduled date**, and **notes** in the expanded job panel (no **Edit** link); **`JobsLive`** **`inline_job_update`** event

### Changed

- **`jobs_live.html.heex`**: wire inline fields on mobile and desktop expanded rows; remove **Edit** actions from the job table and mobile footer (**Delete** remains)
- **`JobExpandLists`**: replace **Remove** text with compact **×** buttons; work items show **ISO date** as plain text plus a **small calendar** control (no wide date field); materials use **one flex row** (narrow **Qty** input, no **`Job:`** prefix for job-level lines), **`truncate`** description

## [0.9.38] - 2026-05-13

### Changed

- **`JobExpandLists` `job_materials_section`**: show **Qty:** beside the quantity control; drop the inline **unit price** field from the expanded materials list; size the qty **`input`** from the saved value (**`size`** + **`field-sizing: content`**, **`max-w-[12ch]`**) so single-digit quantities stay narrow

## [0.9.37] - 2026-05-13

### Changed

- **`Jobs.work_items_preload_query`**: order work items by **`completed`**, then **dated `scheduled_on` before undated**, then **`scheduled_on`**, **`sort_order`**, **`id`**

### Fixed

- **`Jobs.merge_append_only_work_items`**: when SMS/AI sends **`work_items`** without **`id`** and the list length matches or exceeds existing rows, zip-merge onto persisted rows (and append only the tail) instead of concatenating the full snapshot after all existing rows (which duplicated every line item after date-only updates)

## [0.9.36] - 2026-05-13

### Changed

- **`JobExpandLists` `job_work_items_section`**: keep checkbox, title, date, and **Remove** on one row with **`items-center`** and **`truncate`** titles (full text in **`title`**); tighten vertical padding; restore **`input type="date"`** with **`input-bordered input-xs`** on the right instead of the icon-only control

## [0.9.35] - 2026-05-13

### Changed

- **`jobs_live.html.heex`**: label **Work:** → **Work description:** in job summary and expanded views
- **`JobExpandLists`**: section title **Work items** → **Work items:**; compact row spacing; move work item date to the right behind a small calendar control (show ISO date only when set); align materials list density with work items
- **`AppWorkspaceNav`**: style workspace links as emerald pill buttons (match **Support**); add **Job list** link to **`/`**; tighten desktop link spacing

## [0.9.34] - 2026-05-13

### Added

- **`priv/repo/migrations/20260515180500_work_items_materials_completed_qty_price.exs`**: add **`completed`** to **`job_work_items`** and **`job_materials`**; add **`quantity`**, **`unit_price`** to **`job_materials`**
- **`RompCrmWeb.JobExpandLists`**: **`job_work_items_section`** / **`job_materials_section`** for expanded rows (dotted row separators, checkbox completion with dimmed styling and bottom sort, inline date or qty/price, per-line remove)
- **`RompCrmWeb.JobsLive`** **`handle_event`** for **`toggle_work_item_completed`**, **`work_item_scheduled_on`**, **`delete_work_item`**, **`toggle_material_completed`**, **`material_quantity`**, **`material_unit_price`**, **`delete_material`**

### Changed

- **`JobWorkItem`** and **`JobMaterial`** schemas and **`RompCrm.Jobs`** (preloads, **`materials_combined/1`**, **`update_job_work_item`**, **`delete_job_work_item`**, **`update_job_material`**, **`delete_job_material`**) for the new fields and ordering
- **`jobs_live.html.heex`**: render work items and materials via **`JobExpandLists`** instead of static bullet lists
- **`job_form_component`**: add **Completed** checkbox per nested work item row

## [0.9.33] - 2026-05-13

### Changed

- **Jobs list (desktop)**: keep header row **`bg-base-200/40`** and visible **Edit / Delete** when a job is expanded, not only on hover; mobile cards use the same expanded background.

## [0.9.32] - 2026-05-13

### Added

- **`Jobs.update_job/2`**: when **`work_items`** lists only rows without persisted **`id`**, merge them after existing line items so **`cast_assoc`** does not delete prior tasks (SMS “add also …” updates).

### Changed

- **Anthropic SMS prompts** (unified + job): instruct the model to add distinct follow-on work as **`work_items`** and refresh **`work_description`** when a summary helps, using judgment over the snapshot.

## [0.9.31] - 2026-05-08

### Added

- **Reminders**: `reminders` and `job_reminder_send_logs` tables; `users.sms_reminders_enabled` and `users.sms_reminder_prefs_json`; **`RompCrm.Reminders`** for row delivery and scheduled-job SMS nudges; **`RompCrm.ReminderScheduler`** GenServer
- **SMS unified extraction**: `reminder_actions` with **`RompCrm.Ai.SmsReminderExtractor`**; Anthropic prompts for work items, materials, job dates, MMS **`attach_photo`**, and reminder scheduling
- **Account settings**: opt-in checkbox and JSON preferences textarea for SMS reminders
- **`Jobs.list_upcoming_scheduled_jobs/2`**: query for calendar nudge delivery

### Changed

- **`SmsJobExtractor.infer_intent/1`**: treat MMS URLs plus **`job_id`** as **`attach_photo`**
- **`TwilioWebhookController.twilio_media_url_suffix_for_prompt/1`**: avoid **`String.trim/1`** in guards (compile on Elixir 1.19)

## [0.9.30] - 2026-05-08

### Added

- **`DataExport.normalize_export_business_ids/2`**: restrict manual export to owner workspace IDs parsed from **`export_business_ids[]`**
- **`DataExport.deliver_email_export/3`**: email CSVs for chosen kinds and chosen owner business IDs (scheduled **`deliver_email_export/1`** still sends all kinds and all owned workspaces)

### Changed

- **User settings export form**: add workspace checkboxes; validate kinds and workspaces together for email and download
- **`UserNotifier.deliver_data_export_csvs`**: clarify body copy for manual vs scheduled export workspace scope
- **Success flash after email export**: mention how many workspaces were included

## [0.9.29] - 2026-05-12

### Fixed

- **`config/runtime.exs`**: pass **`tls_options`** for Swoosh SMTP (**`:verify_peer`**, **`:cacerts`**, **`customize_hostname_check`** with **`:public_key.pkix_verify_hostname_match_fun(:https)`**, **`depth`**, **`server_name_indication`**) so STARTTLS to SpaceMail verifies wildcard SMTP certs instead of returning **`:tls_failed`**

## [0.9.28] - 2026-05-12

### Fixed

- **`config/runtime.exs`**: set **`check_origin`** from **`PHX_HOST`** (apex + **`www`**) merged with **`https://{hromp,rompcrm}.com`** (each apex + www) when **`PHX_CHECK_ORIGINS`** is unset, so LiveView works on **`rompcrm.com`** while **`PHX_HOST`** stays **`hromp.com`**; optional **`PHX_CHECK_ORIGINS`** alone for self-host overrides
- **`assets/js/app.js`**: remove **`longPollFallbackMs: 2500`** so Phoenix does not tear down a working WebSocket when the post-connect RTT ping is slow (common on mobile), which triggered LiveView **`phx-server-error`** and the “Something went wrong! Attempting to reconnect” toast in a loop; set **`disconnectedTimeout: 2500`** so brief blips wait longer before showing that toast
- **`deploy/nginx-location-romp-crm.conf`**: document **`$connection_upgrade`** map and use it instead of unconditional **`Connection: upgrade`**

## [0.9.27] - 2026-05-12

### Fixed

- **`config/runtime.exs`**: set **`no_mx_lookups: true`** on **`RompCrm.Mailer`** so gen_smtp connects to **`SMTP_HOST`** by hostname; avoids STARTTLS **`:tls_failed`** when the host has no MX and the client would otherwise use the A record IP (e.g. SpaceMail)

## [0.9.26] - 2026-05-12

### Added

- **`RompCrmWeb.AppWorkspaceNav`**: shared header workspace links (**Job time log**, **Workday timeclock**, **Employees** when owner, **Businesses**, **Settings**); desktop inline row; mobile **Menu** `<details>` panel; optional multi-business switcher
- **`Layouts.app`**: **`show_workspace_nav`**, **`current_business_id`**, **`my_businesses`**, **`is_business_owner`**, optional **`header_extras`** slot; **`JobsLive`** uses layout with SMS intake lines in **`header_extras`**
- **`Businesses.resolve_active_business_id/3`**: centralize active-workspace resolution for nav and **`UserAuth.on_mount(:ensure_business_scope)`**
- **Tests**: **`resolve_active_business_id/3`** coverage in **`BusinessesTest`**

### Changed

- **`UserAuth`**: **`ensure_business_scope`** calls **`Businesses.resolve_active_business_id/3`**
- **`JobsLive`**, **`TimeLogLive`**, **`MyTimeclockLive`**, **`EmployeesLive`**, **`EmployeeDetailLive`**, **`BusinessesLive`**, **`UserSettingsController`**, **`SubscribeController`**: pass workspace nav assigns into **`Layouts.app`**; remove duplicated per-page link rows where replaced by the shared nav

## [0.9.25] - 2026-05-08

### Added

- **`/my-timeclock`** (**`MyTimeclockLive`**): workday punch **Clock in** / **Clock out** for the signed-in user’s linked employee row; copy distinguishes employer timeclock vs client job hours; audit rows **`employee_time_entries.create`** / updates on punch out
- **`EmployeePermissions.can_punch_own_timeclock?/1`**: gate web punch clock (roster link + own employee time permission)
- **`JobsLive`**: **Add job hours…** modal with **`datetime-local`** start/end (**`step="900"`**), optional notes; **`RompCrmWeb.DatetimeLocal`**, **`RompCrmWeb.JobTimeLogDefaults`**; audit **`time_entries.create`** with **`metadata.source`** **`job_hours_form`**
- **`TimeEntry` changeset**: validate **`ended_at`** after **`started_at`** when both present

### Changed

- **`JobsLive`** header: **Job time log**, **Workday timeclock**, **Employees** (owners only); expanded job panels label **Hours on this job** with cross-links to the timeclock and job time log
- **`TimeLogLive`**: title **Job time log**, explanatory copy and nav (**Workday timeclock**, **Employees** for owners); empty-state copy references Jobs board job hours
- **`RompCrmWeb.DatetimeLocal.parse/1`**: map any failed ISO parse to **`{:error, :invalid}`** (covers **`{:error, :invalid_format}`** from **`NaiveDateTime.from_iso8601/1`**)

## [0.9.24] - 2026-05-08

### Added

- **`employees`**: optional **`user_id`** (FK to **`users`**), permission booleans **`can_edit_jobs`**, **`can_log_job_time`**, **`can_log_own_employee_time`**, **`can_log_employee_time_for_others`** (defaults: job time and own employee time on; job edits and others’ employee time off); partial unique index on **`(business_id, user_id)`** when **`user_id`** is set
- **`business_audit_logs`** table and **`RompCrm.BusinessAuditLogs`**: append-only rows with **`actor_user_id`**, **`source`** (`web` / `sms`), **`action`**, **`entity_type`**, **`entity_id`**, **`metadata`** (JSON); migration copies existing **`sms_interaction_logs`** into **`business_audit_logs`** as legacy rows
- **`RompCrm.EmployeePermissions`**: resolve effective caps for owners vs linked members
- **`Employees.ensure_placeholder_for_invitation/3`**, **`Employees.link_user_after_invite_accept/2`**: roster row for invite email; link or create employee when a user accepts an invitation
- **Employees UI**: permission checkboxes on the employee form; **Invite to app** on roster rows with email and no linked user (calls **`Businesses.invite_user/3`**)
- **`UserAuth.on_mount(:require_business_owner)`** and a dedicated **`live_session`** so **`/employees`** routes are owner-only
- **Tests**: **`EmployeePermissionsTest`**, **`DataExport.build_audit_log_csv/1`** coverage

### Changed

- **`Businesses.invite_user`**: after creating an invitation, ensure an employee placeholder for the invited email; record **`business_invitation.create`** and **`employees.create`** (placeholder) in **`business_audit_logs`**
- **`Businesses.accept_invitation_raw`**: after membership insert, call **`Employees.link_user_after_invite_accept/2`**; record **`business_membership.create`** in **`business_audit_logs`**
- **`Businesses.cancel_invitation`**: return **`{:ok, :deleted}`** / error tuple and append **`business_invitation.cancel`** audit row
- **`DataExport.deliver_email_export/1`**: attach **`audit_log.csv`** (from **`business_audit_logs`**) instead of **`sms_interactions.csv`**; extend **`employees.csv`** with **`user_id`** and permission columns
- **`TwilioWebhookController`**: filter parsed operations by **`EmployeePermissions`**; record one **`business_audit_logs`** row per successful DB mutation from SMS (job / job time / employee time); remove writes to **`sms_interaction_logs`**
- **`JobsLive`** / **`JobFormComponent`**: gate create / edit / delete on **`can_edit_jobs`**; append **`jobs.create`**, **`jobs.update`**, **`jobs.delete`** audit rows from the web UI
- **`EmployeesLive`** / **`EmployeeFormComponent`**: append **`employees.create`**, **`employees.update`**, **`employees.delete`** audit rows
- **`Employees.link_user_after_invite_accept`**: append **`employees.link_user`** or **`employees.create`** audit rows as appropriate
- **`UserNotifier.deliver_data_export_csvs`**, **Settings → Data export** copy: describe **`audit_log.csv`** instead of SMS-only export
- **`config/test.exs`**: use ephemeral HTTP **`port: 0`** for **`Endpoint`** to reduce port collisions; set SQLite **`busy_timeout`** on **`Repo`**

## [0.9.23] - 2026-05-13

### Added

- **`users`**: **`data_export_schedule`**, **`data_export_next_run_at`**, **`data_export_last_sent_at`** for optional scheduled CSV email exports (owner businesses only)
- **`sms_interaction_logs`** table and **`SmsInteractionLogs`** context: one row per inbound SMS handled by **`TwilioWebhookController`** with planned operations and results summaries for export
- **`RompCrm.DataExport`**: build UTF-8 CSVs for jobs, employees, combined time log (job + employee clocks), and SMS interaction log; **`deliver_email_export/1`** emails attachments via **`UserNotifier`**
- **`RompCrm.DataExportSchedule`**: compute next UTC run for daily / weekly / monthly intervals
- **`RompCrm.DataExportScheduler`**: GenServer tick (5 minutes) calling **`DataExport.run_due_exports/0`** when **`config :romp_crm, :data_export_scheduler_enabled`** is not **`false`**
- **`Businesses.list_owned_businesses_for_user/1`**: businesses where membership role is **owner** only
- **Settings → Data export**: schedule (off / daily / weekly / monthly) and **Email export now** one-time action

### Changed

- **`TwilioWebhookController`**: persist **`SmsInteractionLogs`** rows alongside conversation exchange logging
- **`UserNotifier`**: add **`deliver_data_export_csvs/2`** and **`deliver_data_export_no_owned_businesses/1`**
- **`Accounts`**: **`change_user_export_settings/2`**, **`update_user_export_settings/2`**, **`advance_data_export_schedule_after_send/1`**
- **`UserSettingsController`** / **`user_settings_html/edit`**: export schedule form and one-time export button
- **`config/test.exs`**: set **`data_export_scheduler_enabled`** **`false`** so tests do not run the export loop

## [0.9.22] - 2026-05-11

### Changed

- **`employees_live`** / **`time_log_live`**: add **`md:hidden`** stacked card lists on small viewports (same pattern as **`jobs_live`**); show **`hidden md:block`** tables on **`md+`** without **`overflow-x-auto`** or forced table **`min-width`**
- **`EmployeesLiveTest`**: assert **`#employees-table`** only when the list is non-empty

## [0.9.21] - 2026-05-12

### Added

- **`sms_conversation_messages`** table and **`SmsConversations`** context: persist inbound/outbound SMS per business + normalized phone so the unified extractor receives a **prior thread** (follow-ups like attributing hours to an employee resolve correctly)
- **`SmsUnifiedInboundExtractor`**: optional **`prior_turns`** passed through to Anthropic user prompt and documented in the system prompt

### Changed

- **`TwilioWebhookController`**: load prior turns before extraction; after each assistant reply, **`record_exchange/5`** stores the inbound/outbound pair
- **`SmsUnifiedInboundExtractor.DeterministicStub`**: legacy **`STUB_JSON`** payloads with **`actions`** (instead of **`job_actions`**) lift into **`job_actions`** for tests
- **`Layouts.app`**: add **`content_width`** (**`:wide`** vs **`:narrow`**); use **`max-w-screen-xl`** for wide pages; stack and wrap header nav on small viewports to avoid horizontal overflow
- **`employees_live`**, **`time_log_live`**, **`employee_detail_live`**: use wide layout; stack page titles and actions on narrow screens; **`employee_detail_live`**: wrap wide tables in horizontal scroll where needed
- **`TimeTrackingTest`** / **`EmployeesTest`**: close the first time entry in ordering tests so fixtures respect partial unique indexes on open clocks

## [0.9.20] - 2026-05-08

### Changed

- **`TwilioWebhookController`**: route inbound SMS through **`SmsUnifiedInboundExtractor`** (single adapter call) instead of three separate Anthropic extractions; reply with user-visible SMS when unified extraction or parsing fails
- **`SmsTimeExtractor`** / **`SmsEmployeeTimeExtractor`**: require **`job_id`** / **`employee_id`** from model output; remove server-side **`match`** tuple operations for job and employee time (alignment with snapshot-based AI matching)
- **`SmsJobExtractor.Anthropic`**, **`SmsTimeExtractor.Anthropic`**, **`SmsEmployeeTimeExtractor.Anthropic`**: pass **`finch: RompCrm.Finch`** on Anthropic **`Req.post`** calls

### Added

- **`SmsUnifiedInboundExtractor.DeterministicStub`** for tests; **`config/test.exs`** **`sms_unified_inbound_adapter`**
- Migration **`partial_unique_open_time_entries`**: SQLite partial unique indexes so at most one open **`time_entries`** row per **`(business_id, job_id)`** and one open **`employee_time_entries`** row per **`(business_id, employee_id)`**; **`unique_constraint`** on related changesets
- **`SmsUnifiedInboundExtractorTest`**

### Removed

- **`TwilioWebhookController`** fuzzy **`find_employee_for_sms`** / **`apply_*`** **`match`** branches for job time and employee time

## [0.9.19] - 2026-05-08

### Added

- **`Billing.cancel_subscription_for_user/1`** and **`PaypalClient.cancel_subscription/2`**: cancel hosted PayPal billing subscriptions via API; clear PayPal subscription fields and set **`subscription_status`** **`inactive`** on success
- **`UserSettingsController`**: **`cancel_subscription`** action redirects to **`/subscribe`** with confirmation flash after cancellation (or error flash on failure)
- **`user_settings_html/edit`**: **Cancel subscription** button with browser confirm (shown for **`active`** subscribers when hosted paywall is enabled)

### Added (tests)

- **`BillingTest`** and **`UserSettingsControllerTest`** coverage for cancellation guards and failure handling

## [0.9.18] - 2026-05-08

### Added

- **`deploy/legal/`**: source copies of **`privacy-policy.html`** and **`terms-of-service.html`** for **[rompcrm.com](https://rompcrm.com)** static deployment
- **`Layouts.legal_footer`**: footer links to Privacy Policy and Terms (hosted marketing domain); **`jobs_live`** includes same footer

## [0.9.17] - 2026-05-08

### Added

- **`users.may_create_business`** column (default true): invite-only accounts register with **`may_create_business` false** and **`subscription_status` `invited_member`**
- **`User.may_create_business?/1`**, **`Billing.subscription_active?/1`** for **`invited_member`**, **`Businesses.create_business/2`** guard returning **`{:error, :cannot_create_business}`**
- **`Accounts.register_user/2`** option **`invitation:`** for **`BusinessInvitation`** (skips hosted PayPal path; marks invited member profile)
- **`UserRegistrationController`**: session **`pending_invitation_token`** suppresses billing UI; **`finish_invite_create`** sends magic link without PayPal
- **`businesses_live`**: hide “Create a business” for users who may not create one; flash on blocked **`create_business`** and on **`business_limit_reached`**
- **`user_registration_html/new`**: invitation-specific subtitle and info alert
- **`Businesses.create_business/2`**: cap at **`3`** owner businesses per account (**`owned_business_creation_limit/0`**); return **`{:error, :business_limit_reached}`**
- Tests for invitation registration, paywall bypass for **`invited_member`**, UI, and business creation limit

## [0.9.16] - 2026-05-08

### Changed

- **`Billing.finalize_subscription_active/3`**: stop requiring PayPal payer email to match registration email
- **`UserAuth.require_active_subscription_user`**: before paywall redirect, if the user has a stored **`paypal_subscription_id`**, call PayPal and activate the row when the subscription is usable (unblocks home / jobs after payment when the return URL or webhook was late)
- **`SubscribeController.show`**: same one-shot PayPal sync for logged-in visitors on **`/subscribe`**, then redirect to **`/`** with a welcome flash when activation succeeds
- **`subscribe_html/show`**: use theme text colors (**`text-base-content`**) for readable copy on dark mode; add a short note about auto-sync on load

## [0.9.15] - 2026-05-08

### Changed

- **`Billing.paypal_return_subscription_id/1`**: accept **`subscriptionId`** (camelCase) and **`token`** / **`ba_token`** when the value matches subscription id shape (**`I-…`**), so PayPal return URLs are parsed reliably
- **`Billing.finalize_subscription_active/3`**: treat **`APPROVED`** like **`ACTIVE`**; resolve **`plan_id`** from nested **`plan.id`** when needed; drop hard dependency on payer email when PayPal omits it (still enforce email match when PayPal sends one); broaden **`subscriber_email`** extraction paths
- **`Billing.activate_from_paypal_subscription_id/1`**: return **`{:error, :unknown_subscription}`** when no user row matches (no silent **`nil`**); map PayPal API failures to **`{:error, {:paypal_subscription_fetch, reason}}`**
- **`SubscribeController.paypal_return`**: redirect PayPal fetch failures to **log-in** with a retry-oriented flash instead of registration

### Added

- **`test/romp_crm/billing_test.exs`** for return-url parsing and **`finalize_subscription_active`**

## [0.9.14] - 2026-05-08

### Changed

- **`Accounts.register_user/2`**: when **`subscription_paywall_enabled`** is true, allow registering again with the same email if the prior row is still **`pending_payment`** and **`confirmed_at`** is **`nil`** (abandoned PayPal checkout), returning that user so **`UserRegistrationController`** can restart checkout instead of failing email uniqueness

### Added

- Tests for paywall resume vs active subscriber duplicate rejection

## [0.9.13] - 2026-05-08

### Added

- Add **`Layouts.support_contact`** (**Support** disclosure with **`tel:`** **802-458-7299** and “call to speak with a live person 24/7”) in **`Layouts.app`** and **`jobs_live`** header

## [0.9.12] - 2026-05-08

### Added

- Document **14-day (configurable) PayPal free trial** on hosted registration (**`PAYPAL_TRIAL_DAYS`**); **`mix paypal.provision`** builds **`TRIAL`** + **`REGULAR`** billing cycles (\$0 trial, then monthly or annual price)

### Changed

- Extend **Account settings** with PayPal **Automatic payments** link and trial/cancel guidance when a stored subscription id exists

## [0.9.11] - 2026-05-08

### Added

- Add **`mix paypal.provision`** to create a PayPal catalog product, **`monthly`** / **`annual`** subscription plans, and a **`BILLING.SUBSCRIPTION.*`** webhook via the REST API (**`deploy/paypal-provision-result.env`** output, gitignored)
- Gate sign-up and CRM access behind an optional **`SUBSCRIPTION_PAYWALL_ENABLED`** PayPal Billing flow (**`monthly`** / **`annual`** plans via **`PAYPAL_PLAN_*_ID`**)
- Add **`POST /webhooks/paypal`** with PayPal webhook signature verification (**`PAYPAL_WEBHOOK_ID`**) plus **`GET /subscribe`**, **`GET /subscribe/paypal/return`** / **`cancel`**, **`POST /subscribe/resume`**
- Add subscription columns on **`users`** (**`paypal_subscription_id`**, **`paypal_plan_id`**, **`subscription_status`**) defaulting **`active`** for existing installs

### Changed

- When the paywall is enabled, **`POST /users/register`** skips the magic link email until **`BILLING.SUBSCRIPTION.ACTIVATED`** (return URL sync or webhook); extend CSRF **`allow_hosts`** for **`rompcrm.com`** and **`www.rompcrm.com`**

## [0.9.10] - 2026-05-08

### Changed

- Wire **`enforce_registration_allowlist`** to **`ENFORCE_REGISTRATION_ALLOWLIST`** (default **`false`**); **`Accounts.register_user/1`** honors the flag so open registration is explicit when disabled
- Support **`register_user/2`** options (**`:enforce_allowlist`**, **`:allowlist`**) for tests
- Set changeset **`action`** on failed registration so email validation errors show under the field

### Fixed

- **`registration_email_allowlist`** in config previously did not restrict sign-ups; behavior now matches intent when enforcement is enabled
- Avoid **`Application.put_env`** in registration tests (**`register_user/2`** opts) so parallel ExUnit runs do not flake

## [0.9.9] - 2026-05-07

### Added

- License Romp CRM under the **GNU General Public License v3.0 or later**; add full **`LICENSE`** text and document in **`README.md`**

## [0.9.8] - 2026-05-07

### Added

- Add **`mix twilio.messaging_service_inbound`** to set **`UseInboundWebhookOnNumber`** on a Twilio Messaging Service so inbound SMS uses each number's **SmsUrl**

### Changed

- Log Twilio **`To`** on inbound SMS for multi-number debugging

## [0.9.7] - 2026-05-07

### Changed

- Drive jobs header SMS link and label from **`TWILIO_MESSAGING_FROM`** via **`RompCrm.Twilio.Phone`** (`format_us_display/1`, **`sms_uri/1`**)
- Run **`mix twilio.configure_sms`** with **`Req`** only (no full **`app.start`**) so it does not bind **`PORT`** while the production release is running

## [0.9.6] - 2026-05-07

### Added

- Add **`RompCrm.Twilio.Messages`** outbound SMS and **`RompCrm.Twilio.SmsReplyBuilder`** short confirmations after inbound CRM updates
- Add **`mix twilio.configure_sms`** to set **`SmsUrl`** / **`SmsMethod`** on a Twilio **`IncomingPhoneNumber`** via the REST API

### Changed

- Configure **`TWILIO_ACCOUNT_SID`**, **`TWILIO_MESSAGING_FROM`** (default **`+18022780965`**), and **`TWILIO_SMS_REPLIES_ENABLED`** in **`config/runtime.exs`** (prod) and **`config/dev.exs`**
- Extend **`SmsJobExtractor`** / webhook flow with **`assistant_sms`**, clarification replies, and **`Jobs`** ambiguous-match SMS copy
- Include **`+18022780965`** in default **`TWILIO_SMS_ALLOWED_FROM`** examples where applicable

## [0.9.5] - 2026-05-07

### Changed

- Add **`1000001495-fast.mp4`** (**2×** playback of the full screencast, audio stripped) for README **`<video>`**; regenerate **`1000001495-preview.gif`** from that file so the GIF shows the full walkthrough at the same speed
- Document link to the original **real-time** **`1000001495.mp4`**

## [0.9.4] - 2026-05-07

### Changed

- Keep a single README screencast (**`1000001495`**); remove **`1000001486`** assets from **`docs/screencaps/`**
- Show preview GIF and **`<video>`** at **480px** width (centered) so the player does not span the full README column

## [0.9.3] - 2026-05-07

### Changed

- Embed screen recordings in **`README.md`** with `<video>` (full MP4) plus looping **GIF** previews (**first ~15s**, **`docs/screencaps/*-preview.gif`**) for Markdown viewers without HTML video support

## [0.9.2] - 2026-05-07

### Added

- Add **`docs/screencaps/`** PNG screenshots and MP4 screen recordings for the public UI
- Document gallery and recording links in **`README.md`**

## [0.9.1] - 2026-05-07

### Changed

- Resolve inbound SMS jobs workspace with **`users.selected_business_id`** first (Jobs header picker / recent workspace), then **`users.sms_business_id`** (Settings), then sole membership
- Reload the user from the DB before **`maybe_set_default_sms_business`** when creating a business so a stale struct does not move the SMS default to every newly created org

### Added

- **`BusinessesTest`** coverage for **`resolve_sms_business_id/1`** and a Twilio webhook test that proves picker routing overrides SMS Settings when both differ

## [0.9.0] - 2026-05-07

### Added

- Store **`users.selected_business_id`** as the preferred Jobs workspace; **`UserAuth.ensure_business_scope`** falls back to it when the session has no **`current_business_id`**, so the choice survives **log out / log in**
- **`Accounts.put_jobs_workspace_selection/2`** to validate membership and persist that field

### Changed

- Set session and persist workspace when a user **accepts a business invitation** (**`InvitationController`**) and when they use the **business picker** (**`BusinessSwitchController`**)

## [0.8.9] - 2026-05-07

### Fixed

- Append **`Endpoint.path`** in **`Businesses`** invitation mail URLs (**`Endpoint.url`** does not carry the **`/romp-crm`** mount), so mailed links resolve under the production reverse-proxy prefix

## [0.8.8] - 2026-05-07

### Fixed

- Store **`BusinessesLive`** invite **`to_form`** data in **`invite_forms`** keyed by **`business_id`** so **`phx-change`** on one business no longer mirrors the email field on other businesses
- Set distinct **`id`** values on per-business invite email inputs so LiveView no longer mounts duplicate **`invite_email`** DOM ids

## [0.8.7] - 2026-05-07

### Changed

- Remove bordered **`base-100`** logo wrapper chrome in **`Layouts.app`** and **`jobs_live`** headers; clip main logo PNGs with **`aspect-ratio`**, **`overflow-hidden`**, and a slight **`scale`** so baked-in bezel and light-mode “double rectangle” stay outside the viewport
- Expose **`--brand-logo-clip-scale`** default **`1.11`** so deploys can tweak clipping without rebuilding assets

## [0.8.6] - 2026-05-07

### Changed

- Re-export light and dark main logo PNGs from **`assets/logos/all_logos.png`**: transparent background on the light asset so **`base-100`** shows through the rounded header, and tighter crops on the dark asset to drop grid gutter and white-edge artifacts
- Use **`overflow-hidden`** on logo wrapper containers and transparent **`img`** backgrounds so branding aligns with rounded corners in **`Layouts.app`** and the jobs page header

## [0.8.5] - 2026-05-07

### Changed

- Build business invitation acceptance URLs from **`RompCrmWeb.Endpoint.url/0`** plus **`/invitations/...`** so emailed links inherit the configured public mount (**`/romp-crm`**) and no longer omit the proxy prefix
- Extend invitation acceptance flow: persist **`pending_invitation_token`** and **`user_return_to`**, redirect unauthenticated invitees to **login** or **register** with prefilled email, and notify wrong-account sessions before login
- Remove eager invitation acceptance on login completion so redirects to the invitation URL can finish acceptance after credentials are verified
- Prefill **`GET /users/register`** email from **`?email=`**

### Added

- Controller tests covering invitation redirects, wrong-user handling, and successful acceptance

## [0.8.4] - 2026-05-07

### Changed

- Re-crop the dark-mode main logo from the inverted top-right source artwork and update theme switching to explicit CSS rules so dark mode reliably shows the dark logo variant

## [0.8.3] - 2026-05-07

### Changed

- Extract and add Romp CRM branding assets (main logo, dark main logo, and light/dark badge icons) and apply rounded logo containers in app headers
- Update the jobs page to respect dark/light theme tokens instead of fixed light palette classes
- Add the theme toggle control to the jobs page header so users can switch between system, light, and dark modes there

## [0.8.2] - 2026-05-07

### Changed

- Suppress the login-required flash when unauthenticated users are redirected from root (`/`) to `/users/log-in`, while keeping the flash for protected non-root pages

## [0.8.1] - 2026-05-06

### Changed

- Rotate **Plug session `signing_salt`** (and **LiveView `signing_salt`**) so old signed cookies are discarded after the OTP/module rename; users sign in again instead of hitting crashes from deserialized `JgsCrmWeb` references in session

## [0.8.0] - 2026-05-06

### Changed

- Rename OTP application and modules from legacy internal identifiers to **`:romp_crm`**, **`RompCrm.*`**, **`RompCrmWeb.*`**; release binary **`romp_crm`**; dev SQLite files **`romp_crm_dev.db`** / **`romp_crm_test.db`**; remember-me cookie **`_romp_crm_web_user_remember_me`**; telemetry metric prefix **`romp_crm.repo`**
- Align **`config/runtime.exs`** with **`:romp_crm`** and **`RompCrm.*`** modules so production releases load correct endpoint, repo, mailer, and Twilio settings at runtime

## [0.7.2] - 2026-05-06

### Changed

- When a job row is expanded, hide truncated work text in the summary row and show the full work description in the expanded panel (desktop table and mobile cards)

## [0.7.1] - 2026-05-06

### Changed

- Use DaisyUI semantic colors on `/businesses` so headings, cards, and secondary text stay readable in dark mode
- Set explicit `text-base-content` on shared `<.header>` titles for consistent contrast in dark mode

## [0.7.0] - 2026-05-06

### Added

- Multi-tenant businesses: memberships, invitations by email, `/businesses` LiveView to create a business and invite members
- User profile fields `phone` and `sms_business_id` (settings) for routing inbound Twilio SMS to the correct job list
- `POST /business/switch` and jobs header switcher when the user belongs to multiple businesses
- Public `GET /invitations/:token` acceptance flow with pending token stored across login/register

### Changed

- Scope jobs by `business_id`; PubSub topic `jobs:business:<id>`
- Resolve inbound SMS `From` via normalized profile phone and `Businesses.resolve_sms_business_id/1` instead of config allowlists
- Disable registration email allowlist in runtime config by default (invitations gate workspace access)

### Removed

- Twilio webhook gate on `TWILIO_SMS_ALLOWED_FROM` allowlist (unknown numbers log and skip CRM updates)

## [0.6.0] - 2026-05-06

### Changed

- Mount production app at `/romp-crm` URL prefix (`config/prod.exs`)
- Set compile-time `Endpoint` URL path `/romp-crm` in prod so Phoenix VerifiedRoutes (`~p`) generate prefixed paths
- Rebrand user-visible strings to Romp CRM; remove navbar logo image in favor of text nav branding
- Rename session cookie key to `_romp_crm_key`
- Replace deploy snippets with `deploy/romp-crm.*` and update runtime/docs examples for `romp-crm` paths
- Point the app layout brand link at verified route `~p"/"` so subpath deployments keep navigation under `/romp-crm`

## [0.5.8] - 2026-05-06

### Changed

- Omit Work and Notes from expanded job panels where those fields already appear in the collapsed row (mobile removes both from the slide-down panel; desktop table removes duplicate Work from the colspan detail grid while keeping Notes there only)

## [0.5.7] - 2026-05-06

### Changed

- Give the jobs list New Job (+) patch link explicit wider minimum width (`min-w-[4.5rem]`), horizontal padding (`px-6`), `inline-flex`, `self-center`, and default link underline removal so it reads as a short wide control rather than a tall narrow pill

## [0.5.6] - 2026-05-06

### Changed

- Widen the filter-row new-job plus control with horizontal padding and a minimum width so it reads less tall-narrow

## [0.5.5] - 2026-05-06

### Changed

- Move the compact new-job control from the dashboard header beside the status filter tabs
- Remove the redundant header column that duplicated the global account controls

## [0.5.4] - 2026-05-06

### Changed

- Adjust the header new-job plus button classes to render as a consistent square control

## [0.5.3] - 2026-05-06

### Changed

- Remove the temporary branded logo from the jobs header and simplify the new-job control to a compact `+` button
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
- Add `RompCrm.Twilio.Phone.normalize_us/1` for comparing formatted North-American caller IDs

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
- Add `deploy/` with nginx location snippet, env example, systemd unit, and server runbook
- Add `RompCrm.Release` for `bin/romp_crm eval "RompCrm.Release.migrate"` in production

## [0.2.1] - 2026-05-06
### Changed
- Document reverse-proxy stripping for the public URL prefix instead of mounting routes under a scope (fixes verified routes / prod compile; nginx `proxy_pass` trailing slash)

## [0.2.0] - 2026-05-06
### Changed
- Add `req` dependency for outbound Anthropic API calls
- Align `Jobs` context tests and `JobsFixtures` with `create_job/1`, `list_jobs/0`, and no user scope on jobs
- Expect authenticated session for `GET /` controller test so it matches the jobs LiveView route
- Replace default Phoenix navbar with custom logo, app name, and theme toggle only; remove Phoenix Website, GitHub, and Get Started links
- Show the same logo in the jobs dashboard header and set the default browser title suffix for CRM branding
- Scope modal dialog content with `data-theme="light"` and explicit text color so DaisyUI field labels stay readable on the white modal when the app uses a dark theme

### Added
- Twilio inbound SMS webhook at `POST /webhooks/twilio/sms` with optional `X-Twilio-Signature` verification and empty TwiML responses
- SMS-to-job pipeline using Anthropic Claude with configurable model and field extraction for CRM jobs
- Deterministic extractor stub for tests (`sms_job_extractor_adapter`)
- Forward `/dev/mailbox` to `Plug.Swoosh.MailboxPreview` when dev routes are enabled so local adapter emails are viewable in the browser
