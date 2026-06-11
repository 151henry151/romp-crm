defmodule RompCrm.Scheduling.TimezoneInference do
  @moduledoc """
  Infers a default IANA timezone from a US phone number's area code or a client IP.

  Used when initializing scheduling prefs — contractors can change timezone in Settings.
  """

  @default "America/New_York"

  # Common NANP area codes → IANA (subset; unknown codes use regional fallback).
  @area_to_tz %{
    "201" => "America/New_York",
    "202" => "America/New_York",
    "203" => "America/New_York",
    "205" => "America/Chicago",
    "206" => "America/Los_Angeles",
    "207" => "America/New_York",
    "208" => "America/Boise",
    "209" => "America/Los_Angeles",
    "210" => "America/Chicago",
    "212" => "America/New_York",
    "213" => "America/Los_Angeles",
    "214" => "America/Chicago",
    "215" => "America/New_York",
    "216" => "America/New_York",
    "217" => "America/Chicago",
    "218" => "America/Chicago",
    "219" => "America/Chicago",
    "224" => "America/Chicago",
    "225" => "America/Chicago",
    "228" => "America/Chicago",
    "229" => "America/New_York",
    "231" => "America/New_York",
    "234" => "America/New_York",
    "239" => "America/New_York",
    "240" => "America/New_York",
    "248" => "America/New_York",
    "251" => "America/Chicago",
    "252" => "America/New_York",
    "253" => "America/Los_Angeles",
    "254" => "America/Chicago",
    "256" => "America/Chicago",
    "260" => "America/New_York",
    "262" => "America/Chicago",
    "267" => "America/New_York",
    "269" => "America/New_York",
    "270" => "America/New_York",
    "281" => "America/Chicago",
    "301" => "America/New_York",
    "302" => "America/New_York",
    "303" => "America/Denver",
    "304" => "America/New_York",
    "305" => "America/New_York",
    "307" => "America/Denver",
    "308" => "America/Chicago",
    "309" => "America/Chicago",
    "310" => "America/Los_Angeles",
    "312" => "America/Chicago",
    "313" => "America/New_York",
    "314" => "America/Chicago",
    "315" => "America/New_York",
    "316" => "America/Chicago",
    "317" => "America/New_York",
    "318" => "America/Chicago",
    "319" => "America/Chicago",
    "320" => "America/Chicago",
    "321" => "America/New_York",
    "323" => "America/Los_Angeles",
    "325" => "America/Chicago",
    "330" => "America/New_York",
    "331" => "America/Chicago",
    "334" => "America/Chicago",
    "336" => "America/New_York",
    "337" => "America/Chicago",
    "339" => "America/New_York",
    "346" => "America/Chicago",
    "347" => "America/New_York",
    "351" => "America/New_York",
    "352" => "America/New_York",
    "360" => "America/Los_Angeles",
    "361" => "America/Chicago",
    "385" => "America/Denver",
    "386" => "America/New_York",
    "401" => "America/New_York",
    "402" => "America/Chicago",
    "404" => "America/New_York",
    "405" => "America/Chicago",
    "406" => "America/Denver",
    "407" => "America/New_York",
    "408" => "America/Los_Angeles",
    "409" => "America/Chicago",
    "410" => "America/New_York",
    "412" => "America/New_York",
    "413" => "America/New_York",
    "414" => "America/Chicago",
    "415" => "America/Los_Angeles",
    "417" => "America/Chicago",
    "419" => "America/New_York",
    "423" => "America/New_York",
    "424" => "America/Los_Angeles",
    "425" => "America/Los_Angeles",
    "430" => "America/Chicago",
    "432" => "America/Chicago",
    "434" => "America/New_York",
    "435" => "America/Denver",
    "440" => "America/New_York",
    "442" => "America/Los_Angeles",
    "443" => "America/New_York",
    "458" => "America/Los_Angeles",
    "469" => "America/Chicago",
    "470" => "America/New_York",
    "475" => "America/New_York",
    "478" => "America/New_York",
    "479" => "America/Chicago",
    "480" => "America/Phoenix",
    "484" => "America/New_York",
    "501" => "America/Chicago",
    "502" => "America/New_York",
    "503" => "America/Los_Angeles",
    "504" => "America/Chicago",
    "505" => "America/Denver",
    "507" => "America/Chicago",
    "508" => "America/New_York",
    "509" => "America/Los_Angeles",
    "510" => "America/Los_Angeles",
    "512" => "America/Chicago",
    "513" => "America/New_York",
    "515" => "America/Chicago",
    "516" => "America/New_York",
    "517" => "America/New_York",
    "518" => "America/New_York",
    "520" => "America/Phoenix",
    "530" => "America/Los_Angeles",
    "531" => "America/Chicago",
    "534" => "America/Chicago",
    "539" => "America/Chicago",
    "540" => "America/New_York",
    "541" => "America/Los_Angeles",
    "551" => "America/New_York",
    "559" => "America/Los_Angeles",
    "561" => "America/New_York",
    "562" => "America/Los_Angeles",
    "563" => "America/Chicago",
    "567" => "America/New_York",
    "570" => "America/New_York",
    "571" => "America/New_York",
    "573" => "America/Chicago",
    "574" => "America/New_York",
    "575" => "America/Denver",
    "580" => "America/Chicago",
    "585" => "America/New_York",
    "586" => "America/New_York",
    "601" => "America/Chicago",
    "602" => "America/Phoenix",
    "603" => "America/New_York",
    "605" => "America/Chicago",
    "606" => "America/New_York",
    "607" => "America/New_York",
    "608" => "America/Chicago",
    "609" => "America/New_York",
    "610" => "America/New_York",
    "612" => "America/Chicago",
    "614" => "America/New_York",
    "615" => "America/Chicago",
    "616" => "America/New_York",
    "617" => "America/New_York",
    "618" => "America/Chicago",
    "619" => "America/Los_Angeles",
    "620" => "America/Chicago",
    "623" => "America/Phoenix",
    "626" => "America/Los_Angeles",
    "628" => "America/Los_Angeles",
    "629" => "America/Chicago",
    "630" => "America/Chicago",
    "631" => "America/New_York",
    "636" => "America/Chicago",
    "641" => "America/Chicago",
    "646" => "America/New_York",
    "650" => "America/Los_Angeles",
    "651" => "America/Chicago",
    "657" => "America/Los_Angeles",
    "660" => "America/Chicago",
    "661" => "America/Los_Angeles",
    "662" => "America/Chicago",
    "667" => "America/New_York",
    "669" => "America/Los_Angeles",
    "678" => "America/New_York",
    "681" => "America/New_York",
    "682" => "America/Chicago",
    "701" => "America/Chicago",
    "702" => "America/Los_Angeles",
    "703" => "America/New_York",
    "704" => "America/New_York",
    "706" => "America/New_York",
    "707" => "America/Los_Angeles",
    "708" => "America/Chicago",
    "712" => "America/Chicago",
    "713" => "America/Chicago",
    "714" => "America/Los_Angeles",
    "715" => "America/Chicago",
    "716" => "America/New_York",
    "717" => "America/New_York",
    "718" => "America/New_York",
    "719" => "America/Denver",
    "720" => "America/Denver",
    "724" => "America/New_York",
    "725" => "America/Los_Angeles",
    "727" => "America/New_York",
    "731" => "America/Chicago",
    "732" => "America/New_York",
    "734" => "America/New_York",
    "737" => "America/Chicago",
    "740" => "America/New_York",
    "747" => "America/Los_Angeles",
    "754" => "America/New_York",
    "757" => "America/New_York",
    "760" => "America/Los_Angeles",
    "762" => "America/New_York",
    "763" => "America/Chicago",
    "765" => "America/New_York",
    "769" => "America/Chicago",
    "770" => "America/New_York",
    "772" => "America/New_York",
    "773" => "America/Chicago",
    "774" => "America/New_York",
    "775" => "America/Los_Angeles",
    "781" => "America/New_York",
    "785" => "America/Chicago",
    "786" => "America/New_York",
    "801" => "America/Denver",
    "802" => "America/New_York",
    "803" => "America/New_York",
    "804" => "America/New_York",
    "805" => "America/Los_Angeles",
    "806" => "America/Chicago",
    "808" => "Pacific/Honolulu",
    "810" => "America/New_York",
    "812" => "America/New_York",
    "813" => "America/New_York",
    "814" => "America/New_York",
    "815" => "America/Chicago",
    "816" => "America/Chicago",
    "817" => "America/Chicago",
    "818" => "America/Los_Angeles",
    "828" => "America/New_York",
    "830" => "America/Chicago",
    "831" => "America/Los_Angeles",
    "832" => "America/Chicago",
    "843" => "America/New_York",
    "845" => "America/New_York",
    "847" => "America/Chicago",
    "848" => "America/New_York",
    "850" => "America/Chicago",
    "856" => "America/New_York",
    "857" => "America/New_York",
    "858" => "America/Los_Angeles",
    "859" => "America/New_York",
    "860" => "America/New_York",
    "862" => "America/New_York",
    "863" => "America/New_York",
    "864" => "America/New_York",
    "865" => "America/New_York",
    "870" => "America/Chicago",
    "872" => "America/Chicago",
    "878" => "America/New_York",
    "901" => "America/Chicago",
    "903" => "America/Chicago",
    "904" => "America/New_York",
    "906" => "America/New_York",
    "907" => "America/Anchorage",
    "908" => "America/New_York",
    "909" => "America/Los_Angeles",
    "910" => "America/New_York",
    "912" => "America/New_York",
    "913" => "America/Chicago",
    "914" => "America/New_York",
    "915" => "America/Denver",
    "916" => "America/Los_Angeles",
    "917" => "America/New_York",
    "918" => "America/Chicago",
    "919" => "America/New_York",
    "920" => "America/Chicago",
    "925" => "America/Los_Angeles",
    "928" => "America/Phoenix",
    "929" => "America/New_York",
    "931" => "America/Chicago",
    "936" => "America/Chicago",
    "937" => "America/New_York",
    "938" => "America/Chicago",
    "940" => "America/Chicago",
    "941" => "America/New_York",
    "947" => "America/New_York",
    "949" => "America/Los_Angeles",
    "951" => "America/Los_Angeles",
    "952" => "America/Chicago",
    "954" => "America/New_York",
    "956" => "America/Chicago",
    "959" => "America/New_York",
    "970" => "America/Denver",
    "971" => "America/Los_Angeles",
    "972" => "America/Chicago",
    "973" => "America/New_York",
    "978" => "America/New_York",
    "979" => "America/Chicago",
    "980" => "America/New_York",
    "984" => "America/New_York",
    "985" => "America/Chicago",
    "989" => "America/New_York"
  }

  @doc "Returns a valid IANA timezone string."
  def from_phone(nil), do: @default
  def from_phone(""), do: @default

  def from_phone(phone) when is_binary(phone) do
    digits = phone |> String.replace(~r/\D/, "")

    area =
      cond do
        String.length(digits) == 11 and String.starts_with?(digits, "1") ->
          String.slice(digits, 1, 3)

        String.length(digits) == 10 ->
          String.slice(digits, 0, 3)

        true ->
          nil
      end

    tz =
      case area do
        nil -> @default
        a -> Map.get(@area_to_tz, a, regional_fallback(a))
      end

    validate_tz(tz)
  end

  @doc "Best-effort timezone from a Plug conn remote IP (GeoLite not required — US state heuristics)."
  def from_conn(%Plug.Conn{remote_ip: {a, b, c, d}}) do
    from_ip_tuple({a, b, c, d})
  end

  def from_conn(_), do: @default

  defp from_ip_tuple({127, 0, 0, _}), do: @default
  defp from_ip_tuple({10, _, _, _}), do: @default
  defp from_ip_tuple({192, 168, _, _}), do: @default

  defp from_ip_tuple({a, _, _, _}) when a in 3..63, do: "America/Los_Angeles"
  defp from_ip_tuple({a, _, _, _}) when a in 64..99, do: "America/Denver"
  defp from_ip_tuple({a, _, _, _}) when a in 100..126, do: "America/Chicago"
  defp from_ip_tuple(_), do: @default

  defp regional_fallback(<<first::binary-size(1), _::binary>>) do
    case first do
      "2" -> "America/New_York"
      "3" -> "America/New_York"
      "4" -> "America/New_York"
      "5" -> "America/Chicago"
      "6" -> "America/Chicago"
      "7" -> "America/Chicago"
      "8" -> "America/Denver"
      "9" -> "America/Los_Angeles"
      _ -> @default
    end
  end

  defp regional_fallback(_), do: @default

  defp validate_tz(tz) do
    case DateTime.now(tz) do
      {:ok, _} -> tz
      _ -> @default
    end
  end
end
