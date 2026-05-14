defmodule RompCrmWeb.CardlessTrialToken do
  @moduledoc false

  @salt "cardless_trial_v1"

  @doc "Returns true if `token` is a valid signed promo signup token."
  def valid?(token) when is_binary(token) do
    token = String.trim(token)

    if token == "" do
      false
    else
      match?({:ok, _}, Phoenix.Token.verify(RompCrmWeb.Endpoint, @salt, token, max_age: :infinity))
    end
  end

  def valid?(_), do: false

  @doc "Build a signed token for the cardless 30-day trial link (stable for a given secret_key_base)."
  def sign do
    Phoenix.Token.sign(RompCrmWeb.Endpoint, @salt, "1", max_age: :infinity)
  end
end
