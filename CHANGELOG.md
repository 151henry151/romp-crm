# Changelog

## [Unreleased]

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
