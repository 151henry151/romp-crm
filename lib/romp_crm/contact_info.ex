defmodule RompCrm.ContactInfo do
  @moduledoc """
  Client phone and email validation/formatting for job contact fields.
  """

  alias RompCrm.Twilio.Phone

  @email_re ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/u
  @email_html_pattern "[^\\s@]+@[^\\s@]+\\.[^\\s@]+"

  @countries [
    {"US +1", "1"},
    {"CA +1", "1"},
    {"UK +44", "44"},
    {"MX +52", "52"},
    {"AU +61", "61"},
    {"DE +49", "49"},
    {"FR +33", "33"},
    {"IN +91", "91"},
    {"BR +55", "55"},
    {"JP +81", "81"}
  ]

  def countries, do: @countries
  def email_html_pattern, do: @email_html_pattern
  def email_hint, do: "Use a name@domain.tld address"
  def email_validation_message, do: "Enter a valid email address (name@domain.tld)"
  def phone_validation_message, do: "Enter a valid phone number for the selected country"

  def normalize_email(value) do
    case blank_to_nil(value) do
      nil ->
        {:ok, nil}

      email ->
        if String.match?(email, @email_re) do
          {:ok, email}
        else
          {:error, email_validation_message()}
        end
    end
  end

  def normalize_phone(value) when is_binary(value) do
    case blank_to_nil(value) do
      nil ->
        {:ok, nil}

      phone ->
        parse_stored_phone(phone)
    end
  end

  def normalize_phone(dial_code, national) when is_binary(dial_code) and is_binary(national) do
    dial = digits_only(dial_code)
    national_digits = digits_only(national)

    if national_digits == "" do
      {:ok, nil}
    else
      with :ok <- validate_national(dial, national_digits) do
        {:ok, "+#{dial}#{national_digits}"}
      end
    end
  end

  def split_phone(value) do
    case blank_to_nil(value) do
      nil ->
        default_split()

      phone ->
        digits = digits_only(phone)

        cond do
          String.starts_with?(phone, "+") ->
            split_prefixed_digits(digits)

          byte_size(digits) == 11 and String.starts_with?(digits, "1") ->
            {"1", String.slice(digits, 1..-1//1)}

          byte_size(digits) == 10 ->
            {"1", digits}

          true ->
            split_prefixed_digits(digits)
        end
    end
  end

  def format_display(nil), do: ""
  def format_display(""), do: ""

  def format_display(phone) when is_binary(phone) do
    {dial, national} = split_phone(phone)

    case dial do
      "1" ->
        Phone.format_us_display(national)

      _ ->
        if national == "" do
          phone
        else
          "+#{dial} #{national}"
        end
    end
  end

  def format_national_display(dial_code, national) do
    national_digits = digits_only(national)

    case dial_code do
      "1" when byte_size(national_digits) == 10 ->
        Phone.format_us_display(national_digits)

      _ ->
        national_digits
    end
  end

  def national_placeholder("1"), do: "(555) 555-1234"
  def national_placeholder(_), do: "Phone number"

  def validate_job_changeset(changeset) do
    import Ecto.Changeset

    changeset
    |> validate_optional_phone()
    |> validate_optional_email()
  end

  defp validate_optional_phone(changeset) do
    import Ecto.Changeset

    case get_change(changeset, :phone) || get_field(changeset, :phone) do
      nil ->
        changeset

      "" ->
        changeset

      phone ->
        case normalize_phone(phone) do
          {:ok, nil} -> put_change(changeset, :phone, nil)
          {:ok, normalized} -> put_change(changeset, :phone, normalized)
          {:error, msg} -> add_error(changeset, :phone, msg)
        end
    end
  end

  defp validate_optional_email(changeset) do
    import Ecto.Changeset

    case get_change(changeset, :client_email) || get_field(changeset, :client_email) do
      nil ->
        changeset

      "" ->
        changeset

      email ->
        case normalize_email(email) do
          {:ok, nil} -> put_change(changeset, :client_email, nil)
          {:ok, normalized} -> put_change(changeset, :client_email, normalized)
          {:error, msg} -> add_error(changeset, :client_email, msg)
        end
    end
  end

  defp parse_stored_phone(phone) do
    {dial, national} = split_phone(phone)

    if national == "" do
      {:ok, nil}
    else
      normalize_phone(dial, national)
    end
  end

  defp split_prefixed_digits(digits) do
    case longest_dial_match(digits) do
      {dial, rest} when rest != "" ->
        {dial, rest}

      _ ->
        default_split()
    end
  end

  defp longest_dial_match(digits) do
    codes =
      @countries
      |> Enum.map(fn {_, code} -> code end)
      |> Enum.uniq()
      |> Enum.sort_by(&byte_size/1, :desc)

    Enum.find_value(codes, fn code ->
      if String.starts_with?(digits, code) do
        rest = String.slice(digits, byte_size(code)..-1//1)
        if rest != "", do: {code, rest}
      end
    end) || default_split()
  end

  defp validate_national("1", digits) do
    if valid_nanp_10?(digits), do: :ok, else: {:error, phone_validation_message()}
  end

  defp validate_national(_dial, digits) do
    size = byte_size(digits)

    if size >= 7 and size <= 14 do
      :ok
    else
      {:error, phone_validation_message()}
    end
  end

  defp valid_nanp_10?(digits) when byte_size(digits) == 10 do
    <<area::binary-size(3), exchange::binary-size(3), _subscriber::binary-size(4)>> = digits
    valid_nxx?(area) and valid_nxx?(exchange)
  end

  defp valid_nanp_10?(_), do: false

  defp valid_nxx?(<<first::binary-size(1), _::binary>>) do
    first in ~w(2 3 4 5 6 7 8 9)
  end

  defp default_split, do: {"1", ""}

  defp blank_to_nil(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp digits_only(value) do
    value |> to_string() |> String.replace(~r/\D/, "")
  end
end
