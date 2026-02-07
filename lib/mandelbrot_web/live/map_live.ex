defmodule MandelbrotWeb.MapLive do
  use MandelbrotWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id="map" phx-hook="MapHook" style="width: 100vw; height: 100vh; overflow: hidden; position: relative; cursor: grab;">
      <div id="map-status" style="position:absolute;bottom:8px;left:8px;z-index:10;background:rgba(0,0,0,0.6);color:#fff;font-family:monospace;font-size:12px;padding:4px 8px;border-radius:4px;pointer-events:none;">
      </div>
    </div>
    """
  end
end
