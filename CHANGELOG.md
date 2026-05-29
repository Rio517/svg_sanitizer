# Changelog

## v0.1.0 (2026-05-28)

Initial release. Thin precompiled NIF wrapping Cloudflare's `svg-hush`
Rust crate (v0.9).

- `SvgHush.sanitize/1` strips `<script>`, event handlers, foreign objects,
  external references, and javascript:/data: URL vectors. Embedded raster
  data URLs (PNG/JPEG/GIF/WebP) are preserved.
- Runs on a DirtyCpu scheduler.
- Rust panics are caught and surfaced as `{:error, term}` rather than
  bringing down the BEAM node.
- Precompiled artifacts published for `aarch64-unknown-linux-gnu` and
  `x86_64-unknown-linux-gnu`. macOS targets deferred (the
  `rustler-precompiled-action` mishandles `cross` on Apple Silicon);
  Mac users build from source with `SVG_HUSH_BUILD=1`.
- Requires OTP 27+ (NIF 2.17); earlier NIF versions added on demand.
