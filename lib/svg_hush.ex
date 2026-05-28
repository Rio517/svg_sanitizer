defmodule SvgHush do
  @moduledoc """
  Vetted SVG sanitizer for Elixir.

  Wraps the Rust [`svg-hush`](https://crates.io/crates/svg-hush) crate from
  Cloudflare in a precompiled NIF. Use it to neutralize user-uploaded SVG
  before storing or serving — strips `<script>`, event handlers, foreign
  objects, external references, and other XSS vectors.

  ## Example

      iex> {:ok, _clean} = SvgHush.sanitize("<svg xmlns='http://www.w3.org/2000/svg'/>")

  Embedded raster data URLs (PNG/JPEG/GIF/WebP) are preserved so sanitized
  SVGs remain self-contained; all other URL schemes (including javascript:
  and arbitrary data: types) are stripped.

  The NIF runs on a dirty CPU scheduler so a slow sanitization does not
  block normal schedulers, and surfaces parse/IO errors as `{:error, term}`
  rather than crashing the VM.
  """

  alias SvgHush.Native

  @doc """
  Returns a sanitized copy of the given SVG.

  Accepts the SVG as a binary. Returns `{:ok, sanitized_binary}` on success
  or `{:error, reason}` if `svg-hush` rejects the input as unparseable.
  """
  @spec sanitize(binary()) :: {:ok, binary()} | {:error, term()}
  def sanitize(svg) when is_binary(svg) do
    Native.sanitize(svg)
  end
end
