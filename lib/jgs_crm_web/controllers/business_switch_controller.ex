defmodule JgsCrmWeb.BusinessSwitchController do
  use JgsCrmWeb, :controller

  alias JgsCrm.Businesses

  def update(conn, %{"business_id" => id}) do
    user = conn.assigns.current_scope.user
    bid = String.to_integer(id)

    if Businesses.member?(user, bid) do
      conn
      |> put_session("current_business_id", Integer.to_string(bid))
      |> redirect(to: ~p"/")
    else
      conn
      |> put_flash(:error, "You are not a member of that business.")
      |> redirect(to: ~p"/businesses")
    end
  end
end
