// svg_sanitizer NIF — wraps Cloudflare's `svg-hush` Rust crate.
//
// Public function: sanitize(binary) -> {:ok, binary} | {:error, term}.
//
// Runs on a DirtyCpu scheduler because sanitization is CPU-bound and may
// take longer than the BEAM's 1ms scheduler budget on large SVGs.
// Wraps the filter call in catch_unwind so a Rust panic is surfaced as
// {:error, ...} rather than bringing down the BEAM node.

use rustler::{Binary, Encoder, Env, OwnedBinary, Term};

#[rustler::nif(schedule = "DirtyCpu")]
fn sanitize<'a>(env: Env<'a>, svg: Binary<'a>) -> Term<'a> {
    let input: &[u8] = svg.as_slice();

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
                None => {
                    return (
                        rustler::types::atom::error(),
                        "alloc_failed".to_string(),
                    )
                        .encode(env)
                }
            };
            bin.as_mut_slice().copy_from_slice(&out);
            (rustler::types::atom::ok(), Binary::from_owned(bin, env)).encode(env)
        }
        Ok(Err(e)) => (rustler::types::atom::error(), format!("{}", e)).encode(env),
        Err(_) => (rustler::types::atom::error(), "panic".to_string()).encode(env),
    }
}

rustler::init!("Elixir.SvgSanitizer.Native");
