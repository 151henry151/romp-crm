defmodule JgsCrmWeb.PageController do
  use JgsCrmWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
