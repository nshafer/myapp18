defmodule Myapp18Web.ErrorJSONTest do
  use Myapp18Web.ConnCase, async: true

  test "renders 404" do
    assert Myapp18Web.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert Myapp18Web.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
