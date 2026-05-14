defmodule Mix.Tasks.RompCrm.CardlessTrialLink do
  @shortdoc "Print the HTTPS register URL with a signed cardless 30-day trial token"
  @moduledoc """
  Prints one line: the public **`/users/register`** URL with query **`t=`** signed by **`secret_key_base`**.

  **Production (recommended):** run against the **live** release so the endpoint URL and token match what nginx serves:

      bin/romp_crm rpc 'IO.puts(RompCrmWeb.Endpoint.url() <> RompCrmWeb.PathPrefix.request_path("/users/register") <> "?" <> URI.encode_query(%{"t" => RompCrmWeb.CardlessTrialToken.sign()}))'

  **Dev / CI:** with **`MIX_ENV=prod`** and **`SECRET_KEY_BASE`**, **`DATABASE_PATH`**, etc. exported (same as **`.env.production`**), Mix can start the app and print the line:

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
