defmodule MandelbrotWeb.PageController do
  use MandelbrotWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
