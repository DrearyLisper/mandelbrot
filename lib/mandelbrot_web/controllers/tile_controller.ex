defmodule MandelbrotWeb.TileController do
  use MandelbrotWeb, :controller

  @tile_size 256

  def show(conn, %{"z" => z_str, "x" => x_str, "y" => y_str}) do
    z = String.to_integer(z_str)
    x = String.to_integer(x_str)
    y = String.to_integer(y_str)

    max_coord = Bitwise.bsl(1, z) - 1

    if x < 0 or y < 0 or x > max_coord or y > max_coord or z < 0 or z > 15 do
      send_resp(conn, 404, "Tile out of range")
    else
      svg = generate_debug_tile(z, x, y)

      conn
      |> put_resp_content_type("image/svg+xml")
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> send_resp(200, svg)
    end
  end

  defp generate_debug_tile(z, x, y) do
    hue = rem(z * 47 + x * 13 + y * 29, 360)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@tile_size}" height="#{@tile_size}">
      <rect width="#{@tile_size}" height="#{@tile_size}" fill="hsl(#{hue}, 30%, 85%)" />
      <rect x="0" y="0" width="#{@tile_size}" height="#{@tile_size}"
            fill="none" stroke="hsl(#{hue}, 30%, 55%)" stroke-width="1" />
      <line x1="0" y1="0" x2="#{@tile_size}" y2="#{@tile_size}"
            stroke="hsl(#{hue}, 20%, 75%)" stroke-width="0.5" />
      <line x1="#{@tile_size}" y1="0" x2="0" y2="#{@tile_size}"
            stroke="hsl(#{hue}, 20%, 75%)" stroke-width="0.5" />
      <text x="128" y="105" text-anchor="middle" font-family="monospace" font-size="22" fill="#444">
        z=#{z}
      </text>
      <text x="128" y="135" text-anchor="middle" font-family="monospace" font-size="18" fill="#555">
        x=#{x} y=#{y}
      </text>
    </svg>
    """
  end
end
