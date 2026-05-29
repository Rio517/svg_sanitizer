# Releasing `svg_sanitizer` to Hex.pm

Playbook for cutting and publishing a release. Optimized for someone who hasn't shipped a `rustler_precompiled` NIF package before — every step has a rationale and a verifiable check.

> **Audience:** package maintainer (or coding agent) bumping the version. Read top-to-bottom on first pass; later releases can skim the **Quick reference** at the bottom.

---

## Distribution model

`svg_sanitizer` is a Rust NIF wrapping Cloudflare's `svg-hush` crate, distributed via [`rustler_precompiled`](https://hexdocs.pm/rustler_precompiled):

- **Primary path (99% of consumers):** the BEAM downloads a precompiled `.so` from this repo's GitHub Release at first compile. No Rust toolchain on the consumer side.
- **Source fallback:** `SVG_SANITIZER_BUILD=1 mix compile` forces a local Rust build. Used by maintainers (no precompiled NIF for their platform) and by Hex when running `mix hex.publish` to validate the build manifest.

The release process therefore has **two artifact pipelines** that must agree:

1. **GitHub Release** — holds the precompiled `.so.tar.gz` files for each supported (NIF version × OS × arch) tuple. Built by `.github/workflows/release.yml` on tag push.
2. **Hex.pm package** — holds the source tarball + the `checksum-Elixir.SvgSanitizer.Native.exs` file that pins the SHA256 of every precompiled `.so` so consumers can verify what they download against what we shipped.

If these diverge (different commits, different checksums), consumers either fail to download or fail to verify. Keep them aligned.

---

## Authoritative references

Before deviating from this playbook, re-read these:

- [`rustler_precompiled` precompilation guide](https://rustler-precompiled.hexdocs.pm/precompilation_guide.html) — the canonical spec for `files:` glob, checksum handling, and force-build convention.
- [Hex publish docs](https://hex.pm/docs/publish) — the 1-hour grace window and `--revert` mechanics.
- [Rust blog: Change in Guidance on Committing Lockfiles (2023)](https://blog.rust-lang.org/2023/08/29/committing-lockfiles/) — current Rust-team stance on `Cargo.lock` ("do what's best for the project").

---

## Decisions encoded in this repo

These match the precompilation guide unless noted. Don't change them without re-reading the rationale.

| Concern | Decision | Rationale |
|---|---|---|
| `files:` manifest in `mix.exs` | Explicit list: `lib`, `native/svg_sanitizer_nif/src`, `native/svg_sanitizer_nif/Cargo.toml`, `native/svg_sanitizer_nif/Cargo.lock`, `checksum-*.exs`, `mix.exs`, `README.md`, `LICENSE`, `CHANGELOG.md` | Equivalent to the guide's `native/my_nif/Cargo*` glob, but explicit makes it obvious that `Cargo.lock` is intentional. |
| `Cargo.lock` committed to git | Yes (`native/svg_sanitizer_nif/Cargo.lock`) | Locks transitive crate versions so source-fallback users get reproducible builds. Required on disk when running `mix hex.publish` because the `files:` manifest references it — building from a tree without it aborts with `Missing files`. |
| `checksum-Elixir.SvgSanitizer.Native.exs` in git | Currently committed; **the guide says "you don't need to track the checksum file in your version control system (git or other)"**. Acceptable deviation — the file gets regenerated per release anyway. To bring into strict compliance: `git rm` it, add `checksum-*.exs` to `.gitignore`. The file still must exist on disk at `mix hex.publish` time (the `files:` glob ships it in the Hex tarball). | Deviation is cosmetic. Either is correct. |
| Force-build env var | `SVG_SANITIZER_BUILD` (set to `1` or `true`) | Matches the guide's `<APP_NAME>_BUILD` convention. |
| Target platforms (v0.1.x) | Linux only: `nif-2.17-{aarch64,x86_64}-unknown-linux-gnu` | macOS precompilation blocked by `rustler-precompiled-action@v1.1.5` unconditionally installing `cross` (fails on Apple Silicon, queues forever on `macos-13` Intel). Revisit in v0.2.x. Mac dev users force-build locally. |
| NIF version range | NIF 2.17 only (OTP 27+) | Scoped narrow in v0.1 to side-step a `rustler` feature-flag conflict. Widen in a future bump if needed. |

---

## Release procedure

### 0. Preconditions

- [ ] Logged in to Hex.pm: `mix hex.user whoami` → should print your username (currently `rio517`).
- [ ] Hex API key + write permission on the package (first publish creates ownership; subsequent publishes need it).
- [ ] 2FA configured on Hex.pm. **Publishing prompts for a TOTP code — this step is interactive-shell only. Agents cannot complete it.**
- [ ] GitHub auth: `gh auth status` clean for `Rio517/svg_sanitizer`.
- [ ] Working tree clean: `git -C /Users/marioflores/code/svg_hush status`.
- [ ] `cargo` available locally if you need to regenerate `Cargo.lock`: `which cargo`.

### 1. Bump the version

Edit `mix.exs` `@version`, `CHANGELOG.md`. Commit:

```
git -C /Users/marioflores/code/svg_hush add mix.exs CHANGELOG.md
git -C /Users/marioflores/code/svg_hush commit -m "release: vX.Y.Z"
```

If Rust deps in `native/svg_sanitizer_nif/Cargo.toml` moved, regenerate the lockfile:

```
cargo generate-lockfile --manifest-path /Users/marioflores/code/svg_hush/native/svg_sanitizer_nif/Cargo.toml
```

Commit `Cargo.lock` with the version bump or as a separate `chore:` commit.

### 2. Tag and push

```
git -C /Users/marioflores/code/svg_hush tag vX.Y.Z
git -C /Users/marioflores/code/svg_hush push origin main
git -C /Users/marioflores/code/svg_hush push origin vX.Y.Z
```

Pushing the tag fires `.github/workflows/release.yml`, which builds the precompiled NIFs for every (NIF version × target) tuple in the matrix and uploads them to the GitHub Release. Watch:

```
gh run watch --repo Rio517/svg_sanitizer --exit-status
```

### 3. Verify GitHub Release assets

```
gh release view vX.Y.Z --repo Rio517/svg_sanitizer --json assets --jq '.assets[].name'
```

Expect one `libsvg_sanitizer_nif-vX.Y.Z-nif-<ver>-<triple>.so.tar.gz` per supported tuple. For v0.1.x that's exactly two:

- `…-nif-2.17-aarch64-unknown-linux-gnu.so.tar.gz`
- `…-nif-2.17-x86_64-unknown-linux-gnu.so.tar.gz`

If a tuple is missing, the consumer's build for that platform will fail. Re-trigger the workflow or expand the matrix; don't publish to Hex until this is complete.

### 4. Generate the checksum file

After every release asset exists on the GitHub Release:

```
mix rustler_precompiled.download Elixir.SvgSanitizer.Native --all --print
```

This downloads every `.tar.gz` from the GitHub Release, computes SHA256, and writes `checksum-Elixir.SvgSanitizer.Native.exs`. `--all` includes every NIF/triple in the precompiled-targets matrix. `--print` echoes to stdout so you can sanity-check before committing.

If the checksum file is in git (current state — see deviation note above), commit it:

```
git -C /Users/marioflores/code/svg_hush add checksum-Elixir.SvgSanitizer.Native.exs
git -C /Users/marioflores/code/svg_hush commit -m "chore: checksum file for vX.Y.Z"
git -C /Users/marioflores/code/svg_hush push origin main
```

### 5. Dry-run the Hex build

```
SVG_SANITIZER_BUILD=1 mix hex.build
```

`SVG_SANITIZER_BUILD=1` forces a local Rust compile to validate `Cargo.lock` and `Cargo.toml` aren't broken. Confirms:

- All files in the `files:` manifest exist on disk (notably `Cargo.lock` and the checksum file).
- The package name, version, license, and description match expectations.

Expect output ending with `Saved to svg_sanitizer-X.Y.Z.tar`. Delete the tarball — it's not committed:

```
rm /Users/marioflores/code/svg_hush/svg_sanitizer-X.Y.Z.tar
```

### 6. Publish to Hex.pm (interactive, 2FA-gated)

**This step requires an interactive shell.** Agents must hand off here:

```
cd /Users/marioflores/code/svg_hush
SVG_SANITIZER_BUILD=1 mix hex.publish --yes
```

`SVG_SANITIZER_BUILD=1` is **required** on macOS — `RustlerPrecompiled`
verifies the host has a matching precompiled artifact before building
the tarball, and v0.1.x ships Linux-only artifacts. Without the env
var you get `precompiled NIF is not available for this target:
"aarch64-apple-darwin"` and the build aborts.

`--yes` skips the y/n confirmation but does **not** skip the TOTP prompt. Enter the 6-digit code from your authenticator app.

Wait for `Package published to https://hex.pm/packages/svg_sanitizer/X.Y.Z`.

### 7. Post-publish verification (within the 1-hour grace window)

> **From the [Hex publish docs](https://hex.pm/docs/publish):** *"If there are any issues, you can publish the package again for up to one hour after first publication."*

In the first hour after publish:

- [ ] Visit `https://hex.pm/packages/svg_sanitizer/X.Y.Z` — confirm version, files list, license, description.
- [ ] Visit `https://hexdocs.pm/svg_sanitizer/X.Y.Z` — confirm doc rendering (README + CHANGELOG + module docs).
- [ ] In a scratch project: `{:svg_sanitizer, "~> X.Y"}` → `mix deps.get` → `mix deps.compile` should pull the precompiled NIF and sanitize a sample SVG.
- [ ] In the GlideDeck platform repo: bump the dep version, run `cd platform && mix precommit`, confirm asset Phase 2 paths still work.

If something is wrong: `mix hex.publish --revert X.Y.Z` within the hour, fix, republish.

**After 1 hour, the version is immutable.** Fixes require a new version (`X.Y.(Z+1)`).

---

## Common failure modes

| Symptom | Cause | Fix |
|---|---|---|
| `mix hex.build` aborts with `Missing files: native/svg_sanitizer_nif/Cargo.lock` | Lockfile listed in `files:` but never generated, or gitignored and not on disk | `cargo generate-lockfile --manifest-path native/svg_sanitizer_nif/Cargo.toml`, commit it. Make sure `.gitignore` doesn't exclude it. |
| `mix hex.publish` errors on TOTP | Agent attempted to run it in a non-interactive shell | Hand off to a human in an interactive terminal. |
| Consumer's `mix deps.compile` fails with `no precompiled NIF available for <triple>` | GitHub Release missing an artifact for that target | Re-run the release workflow, or add the triple to the matrix in `lib/svg_sanitizer/native.ex` if it's new. |
| Checksum verification fails on consumer side | Checksum file in the Hex tarball doesn't match what's on the GitHub Release (e.g., release was re-uploaded after `rustler_precompiled.download` ran) | Re-run step 4 with the current Release assets, republish (within the 1-hour grace) or bump patch version. |
| Hex tag commit and GitHub tag commit diverge | Hex tarball built from a local commit that wasn't pushed before tagging | Force-retag to the published commit: `git tag -f vX.Y.Z <published-commit>` then `git push --force origin vX.Y.Z`. .so artifacts on the GH Release identify by tag *name*, not commit, so they're unaffected — but only do this if no source changes happened between the two commits (otherwise consumers building from source see different code than the precompiled NIFs were built from). |

---

## Quick reference

```
# 0. Verify state
mix hex.user whoami
git -C /Users/marioflores/code/svg_hush status

# 1. Bump version in mix.exs + CHANGELOG.md, commit

# 2. Tag + push
git -C /Users/marioflores/code/svg_hush tag vX.Y.Z
git -C /Users/marioflores/code/svg_hush push origin main
git -C /Users/marioflores/code/svg_hush push origin vX.Y.Z

# 3. Wait for CI to publish NIFs
gh run watch --repo Rio517/svg_sanitizer --exit-status

# 4. Generate + commit checksum
mix rustler_precompiled.download Elixir.SvgSanitizer.Native --all --print
git -C /Users/marioflores/code/svg_hush add checksum-Elixir.SvgSanitizer.Native.exs
git -C /Users/marioflores/code/svg_hush commit -m "chore: checksum file for vX.Y.Z"
git -C /Users/marioflores/code/svg_hush push origin main

# 5. Dry-run, then publish (interactive shell + TOTP)
SVG_SANITIZER_BUILD=1 mix hex.build
SVG_SANITIZER_BUILD=1 mix hex.publish --yes

# 6. If broken within 1 hour: mix hex.publish --revert X.Y.Z
```
