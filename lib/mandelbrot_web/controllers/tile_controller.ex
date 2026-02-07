defmodule MandelbrotWeb.TileController do
  use MandelbrotWeb, :controller

  @tile_size 256

  def show(conn, %{"z" => z_str, "x" => x_str, "y" => y_str}) do
    z = String.to_integer(z_str)
    x = String.to_integer(x_str)
    y = String.to_integer(y_str)

    max_coord = Bitwise.bsl(1, z) - 1

    if x < 0 or y < 0 or x > max_coord or y > max_coord or z < 0 or z > 45 do
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

  # Map global pixel coordinates to the complex plane and compute Mandelbrot.
  # At zoom 0 the full world covers real [-2.5, 1.0] x imag [-1.75, 1.75].
  defp pixel_color(z, x, y) do
    world_size = @tile_size * Bitwise.bsl(1, z)
    cr = -2.5 + x / world_size * 3.5
    ci = -1.75 + y / world_size * 3.5

    max_iter = 100 + z * 50
    {n, zr, zi} = mandelbrot_iterate(cr, ci, 0.0, 0.0, 0, max_iter)

    if n == max_iter do
      <<0, 0, 0>>
    else
      # Smooth iteration count for continuous coloring
      log_zn = :math.log(zr * zr + zi * zi) / 2.0
      smooth = n + 1 - :math.log2(log_zn / :math.log(2))
      t = smooth * 0.05

      r = trunc((0.5 + 0.5 * :math.cos(6.2832 * (t + 0.00))) * 255)
      g = trunc((0.5 + 0.5 * :math.cos(6.2832 * (t + 0.15))) * 255)
      b = trunc((0.5 + 0.5 * :math.cos(6.2832 * (t + 0.35))) * 255)
      <<r, g, b>>
    end
  end

  defp mandelbrot_iterate(_cr, _ci, zr, zi, n, max) when n >= max, do: {n, zr, zi}

  defp mandelbrot_iterate(cr, ci, zr, zi, n, max) do
    zr2 = zr * zr
    zi2 = zi * zi

    if zr2 + zi2 > 4.0 do
      {n, zr, zi}
    else
      mandelbrot_iterate(cr, ci, zr2 - zi2 + cr, 2.0 * zr * zi + ci, n + 1, max)
    end
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
