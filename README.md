# SvgSanitizer

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
    {:svg_sanitizer, "~> 0.1"}
  ]
end
```

Precompiled artifacts are published to GitHub releases for these targets;
`mix deps.get` downloads the right one — no Rust toolchain required:

- `aarch64-unknown-linux-gnu`
- `x86_64-unknown-linux-gnu`

**OTP 26+ required** (NIF 2.17). Earlier NIF versions will be added on demand.

**macOS users:** v0.1 doesn't ship precompiled macOS artifacts (the
`rustler-precompiled-action` mishandles `cross` on Apple Silicon; tracked
for v0.2). Build from source by setting `SVG_SANITIZER_BUILD=1`; you'll need
`cargo` installed.

## Usage

```elixir
case SvgSanitizer.sanitize(user_uploaded_svg) do
  {:ok, clean} ->
    store_asset(clean)

  {:error, reason} ->
    # reason is one of:
    #   :invalid_input    — input wasn't a binary
    #   :input_too_large  — over 5 MB; rejected without parsing
    #   :parse_error      — svg-hush rejected as malformed
    #   :panic            — Rust layer panicked (caught, BEAM safe)
    #   :alloc_failed     — out of memory while building output
    Logger.warning("svg sanitize failed: #{reason}")
    reject_upload(reason)
end
```

Always handle `{:error, _}`. SVG input from users *will* hit one of those
branches eventually; pattern-matching only on `{:ok, _}` is a `MatchError`
waiting to happen.

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
