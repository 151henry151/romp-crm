defmodule RompCrmWeb.UserRegistrationController do
  use RompCrmWeb, :controller

  alias RompCrm.Accounts
  alias RompCrm.Accounts.User
  alias RompCrm.Billing
  alias RompCrm.Businesses
  alias RompCrm.Gifts
  alias RompCrm.Gifts.GiftSubscription
  alias RompCrmWeb.CardlessTrialToken
  alias RompCrmWeb.UserAuth

  plug :auth_pages_no_store when action in [:new]

  defp auth_pages_no_store(conn, _opts), do: UserAuth.put_auth_pages_no_store(conn)

  def new(conn, params) do
    gift_token_raw = params |> Map.get("gift") |> to_string() |> String.trim()

    if gift_token_raw != "" and Gifts.claimable_gift_token?(gift_token_raw) do
      redirect(conn, to: ~p"/gift/claim/#{gift_token_raw}")
    else
      new_register_form(conn, params, gift_token_raw)
    end
  end

  defp new_register_form(conn, params, gift_token_raw) do
    {gift_registration?, gift_token, gift_email} = gift_registration_context(gift_token_raw)

    conn =
      cond do
        gift_registration? && gift_token != "" ->
          put_session(conn, :pending_gift_token, gift_token)

        gift_token_raw != "" ->
          delete_session(conn, :pending_gift_token)

        true ->
          conn
      end

    conn = apply_cardless_trial_session(conn, params)

    initial_email =
      cond do
        gift_email != "" ->
          gift_email

        true ->
          params
          |> Map.get("email", "")
          |> to_string()
          |> String.trim()
      end

    changeset = Accounts.change_user_email(%User{email: initial_email})

    {invitation_registration?, _inv} = invitation_context(conn)

    render(
      conn,
      :new,
      registration_assigns(
        changeset: changeset,
        invitation_registration: invitation_registration?,
        gift_registration: gift_registration?,
        gift_token: gift_token,
        cardless_trial: cardless_trial_signup?(conn, initial_email)
      )
    )
  end

  defp apply_cardless_trial_session(conn, params) do
    raw = params |> Map.get("t") |> to_string() |> String.trim()

    cond do
      not Billing.paywall_enabled?() ->
        delete_session(conn, :cardless_trial_signup)

      raw != "" and CardlessTrialToken.valid?(raw) ->
        put_session(conn, :cardless_trial_signup, true)

      raw != "" ->
        conn
        |> delete_session(:cardless_trial_signup)
        |> put_flash(:error, "That promotional link is invalid.")

      promo_email?(params) ->
        put_session(conn, :cardless_trial_signup, true)

      true ->
        delete_session(conn, :cardless_trial_signup)
    end
  end

  defp promo_email?(params) when is_map(params) do
    params
    |> Map.get("email", "")
    |> to_string()
    |> String.trim()
    |> Billing.cardless_promo_registration_email?()
  end

  def create(conn, params) do
    %{"user" => user_params} = params
    plan = user_params |> Map.get("plan", "monthly") |> to_string()
    attrs = Map.drop(user_params, ["plan"])

    gift_raw =
      [Map.get(params, "gift"), get_session(conn, :pending_gift_token)]
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.find(&(&1 != ""))

    case classify_registration(conn, attrs) do
      {:via_invitation, invitation} ->
        finish_invite_create(conn, attrs, invitation)

      {:invitation_expired, conn} ->
        conn

      {:invitation_email_mismatch, expected, conn} ->
        cs = Accounts.change_user_email(%User{}, attrs)

        flash =
          "This invitation is for #{expected}. Use that email address or ask for a new invite."

        conn
        |> put_flash(:error, flash)
        |> render(
          :new,
          registration_assigns(
            changeset: %{cs | action: :insert},
            invitation_registration: true,
            gift_registration: false,
            gift_token: "",
            cardless_trial: cardless_trial_signup?(conn, attrs)
          )
        )

      :standard_paywall ->
        gift_ok = gift_raw != nil && gift_pending?(gift_raw)
        cardless? = cardless_trial_signup?(conn, attrs)

        cond do
          gift_ok ->
            finish_create_with_gift(conn, attrs, gift_raw)

          cardless? ->
            finish_create_cardless_trial(conn, attrs)

          Billing.paywall_enabled?() and not Billing.valid_plan?(plan) ->
            conn
            |> put_flash(:error, "Choose monthly or annual billing.")
            |> render_register_form(attrs)

          Billing.paywall_enabled?() and not Billing.plan_configured?(plan) ->
            conn
            |> put_flash(
              :error,
              "This server is not configured for that plan yet. Try the other option or contact support."
            )
            |> render_register_form(attrs)

          true ->
            finish_create(conn, attrs, plan)
        end
    end
  end

  defp gift_registration_context(gift_token) when gift_token == "" do
    {false, "", ""}
  end

  defp gift_registration_context(gift_token) do
    case Gifts.get_gift_by_token(gift_token) do
      %GiftSubscription{redeemed_at: nil} = g ->
        {true, gift_token, g.recipient_email}

      _ ->
        {false, "", ""}
    end
  end

  defp gift_pending?(token) do
    case Gifts.get_gift_by_token(token) do
      %GiftSubscription{redeemed_at: nil} -> true
      _ -> false
    end
  end

  defp classify_registration(conn, attrs) do
    token = get_session(conn, "pending_invitation_token")

    cond do
      not is_binary(token) ->
        :standard_paywall

      true ->
        case Businesses.get_invitation_by_raw_token(token) do
          nil ->
            {:invitation_expired,
             conn
             |> delete_session("pending_invitation_token")
             |> put_flash(
               :error,
               "That invitation link is no longer valid. Ask the business owner for a new invitation, or register below if you are subscribing yourself."
             )
             |> redirect(to: ~p"/users/register")}

          invitation ->
            email =
              attrs
              |> Map.get("email", "")
              |> to_string()
              |> String.trim()
              |> String.downcase()

            inv_email =
              invitation.email
              |> String.trim()
              |> String.downcase()

            cond do
              email != inv_email ->
                {:invitation_email_mismatch, invitation.email, conn}

              true ->
                {:via_invitation, invitation}
            end
        end
    end
  end

  defp finish_invite_create(conn, attrs, invitation) do
    case Accounts.register_user(attrs, invitation: invitation) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        conn
        |> put_flash(
          :info,
          "Check #{user.email} for your sign-in link. After signing in, you’ll finish joining the business — no PayPal subscription needed for invited members."
        )
        |> redirect(to: ~p"/users/log-in")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(
          conn,
          :new,
          registration_assigns(
            changeset: %{changeset | action: :insert},
            invitation_registration: true,
            gift_registration: false,
            gift_token: "",
            cardless_trial: cardless_trial_signup?(conn, attrs)
          )
        )
    end
  end

  defp render_register_form(conn, attrs) do
    cs = Accounts.change_user_email(%User{}, attrs)
    changeset = %{cs | action: :insert}
    {invitation_registration?, _} = invitation_context(conn)
    gift_token = get_session(conn, :pending_gift_token) |> to_string() |> String.trim()
    {gift_registration?, gift_token, _} = gift_registration_context(gift_token)

    render(
      conn,
      :new,
      registration_assigns(
        changeset: changeset,
        invitation_registration: invitation_registration?,
        gift_registration: gift_registration?,
        gift_token: gift_token,
        cardless_trial: cardless_trial_signup?(conn, attrs)
      )
    )
  end

  defp registration_assigns(extra) do
    invitation_registration = Keyword.get(extra, :invitation_registration, false)
    gift_registration = Keyword.get(extra, :gift_registration, false)
    gift_token = Keyword.get(extra, :gift_token, "")
    cardless_trial = Keyword.get(extra, :cardless_trial, false)

    Keyword.merge(
      [
        subscription_paywall:
          Billing.paywall_enabled?() && !invitation_registration && !gift_registration &&
            !cardless_trial,
        paypal_trial_days: Billing.paypal_trial_days(),
        invitation_registration: invitation_registration,
        gift_registration: gift_registration,
        gift_token: gift_token,
        cardless_trial: cardless_trial
      ],
      extra
    )
  end

  defp invitation_context(conn) do
    token = get_session(conn, "pending_invitation_token")

    if is_binary(token) do
      case Businesses.get_invitation_by_raw_token(token) do
        nil -> {false, nil}
        %_{} = inv -> {true, inv}
      end
    else
      {false, nil}
    end
  end

  defp finish_create_with_gift(conn, attrs, gift_token) do
    case Accounts.register_user(attrs) do
      {:ok, user} ->
        case Gifts.apply_after_registration(user, gift_token) do
          {:ok, user} ->
            {:ok, _} =
              Accounts.deliver_login_instructions(
                user,
                &url(~p"/users/log-in/#{&1}")
              )

            conn
            |> delete_session(:pending_gift_token)
            |> put_flash(
              :info,
              "Check #{user.email} for your sign-in link to activate your gifted subscription (no payment)."
            )
            |> redirect(to: ~p"/users/log-in")

          {:error, :email_mismatch} ->
            conn
            |> put_flash(:error, "Registration email must match the gift recipient address.")
            |> render_register_form(attrs)

          {:error, :already_redeemed} ->
            conn
            |> put_flash(:error, "That gift was already redeemed.")
            |> render_register_form(attrs)

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not apply the gift. Contact support.")
            |> render_register_form(attrs)
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {invitation_registration?, _} = invitation_context(conn)
        gift_tok = gift_token

        render(
          conn,
          :new,
          registration_assigns(
            changeset: %{changeset | action: :insert},
            invitation_registration: invitation_registration?,
            gift_registration: true,
            gift_token: gift_tok,
            cardless_trial: cardless_trial_signup?(conn, attrs)
          )
        )
    end
  end

  defp finish_create_cardless_trial(conn, attrs) do
    email = register_email(attrs)
    existed_before? = email != "" and Accounts.get_user_by_email(email) != nil

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        cond do
          existed_before? and Billing.paywall_enabled?() and Accounts.resumable_paywall_signup?(user) ->
            conn
            |> delete_session(:cardless_trial_signup)
            |> put_session(:pending_paywall_user_id, user.id)
            |> put_flash(
              :info,
              "This email already has an account waiting for billing. Continue on the subscription page to add PayPal."
            )
            |> redirect(to: ~p"/subscribe")

          true ->
            case Accounts.apply_cardless_promo_trial(user, 30) do
              {:ok, user} ->
                {:ok, _} =
                  Accounts.deliver_login_instructions(
                    user,
                    &url(~p"/users/log-in/#{&1}")
                  )

                conn
                |> delete_session(:cardless_trial_signup)
                |> put_flash(
                  :info,
                  "Check #{user.email} for your sign-in link. You have 30 days of full access without a card; add PayPal on the subscription page before then to keep using the app."
                )
                |> redirect(to: ~p"/users/log-in")

              {:error, _} ->
                conn
                |> put_flash(:error, "Could not start your trial. Try again or contact support.")
                |> render_register_form(attrs)
            end
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {invitation_registration?, _} = invitation_context(conn)

        render(
          conn,
          :new,
          registration_assigns(
            changeset: %{changeset | action: :insert},
            invitation_registration: invitation_registration?,
            gift_registration: false,
            gift_token: "",
            cardless_trial: cardless_trial_signup?(conn, attrs)
          )
        )
    end
  end

  defp cardless_trial_signup?(conn, email) when is_binary(email) do
    Billing.paywall_enabled?() and
      (get_session(conn, :cardless_trial_signup) == true or
         Billing.cardless_promo_registration_email?(email))
  end

  defp cardless_trial_signup?(conn, attrs) when is_map(attrs) do
    cardless_trial_signup?(conn, register_email(attrs))
  end

  defp register_email(attrs) when is_map(attrs) do
    (Map.get(attrs, "email") || Map.get(attrs, :email) || "")
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp finish_create(conn, attrs, plan) do
    case Accounts.register_user(attrs) do
      {:ok, user} ->
        if Billing.paywall_enabled?() do
          return_url = fn -> url(conn, ~p"/subscribe/paypal/return") end
          cancel_url = fn -> url(conn, ~p"/subscribe/paypal/cancel") end

          case Billing.start_paypal_checkout(user, plan, return_url, cancel_url) do
            {:ok, %{approve_url: approve}} ->
              conn
              |> delete_session(:cardless_trial_signup)
              |> put_session(:pending_paywall_user_id, user.id)
              |> put_session(:pending_paywall_plan, plan)
              |> redirect(external: approve)

            {:error, _} ->
              conn
              |> put_flash(
                :error,
                "Could not start PayPal checkout. Try again in a minute or resume from the subscription page."
              )
              |> put_session(:pending_paywall_user_id, user.id)
              |> put_session(:pending_paywall_plan, plan)
              |> redirect(to: ~p"/subscribe")
          end
        else
          {:ok, _} =
            Accounts.deliver_login_instructions(
              user,
              &url(~p"/users/log-in/#{&1}")
            )

          conn
          |> delete_session(:cardless_trial_signup)
          |> put_flash(
            :info,
            "An email was sent to #{user.email}, please access it to confirm your account."
          )
          |> redirect(to: ~p"/users/log-in")
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {invitation_registration?, _} = invitation_context(conn)
        gift_tok = get_session(conn, :pending_gift_token) |> to_string() |> String.trim()
        {gift_reg?, gift_tok2, _} = gift_registration_context(gift_tok)

        render(
          conn,
          :new,
          registration_assigns(
            changeset: %{changeset | action: :insert},
            invitation_registration: invitation_registration?,
            gift_registration: gift_reg?,
            gift_token: gift_tok2,
            cardless_trial: cardless_trial_signup?(conn, attrs)
          )
        )
    end
  end
end
