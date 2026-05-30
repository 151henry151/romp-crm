defmodule RompCrm.Ai.WorkItemsPrompt do
  @moduledoc false

  @doc """
  Shared instructions for mapping contractor messages to `work_description` and `work_items`.
  """
  def guidance do
    """
    ## Work description and work items (keep them aligned)

    **`work_description`:** Short job-level summary for the office (one line when possible).
    **`work_items`:** Separate rows for distinct tasks on the same job/visit; each object needs a concise **`title`**.

    Read snapshot **`work_items`** titles (and existing **`work_description`**) before updates — avoid duplicating line items that already exist with the same meaning.

    ### Creates (new lead / new job)
    - When the message lists **two or more distinct tasks** for one customer, include **`work_items`** with **one row per task** and a **`work_description`** that summarizes the whole job.
    - Example: "New client Bob — fix his toilet and change his kitchen faucet" → `"work_description": "Fix toilet and change kitchen faucet"`, `"work_items": [{"title":"Fix toilet"},{"title":"Change kitchen faucet"}]`.
    - When there is **one** clear task, still add a matching **`work_items`** row (e.g. `[{"title":"Fix toilet"}]`) plus **`work_description`**.
    - Do **not** list multiple distinct tasks **only** in **`work_description`** when they should be separate line items.

    ### Updates — adding scope ("also", "when we're there", "add to … job")
    - When the contractor is **adding** another task on an existing job, send **`updates.work_items`** with a **new** row (omit `"id"` so the server appends) **and** refresh **`updates.work_description`** when a new summary helps.
    - Example: "When we're at Bob's we're also going to replace his bathtub" → update Bob's `job_id`: update **`work_description`**, append **`work_items": [{"title":"Replace bathtub"}]`**.

    ### Updates — general work / scope changes
    - When the user describes **new or expanded work** (not merely renaming the summary), compare the message to snapshot **`work_items`** and **`work_description`**. Add **`work_items`** rows for **newly implied** tasks that are not already covered; update **`work_description`** when helpful.
    - Example: snapshot work item "Fix toilet"; message "Bob's job is toilet and kitchen faucet" → append **`{"title":"Change kitchen faucet"}`** if missing, refresh description.

    ### Updates — description-only / explicit rewrite (usually **no** new line items)
    - When the user **only** wants the summary text changed — e.g. "update the work description to …", "change the description to say …", "set Bob's work description to …", "rewrite the job summary as …" — set **`updates.work_description`** only. **Do not** add **`work_items`** unless they also clearly name **new** tasks in the same message.
    - If the new wording **implies** additional tasks beyond existing line items, you may: (a) update the description and ask in **`assistant_sms`**: "Updated the description — should I also add a work item for …?" or (b) return **no DB changes** and ask first. Either is fine; brief clarification is always OK.

    ### Mechanics (server behavior)
    - On **updates**, new **`work_items`** rows **without `"id"`** are **appended** after existing snapshot line items — send **only new** rows unless you intend to replace the full list.
    - To **replace, delete, or reorder** line items, send the **complete** intended **`work_items`** array including every surviving snapshot **`id`**.
    """
  end
end
