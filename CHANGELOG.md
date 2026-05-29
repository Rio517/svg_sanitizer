# Changelog

## v0.1.0 (2026-05-28)

Initial release. Thin precompiled NIF wrapping Cloudflare's `svg-hush`
Rust crate (v0.9).

- `SvgSanitizer.sanitize/1` strips `<script>`, event handlers, foreign
  objects, external references, and javascript:/data: URL vectors.
  Embedded raster data URLs (PNG/JPEG/GIF/WebP) are preserved.
- Returns `{:ok, binary}` or `{:error, reason}` where `reason` is one of
  `:invalid_input | :input_too_large | :parse_error | :panic | :alloc_failed`
  — all atoms, no internal-state leaks. See `t:SvgSanitizer.reason/0`.
- Runs on a DirtyCpu scheduler.
- Rust panics are caught and surfaced as `{:error, :panic}` rather than
  bringing down the BEAM node. (Stack overflow on the dirty NIF thread is
  not catchable — svg-hush's iterative parser keeps stack usage bounded.)
- Inputs over 5 MB are rejected with `{:error, :input_too_large}` at both
  the Elixir wrapper and the NIF boundary (defense in depth).
- Non-binary input returns `{:error, :invalid_input}` instead of raising.
- Precompiled artifacts published for `aarch64-unknown-linux-gnu` and
  `x86_64-unknown-linux-gnu`. macOS targets deferred (the
  `rustler-precompiled-action` mishandles `cross` on Apple Silicon);
  Mac users build from source with `SVG_SANITIZER_BUILD=1`.
- Requires OTP 26+ (NIF 2.17); earlier NIF versions added on demand.
