defmodule RompCrmWeb.JobExpandEditKeys do
  @moduledoc false

  def job(job_id, field) when is_integer(job_id) and is_binary(field),
    do: "job:#{job_id}:#{field}"

  def wi_title(work_item_id) when is_integer(work_item_id), do: "wi:#{work_item_id}:title"

  def wi_scheduled(work_item_id) when is_integer(work_item_id),
    do: "wi:#{work_item_id}:scheduled_on"

  def mat_quantity(material_id) when is_integer(material_id), do: "mat:#{material_id}:quantity"

  def mat_description(material_id) when is_integer(material_id),
    do: "mat:#{material_id}:description"
end
