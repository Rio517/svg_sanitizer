defmodule SvgSanitizer do
  @moduledoc """
  Vetted SVG sanitizer for Elixir.

  Wraps the Rust [`svg-hush`](https://crates.io/crates/svg-hush) crate from
  Cloudflare in a precompiled NIF. Use it to neutralize user-uploaded SVG
  before storing or serving — strips `<script>`, event handlers, foreign
  objects, external references, and other XSS vectors.

  ## Example

      iex> {:ok, _clean} = SvgSanitizer.sanitize("<svg xmlns='http://www.w3.org/2000/svg'/>")

  Embedded raster data URLs (PNG/JPEG/GIF/WebP) are preserved so sanitized
  SVGs remain self-contained; all other URL schemes (including javascript:
  and arbitrary data: types) are stripped.

  The NIF runs on a dirty CPU scheduler so a slow sanitization does not
  block normal schedulers, and surfaces parse/IO errors as `{:error, atom}`
  rather than crashing the VM.
  """

  alias SvgSanitizer.Native

  @max_bytes 5 * 1024 * 1024

  @typedoc """
  Why sanitization didn't yield a clean binary. Always an atom — stable
  for pattern matching, doesn't leak internal parser state.

    * `:invalid_input`   — input wasn't a binary.
    * `:input_too_large` — input over #{@max_bytes} bytes; rejected without parsing.
    * `:parse_error`     — svg-hush rejected the input (malformed XML,
      unsupported encoding, etc.). Treat as "reject this upload".
    * `:panic`           — Rust layer panicked (caught at the NIF boundary,
      BEAM unaffected). Stack overflow is *not* caught and aborts the node;
      svg-hush's iterative parser keeps stack usage bounded in practice.
    * `:alloc_failed`    — out of memory while copying the sanitized output.
  """
  @type reason ::
          :invalid_input
          | :input_too_large
          | :parse_error
          | :panic
          | :alloc_failed

  @doc """
  Returns a sanitized copy of the given SVG.

  Accepts a binary up to #{@max_bytes} bytes. Returns `{:ok, sanitized_binary}`
  on success, `{:error, reason}` on rejection. See `t:reason/0` for the
  full set of error atoms.

  Always handle `{:error, _}`. Non-binary input, oversized input, malformed
  XML, and adversarial payloads all land there; pattern-matching only on
  `{:ok, _}` is a `MatchError` waiting to happen.
  """
  @spec sanitize(term()) :: {:ok, binary()} | {:error, reason()}
  def sanitize(svg) when is_binary(svg) and byte_size(svg) > @max_bytes do
    {:error, :input_too_large}
  end

  def sanitize(svg) when is_binary(svg) do
    Native.sanitize(svg)
  end

  def sanitize(_other) do
    {:error, :invalid_input}
  end
end
