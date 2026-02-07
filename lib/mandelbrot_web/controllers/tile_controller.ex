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
      png = generate_tile(z, x, y)

      conn
      |> put_resp_content_type("image/png")
      |> put_resp_header("cache-control", "public, max-age=3600")
      |> send_resp(200, png)
    end
  end

  defp generate_tile(z, tile_x, tile_y) do
    pixels =
      for py <- 0..(@tile_size - 1), px <- 0..(@tile_size - 1), into: <<>> do
        pixel_color(z, tile_x * @tile_size + px, tile_y * @tile_size + py)
      end

    encode_png(pixels)
  end

  # Returns an {r, g, b} binary for the pixel at global coordinates (x, y)
  # at zoom level z. Replace this with your own logic.
  defp pixel_color(z, x, y) do
    # Placeholder: simple gradient based on position
    world_size = @tile_size * Bitwise.bsl(1, z)
    r = trunc(x / world_size * 255)
    g = trunc(y / world_size * 255)
    b = rem(z * 40, 256)
    <<r, g, b>>
  end

  # Encodes raw RGB pixel data as a PNG.
  # Pixels must be @tile_size * @tile_size * 3 bytes (row-major, RGB).
  defp encode_png(pixels) do
    # Build filtered scanlines: each row gets a 0 (None filter) prefix
    scanlines =
      for row <- 0..(@tile_size - 1), into: <<>> do
        offset = row * @tile_size * 3
        <<0, binary_part(pixels, offset, @tile_size * 3)::binary>>
      end

    compressed = :zlib.compress(scanlines)

    <<
      # PNG signature
      137, 80, 78, 71, 13, 10, 26, 10,
      # IHDR chunk
      png_chunk("IHDR", <<
        @tile_size::32,
        @tile_size::32,
        8,  # bit depth
        2,  # color type: RGB
        0,  # compression method
        0,  # filter method
        0   # interlace method
      >>)::binary,
      # IDAT chunk
      png_chunk("IDAT", compressed)::binary,
      # IEND chunk
      png_chunk("IEND", <<>>)::binary
    >>
  end

  defp png_chunk(type, data) do
    type_bin = type
    crc = :erlang.crc32(<<type_bin::binary, data::binary>>)
    <<byte_size(data)::32, type_bin::binary, data::binary, crc::32>>
  end
end
