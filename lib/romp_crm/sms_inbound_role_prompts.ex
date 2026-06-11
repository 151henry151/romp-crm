defmodule RompCrm.SmsInboundRolePrompts do
  @moduledoc """
  When one phone number is both a Romp CRM contractor and an active client in a
  booking conversation, we may ask which context they mean and remember the
  answer until the next inbound SMS.
  """

  alias RompCrm.Repo
  alias RompCrm.SmsInboundRolePrompts.RolePrompt

  def get(phone_normalized) when is_binary(phone_normalized) do
    Repo.get_by(RolePrompt, phone_normalized: phone_normalized)
  end

  def store!(phone_normalized, user_id, business_names)
      when is_binary(phone_normalized) and is_integer(user_id) and is_list(business_names) do
    attrs = %{
      phone_normalized: phone_normalized,
      user_id: user_id,
      booking_business_names_json: Jason.encode!(business_names)
    }

    case get(phone_normalized) do
      nil ->
        %RolePrompt{} |> RolePrompt.changeset(attrs) |> Repo.insert!()

      row ->
        row |> RolePrompt.changeset(attrs) |> Repo.update!()
    end
  end

  def clear(phone_normalized) when is_binary(phone_normalized) do
    case get(phone_normalized) do
      nil -> :ok
      row -> Repo.delete!(row)
    end
  end

  def business_names(%RolePrompt{booking_business_names_json: json}) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, names} when is_list(names) -> Enum.map(names, &to_string/1)
      _ -> []
    end
  end
end
