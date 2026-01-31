defmodule ClaudeConductorWeb.PageController do
  use ClaudeConductorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
