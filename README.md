# SvgHush

Vetted SVG sanitizer for Elixir. Thin precompiled NIF wrapping Cloudflare's
[`svg-hush`](https://crates.io/crates/svg-hush) Rust crate, so applications
can accept user-uploaded SVG without authoring their own allowlist scrubber
— `<script>`, event handlers, foreign objects, external references, and
javascript:/data: URL vectors are stripped, raster image data URLs (PNG /
JPEG / GIF / WebP) are preserved so sanitized SVGs stay self-contained.

The NIF runs on a dirty CPU scheduler and converts Rust panics into
`{:error, term}` rather than crashing the BEAM node.

## Installation

```elixir
def deps do
  [
    {:svg_hush, "~> 0.1"}
  ]
end
```

Precompiled artifacts are published to GitHub releases for these targets;
`mix deps.get` downloads the right one — no Rust toolchain required:

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `aarch64-unknown-linux-gnu`
- `x86_64-unknown-linux-gnu`

Set `SVG_HUSH_BUILD=1` to force a local source build (requires `cargo`).

## Usage

```elixir
{:ok, clean} = SvgHush.sanitize(user_uploaded_svg)
```

Returns `{:ok, binary}` on success or `{:error, reason}` if `svg-hush`
rejects the input.

## Why a separate package

Elixir has no purpose-built SVG sanitizer; `html_sanitize_ex` is HTML-only
and pointing it at SVG amounts to hand-rolling an allowlist (which is what
makes SVG sanitization dangerous — the [TYPO3 PSA-2025-001
advisory](https://typo3.org/security/advisory/typo3-psa-2025-001) traces a
real-world bypass to exactly that). `svg-hush` is Cloudflare-maintained,
allowlist-based, and security-focused; this package is the thin glue that
makes it available to Phoenix / Plug / LiveView applications.

## License

Apache-2.0 — matches the upstream `svg-hush` crate.
