defmodule RompCrmWeb.JobExpandEditKeys do
  @moduledoc false

  def job(job_id, field) when is_integer(job_id) and is_binary(field), do: "job:#{job_id}:#{field}"

  def wi_edit(work_item_id) when is_integer(work_item_id), do: "wi:#{work_item_id}:edit"

  def mat_edit(material_id) when is_integer(material_id), do: "mat:#{material_id}:edit"
end
