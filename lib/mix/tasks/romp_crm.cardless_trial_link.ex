defmodule Mix.Tasks.RompCrm.CardlessTrialLink do
  @shortdoc "Print the HTTPS register URL with a signed cardless 30-day trial token"
  @moduledoc """
  Prints one line: the public **`/users/register`** URL with query **`t=`** signed by **`secret_key_base`**.

  Run on the **same** machine and release as production so the token matches **`Phoenix.Token`** verification.

      mix romp_crm.cardless_trial_link
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:romp_crm)
    base = RompCrmWeb.Endpoint.url() |> String.trim_trailing("/")
    path = RompCrmWeb.PathPrefix.request_path("/users/register")
    t = RompCrmWeb.CardlessTrialToken.sign()
    url = base <> path <> "?" <> URI.encode_query(%{"t" => t})
    Mix.shell().info(url)
  end
end
