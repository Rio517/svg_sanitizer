defmodule SvgHush.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Rio517/svg_hush"

  def project do
    [
      app: :svg_hush,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "svg_hush",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:rustler_precompiled, "~> 0.9"},
      {:rustler, "~> 0.38.0", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Vetted SVG sanitizer for Elixir. Wraps the Rust `svg-hush` crate
    (Cloudflare) in a precompiled NIF, so applications can accept
    user-uploaded SVGs without writing their own allowlist-based scrubber.
    """
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(
        lib
        native/svg_hush_nif/src
        native/svg_hush_nif/Cargo.toml
        native/svg_hush_nif/Cargo.lock
        native/svg_hush_nif/.cargo
        checksum-*.exs
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end
end
