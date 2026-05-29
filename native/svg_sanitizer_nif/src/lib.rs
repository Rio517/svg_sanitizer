// svg_sanitizer NIF — wraps Cloudflare's `svg-hush` Rust crate.
//
// Public function: sanitize(binary) -> {:ok, binary} | {:error, term}.
//
// Runs on a DirtyCpu scheduler because sanitization is CPU-bound and may
// take longer than the BEAM's 1ms scheduler budget on large SVGs.
// catch_unwind catches heap panics (unwrap failures, explicit panic!) and
// surfaces them as {:error, :panic}. Stack overflow on a dirty NIF OS
// thread aborts the process and is NOT catchable — the upstream svg-hush
// filter is iterative (no recursion) so stack growth is bounded in
// practice, but we don't enforce that limit at this layer.

use rustler::{Atom, Binary, Encoder, Env, OwnedBinary, Term};

// Defense in depth: the Elixir wrapper already rejects oversize input,
// but we re-check at the NIF boundary so any caller that bypasses
// SvgSanitizer.sanitize/1 (e.g. talks to Native directly) still gets a
// bounded allocation. Keep this number in sync with SvgSanitizer's
// @max_bytes — 5 MB.
const MAX_INPUT_BYTES: usize = 5 * 1024 * 1024;

mod atoms {
    rustler::atoms! {
        alloc_failed,
        input_too_large,
        panic,
        parse_error,
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn sanitize<'a>(env: Env<'a>, svg: Binary<'a>) -> Term<'a> {
    let input: &[u8] = svg.as_slice();

    if input.len() > MAX_INPUT_BYTES {
        return error(env, atoms::input_too_large());
    }

    let mut filter = svg_hush::Filter::new();
    // Allow embedded raster image data: URLs (PNG/JPEG/GIF/WebP) so sanitized
    // SVGs can stay self-contained; reject every other URL scheme, including
    // javascript: and arbitrary data: types.
    filter.set_data_url_filter(svg_hush::data_url_filter::allow_standard_images);

    let mut out: Vec<u8> = Vec::with_capacity(input.len());
    let mut reader: &[u8] = input;

    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        filter.filter(&mut reader, &mut out)
    }));

    match result {
        Ok(Ok(())) => {
            let mut bin = match OwnedBinary::new(out.len()) {
                Some(b) => b,
                None => return error(env, atoms::alloc_failed()),
            };
            bin.as_mut_slice().copy_from_slice(&out);
            (rustler::types::atom::ok(), Binary::from_owned(bin, env)).encode(env)
        }
        // Classify svg-hush's parse error to an atom so we don't leak internal
        // formatter state (byte offsets, token names) into the public reason.
        // svg-hush's Display impl is useful for humans but not a stable API.
        Ok(Err(_)) => error(env, atoms::parse_error()),
        Err(_) => error(env, atoms::panic()),
    }
}

fn error<'a>(env: Env<'a>, reason: Atom) -> Term<'a> {
    (rustler::types::atom::error(), reason).encode(env)
}

rustler::init!("Elixir.SvgSanitizer.Native");
