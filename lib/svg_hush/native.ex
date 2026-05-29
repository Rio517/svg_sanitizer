defmodule SvgHush.Native do
  @moduledoc false

  mix_config = Mix.Project.config()
  version = mix_config[:version]
  github_url = mix_config[:source_url]

  use RustlerPrecompiled,
    otp_app: :svg_hush,
    crate: "svg_hush_nif",
    base_url: "#{github_url}/releases/download/v#{version}",
    force_build: System.get_env("SVG_HUSH_BUILD") in ["1", "true"],
    # v0.1 ships precompiled artifacts for Linux only — the prod deploy target.
    # macOS targets are deferred: rustler-precompiled-action v1.1.5 unconditionally
    # installs the `cross` tool, which won't run on Apple Silicon and queues
    # forever on macos-13 Intel. Mac dev users set SVG_HUSH_BUILD=1 (requires
    # cargo). Adding macOS targets back will revisit the action.
    targets: ~w(
      aarch64-unknown-linux-gnu
      x86_64-unknown-linux-gnu
    ),
    version: version,
    nif_versions: ["2.17"]

  # Implementation lives in native/svg_hush_nif (Rust). The function below
  # is replaced at load time by the NIF; this stub exists so the module
  # compiles even when no precompiled artifact is available.
  def sanitize(_svg), do: :erlang.nif_error(:nif_not_loaded)
end
