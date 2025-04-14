defmodule Myapp18Web.PageController do
  use Myapp18Web, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
