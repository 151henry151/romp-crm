defmodule RompCrm.Scheduling.AppleCalendarSourceTest do
  use RompCrm.DataCase

  import RompCrm.AccountsFixtures

  alias RompCrm.Scheduling.AppleCalendarSource
  alias RompCrm.Scheduling.CalendarCredentials

  @range {~D[2026-06-15], ~D[2026-06-16]}
  @tz "America/New_York"

  describe "parse_freebusy_ics/1" do
    test "extracts FREEBUSY periods" do
      ics = """
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VFREEBUSY
      DTSTART:20260615T040000Z
      DTEND:20260617T040000Z
      FREEBUSY:20260615T140000Z/20260615T160000Z
      FREEBUSY;FBTYPE=BUSY:20260616T130000Z/20260616T133000Z
      END:VFREEBUSY
      END:VCALENDAR
      """

      assert AppleCalendarSource.parse_freebusy_ics(ics) == [
               %{start: ~U[2026-06-15 14:00:00Z], end: ~U[2026-06-15 16:00:00Z]},
               %{start: ~U[2026-06-16 13:00:00Z], end: ~U[2026-06-16 13:30:00Z]}
             ]
    end

    test "supports duration form and ignores FREE periods" do
      ics = """
      FREEBUSY;FBTYPE=FREE:20260615T100000Z/20260615T120000Z
      FREEBUSY:20260615T140000Z/PT2H
      """

      assert AppleCalendarSource.parse_freebusy_ics(ics) == [
               %{start: ~U[2026-06-15 14:00:00Z], end: ~U[2026-06-15 16:00:00Z]}
             ]
    end

    test "garbage yields empty list" do
      assert AppleCalendarSource.parse_freebusy_ics("nope") == []
    end
  end

  describe "parse_href/2" do
    test "extracts the principal href from PROPFIND XML" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <multistatus xmlns="DAV:">
        <response>
          <href>/</href>
          <propstat>
            <prop>
              <current-user-principal>
                <href>/123456789/principal/</href>
              </current-user-principal>
            </prop>
          </propstat>
        </response>
      </multistatus>
      """

      assert AppleCalendarSource.parse_href(xml, "current-user-principal") ==
               "/123456789/principal/"
    end

    test "extracts calendar-home-set href" do
      xml = """
      <multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
        <response>
          <propstat>
            <prop>
              <C:calendar-home-set>
                <href>https://p42-caldav.icloud.com:443/123456789/calendars/</href>
              </C:calendar-home-set>
            </prop>
          </propstat>
        </response>
      </multistatus>
      """

      assert AppleCalendarSource.parse_href(xml, "calendar-home-set") ==
               "https://p42-caldav.icloud.com:443/123456789/calendars/"
    end

    test "missing element yields nil" do
      assert AppleCalendarSource.parse_href("<x/>", "calendar-home-set") == nil
    end
  end

  describe "fetch_busy_blocks/3" do
    setup do
      prev = Application.get_env(:romp_crm, :calendar_http_options)
      Application.put_env(:romp_crm, :calendar_http_options, plug: {Req.Test, AppleCalendarSource})

      on_exit(fn -> Application.put_env(:romp_crm, :calendar_http_options, prev) end)

      user = user_fixture()

      {:ok, cred} =
        CalendarCredentials.connect(user.id, "apple", %{
          "apple_id" => "tech@icloud.com",
          "app_password" => "abcd-efgh-ijkl-mnop"
        })

      %{cred: cred}
    end

    test "walks principal discovery and parses the freebusy report", %{cred: cred} do
      Req.Test.stub(AppleCalendarSource, fn conn ->
        case {conn.method, conn.request_path} do
          {"PROPFIND", "/"} ->
            Plug.Conn.send_resp(conn, 207, """
            <multistatus xmlns="DAV:"><response><propstat><prop>
              <current-user-principal><href>/1234/principal/</href></current-user-principal>
            </prop></propstat></response></multistatus>
            """)

          {"PROPFIND", "/1234/principal/"} ->
            Plug.Conn.send_resp(conn, 207, """
            <multistatus xmlns="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><response><propstat><prop>
              <C:calendar-home-set><href>/1234/calendars/</href></C:calendar-home-set>
            </prop></propstat></response></multistatus>
            """)

          {"REPORT", "/1234/calendars/"} ->
            Plug.Conn.send_resp(conn, 200, """
            BEGIN:VCALENDAR
            BEGIN:VFREEBUSY
            FREEBUSY:20260615T140000Z/20260615T160000Z
            END:VFREEBUSY
            END:VCALENDAR
            """)
        end
      end)

      assert {:ok, blocks} = AppleCalendarSource.fetch_busy_blocks(cred, @range, @tz)
      assert blocks == [%{start: ~U[2026-06-15 14:00:00Z], end: ~U[2026-06-15 16:00:00Z]}]
      assert Repo.reload!(cred).status == "connected"
    end

    test "auth failure marks the credential errored", %{cred: cred} do
      Req.Test.stub(AppleCalendarSource, fn conn ->
        Plug.Conn.send_resp(conn, 401, "unauthorized")
      end)

      assert {:error, _} = AppleCalendarSource.fetch_busy_blocks(cred, @range, @tz)
      assert Repo.reload!(cred).status == "error"
    end
  end
end
