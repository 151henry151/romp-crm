defmodule RompCrmWeb.PageController do
  use RompCrmWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
