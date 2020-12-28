defmodule LoPriceWeb.PageController do
  use LoPriceWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
