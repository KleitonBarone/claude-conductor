defmodule ClaudeConductorWeb.PageControllerTest do
  use ClaudeConductorWeb.ConnCase

  test "GET / renders project list", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Projects"
  end
end
