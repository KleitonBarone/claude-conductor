defmodule ClaudeConductorWeb.ErrorJSONTest do
  use ClaudeConductorWeb.ConnCase, async: true

  test "renders 404" do
    assert ClaudeConductorWeb.ErrorJSON.render("404.json", %{}) == %{
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500" do
    assert ClaudeConductorWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
