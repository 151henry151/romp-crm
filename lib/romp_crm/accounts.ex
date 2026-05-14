defmodule RompCrm.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias RompCrm.Repo

  alias RompCrm.Accounts.{User, UserToken, UserNotifier}
  alias RompCrm.Businesses.BusinessInvitation
  alias RompCrm.DataExportSchedule

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Inserts a **confirmed** user for a gift-recipient email (no registration allowlist check).

  Used only from the gift claim flow. Sets a random **`hashed_password`** so the row is valid;
  the recipient should use magic-link sign-in or set a password later.

  Returns **`{:error, :exists}`** if the email is already taken.
  """
  def insert_gift_recipient_user(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()

    if get_user_by_email(email) do
      {:error, :exists}
    else
      now = DateTime.utc_now(:second)
      secret = :crypto.strong_rand_bytes(32) |> Base.encode64(padding: false)
      hash = Bcrypt.hash_pwd_salt(secret)

      attrs = %{
        email: email,
        hashed_password: hash,
        confirmed_at: now
      }

      attrs =
        if RompCrm.ApplicationConfig.subscription_paywall_enabled?() do
          Map.merge(attrs, %{
            subscription_status: "pending_payment",
            paypal_subscription_id: nil,
            paypal_plan_id: nil
          })
        else
          Map.put(attrs, :subscription_status, "active")
        end

      %User{}
      |> Ecto.Changeset.change(attrs)
      |> Ecto.Changeset.unique_constraint(:email)
      |> Repo.insert()
    end
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  When **`subscription_paywall_enabled`** is true, if the email already belongs to an account
  that never finished PayPal (**`subscription_status` `pending_payment`** and **`confirmed_at`**
  still **`nil`**), returns **`{:ok, that user}`** so sign-up can restart checkout instead of failing
  with “email has already been taken”.

  ## Options

    * `:enforce_allowlist` — override **`Application`** `enforce_registration_allowlist` (for tests).
    * `:allowlist` — override **`Application`** `registration_email_allowlist` (list of downcased emails).
    * `:invitation` — pass **`%BusinessInvitation{}`** when registering from an invite link; skips hosted
      PayPal paywall and creates an **`invited_member`** account that **`may_create_business`** **`false`**.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs, opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :invitation) do
      %BusinessInvitation{} = inv ->
        register_user_via_invitation(attrs, inv, opts)

      _ ->
        register_user_standard(attrs, opts)
    end
  end

  defp register_user_via_invitation(attrs, %BusinessInvitation{} = inv, opts)
       when is_list(opts) do
    changeset =
      %User{}
      |> User.email_changeset(attrs, validate_unique: false)

    cond do
      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      not invitation_email_matches_changeset?(inv, changeset) ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(
           :email,
           "must match the invitation (use the email address the invitation was sent to)"
         )
         |> Map.put(:action, :insert)}

      not registration_email_allowed?(changeset, opts) ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(
           :email,
           "is not authorized for registration on this server"
         )
         |> Map.put(:action, :insert)}

      true ->
        insert_invited_member_user(attrs, opts)
    end
  end

  defp invitation_email_matches_changeset?(%BusinessInvitation{} = inv, changeset) do
    reg =
      changeset
      |> Ecto.Changeset.get_field(:email)
      |> to_string()
      |> String.trim()
      |> String.downcase()

    inv_email =
      inv.email
      |> String.trim()
      |> String.downcase()

    reg != "" and reg == inv_email
  end

  defp insert_invited_member_user(attrs, opts) when is_list(opts) do
    changeset = %User{} |> User.email_changeset(attrs)

    cond do
      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      not registration_email_allowed?(changeset, opts) ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(
           :email,
           "is not authorized for registration on this server"
         )
         |> Map.put(:action, :insert)}

      true ->
        Repo.transact(fn ->
          with {:ok, user} <- Repo.insert(changeset),
               {:ok, user} <- mark_invited_member_profile(user),
               do: {:ok, user}
        end)
    end
  end

  defp mark_invited_member_profile(%User{} = user) do
    user
    |> Ecto.Changeset.change(
      subscription_status: "invited_member",
      may_create_business: false
    )
    |> Repo.update()
  end

  defp register_user_standard(attrs, opts) when is_list(opts) do
    changeset =
      %User{}
      |> User.email_changeset(attrs, validate_unique: false)

    cond do
      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      not registration_email_allowed?(changeset, opts) ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(
           :email,
           "is not authorized for registration on this server"
         )
         |> Map.put(:action, :insert)}

      RompCrm.ApplicationConfig.subscription_paywall_enabled?() ->
        email = Ecto.Changeset.get_field(changeset, :email)

        case Repo.get_by(User, email: email) do
          %User{} = existing ->
            if resumable_paywall_signup?(existing) do
              {:ok, existing}
            else
              {:error, duplicate_email_registration_changeset(attrs)}
            end

          nil ->
            insert_new_registered_user(attrs, opts)
        end

      true ->
        insert_new_registered_user(attrs, opts)
    end
  end

  defp insert_new_registered_user(attrs, opts) when is_list(opts) do
    changeset = %User{} |> User.email_changeset(attrs)

    cond do
      not changeset.valid? ->
        {:error, %{changeset | action: :insert}}

      not registration_email_allowed?(changeset, opts) ->
        {:error,
         changeset
         |> Ecto.Changeset.add_error(
           :email,
           "is not authorized for registration on this server"
         )
         |> Map.put(:action, :insert)}

      true ->
        Repo.transact(fn ->
          with {:ok, user} <- Repo.insert(changeset),
               {:ok, user} <- maybe_mark_pending_paywall(user),
               do: {:ok, user}
        end)
    end
  end

  defp duplicate_email_registration_changeset(attrs) do
    cs = %User{} |> User.email_changeset(attrs)
    %{cs | action: :insert}
  end

  @doc false
  def resumable_paywall_signup?(%User{
        subscription_status: "pending_payment",
        confirmed_at: nil
      }),
      do: true

  def resumable_paywall_signup?(_), do: false

  @doc """
  Sets **`gift_access_until`** to **`days`** days from now (UTC) for promo signups that skip PayPal.

  **`Billing.subscription_active?/1`** treats unexpired **`gift_access_until`** like active access.
  """
  def apply_cardless_promo_trial(%User{} = user, days \\ 30)
      when is_integer(days) and days > 0 do
    until = DateTime.add(DateTime.utc_now(:second), days, :day)

    user
    |> Ecto.Changeset.change(gift_access_until: until)
    |> Repo.update()
  end

  defp maybe_mark_pending_paywall(user) do
    if RompCrm.ApplicationConfig.subscription_paywall_enabled?() do
      user
      |> Ecto.Changeset.change(
        subscription_status: "pending_payment",
        paypal_subscription_id: nil,
        paypal_plan_id: nil
      )
      |> Repo.update()
    else
      {:ok, user}
    end
  end

  defp registration_email_allowed?(%Ecto.Changeset{} = cs, opts) when is_list(opts) do
    enforce? =
      Keyword.get(
        opts,
        :enforce_allowlist,
        Application.get_env(:romp_crm, :enforce_registration_allowlist, false)
      )

    unless enforce? do
      true
    else
      email =
        cs
        |> Ecto.Changeset.get_field(:email)
        |> to_string()
        |> String.downcase()

      allow =
        Keyword.get(
          opts,
          :allowlist,
          Application.get_env(:romp_crm, :registration_email_allowlist, [])
        )

      email != "" and email in allow
    end
  end

  def get_user_by_phone_normalized(nil), do: nil
  def get_user_by_phone_normalized(""), do: nil

  def get_user_by_phone_normalized(phone) when is_binary(phone) do
    Repo.get_by(User, phone_normalized: phone)
  end

  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  def update_user_profile(%User{} = user, attrs) when is_map(attrs) do
    allowed_ids =
      user
      |> RompCrm.Businesses.list_businesses_for_user()
      |> Enum.map(& &1.id)
      |> MapSet.new()

    attrs = normalize_profile_attrs(attrs)

    changeset = User.profile_changeset(user, attrs)

    changeset =
      case Ecto.Changeset.get_change(changeset, :sms_business_id) do
        nil ->
          changeset

        bid when is_integer(bid) ->
          if MapSet.member?(allowed_ids, bid) do
            changeset
          else
            Ecto.Changeset.add_error(
              changeset,
              :sms_business_id,
              "must be a business you belong to"
            )
          end

        _ ->
          changeset
      end

    Repo.update(changeset)
  end

  @doc """
  Marks the first-login SMS assistant intro as finished without saving a phone number.
  """
  def skip_sms_assistant_intro(%User{} = user), do: mark_sms_assistant_intro_completed(user)

  @doc """
  Saves **`attrs`** as the profile **`phone`** (and derived **`phone_normalized`**), sends the
  welcome SMS when outbound SMS is enabled, then marks the intro flow complete.

  Twilio errors do not roll back the saved phone number.
  """
  def complete_sms_assistant_intro_with_phone(%User{} = user, attrs) when is_map(attrs) do
    case update_user_profile(user, profile_phone_only_attrs(attrs)) do
      {:error, _} = err ->
        err

      {:ok, %User{} = user} ->
        sms_result = RompCrm.SmsAssistantIntro.send_welcome_sms(user)

        case mark_sms_assistant_intro_completed(user) do
          {:ok, u} -> {:ok, u, sms_result}
          {:error, _} = err -> err
        end
    end
  end

  @doc false
  def mark_sms_assistant_intro_completed(%User{} = user) do
    user
    |> Ecto.Changeset.change(sms_assistant_intro_completed_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  defp profile_phone_only_attrs(attrs) when is_map(attrs) do
    flat =
      Enum.into(attrs, %{}, fn
        {k, v} when is_atom(k) -> {Atom.to_string(k), v}
        {k, v} -> {to_string(k), v}
      end)

    %{"phone" => flat |> Map.get("phone", "") |> to_string()}
  end

  defp normalize_profile_attrs(attrs) when is_map(attrs) do
    attrs =
      Enum.into(attrs, %{}, fn
        {k, v} when is_atom(k) -> {Atom.to_string(k), v}
        {k, v} -> {to_string(k), v}
      end)

    case attrs["sms_business_id"] do
      "" ->
        Map.put(attrs, "sms_business_id", nil)

      nil ->
        attrs

      v when is_integer(v) ->
        attrs

      v when is_binary(v) ->
        case Integer.parse(String.trim(v)) do
          {n, _} -> Map.put(attrs, "sms_business_id", n)
          :error -> Map.put(attrs, "sms_business_id", nil)
        end

      _ ->
        attrs
    end
  end

  @doc """
  Sets `sms_business_id` the first time a user creates their only (or first) business.
  """
  def maybe_set_default_sms_business(%User{sms_business_id: nil} = user, business_id)
      when is_integer(business_id) do
    user
    |> Ecto.Changeset.change(sms_business_id: business_id)
    |> Repo.update()
  end

  def maybe_set_default_sms_business(%User{}, _), do: {:ok, :skipped}

  @doc """
  Saves which business/workspace the Jobs list and picker use (`users.selected_business_id`).
  Fails when the user is not a member of that business.

  Prefer this over touching `selected_business_id` directly so eligibility is enforced.
  """
  def put_jobs_workspace_selection(%User{} = user, business_id)
      when is_integer(business_id) do
    if RompCrm.Businesses.member?(user, business_id) do
      user
      |> Ecto.Changeset.change(selected_business_id: business_id)
      |> Repo.update()
    else
      {:error, :not_member}
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `RompCrm.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `RompCrm.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc "Returns a changeset for **`data_export_schedule`** (CSV email export)."
  def change_user_export_settings(%User{} = user, attrs \\ %{}) do
    User.export_settings_changeset(user, attrs)
  end

  @doc "Updates scheduled CSV export; recalculates **`data_export_next_run_at`** when schedule is not **`none`**."
  def update_user_export_settings(%User{} = user, attrs) when is_map(attrs) do
    user
    |> User.export_settings_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  After a successful export email, sets **`data_export_last_sent_at`** and advances
  **`data_export_next_run_at`** by the current schedule interval.
  """
  def advance_data_export_schedule_after_send(%User{id: id}) do
    user = get_user!(id)
    now = DateTime.utc_now(:second)

    next_at =
      case user.data_export_schedule do
        "none" -> nil
        sch -> DataExportSchedule.compute_next_run_at(sch, now)
      end

    user
    |> Ecto.Changeset.change(%{
      data_export_last_sent_at: now,
      data_export_next_run_at: next_at
    })
    |> Repo.update()
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
