defmodule MandelbrotWeb.MapLive do
  use MandelbrotWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id="map" phx-hook="MapHook" style="width: 100vw; height: 100vh; overflow: hidden; position: relative; cursor: grab;">
    </div>
    """
  end
end
