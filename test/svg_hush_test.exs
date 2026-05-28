defmodule SvgHushTest do
  use ExUnit.Case, async: true

  # Each malicious SVG is paired with a `forbidden` pattern that MUST NOT appear
  # in the sanitized output. Strings, not regexes, kept blunt on purpose — if
  # any sanitization regression lets one through, the assertion is unambiguous.

  @cases [
    {
      "script element",
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>|,
      "alert"
    },
    {
      "onload attribute on root",
      ~S|<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"></svg>|,
      "alert"
    },
    {
      "onload on inner element",
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><g onload="alert(1)"/></svg>|,
      "alert"
    },
    {
      "mixed-case event handler (TYPO3 PSA-2025-001 pattern)",
      ~S|<svg xmlns="http://www.w3.org/2000/svg" OnLoAd="alert(1)"></svg>|,
      "alert"
    },
    {
      "javascript: href",
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><a href="javascript:alert(1)"><text>x</text></a></svg>|,
      "javascript:"
    },
    {
      "xlink:href javascript:",
      ~S|<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><a xlink:href="javascript:alert(1)"><text>x</text></a></svg>|,
      "javascript:"
    },
    {
      "mixed-case xlink:HrEf",
      ~S|<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><a xlink:HrEf="javascript:alert(1)"><text>x</text></a></svg>|,
      "javascript:"
    },
    {
      "foreignObject with HTML script",
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><body xmlns="http://www.w3.org/1999/xhtml"><script>alert(1)</script></body></foreignObject></svg>|,
      "alert"
    },
    {
      "use element with external reference",
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><use href="https://evil.example.com/x.svg#payload"/></svg>|,
      "evil.example.com"
    },
    {
      "data:text/html embedded in href",
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><a href="data:text/html,<script>alert(1)</script>"><text>x</text></a></svg>|,
      "text/html"
    },
    {
      "iframe inside foreignObject",
      ~S|<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><iframe xmlns="http://www.w3.org/1999/xhtml" src="javascript:alert(1)"/></foreignObject></svg>|,
      "javascript:"
    }
  ]

  for {name, input, forbidden} <- @cases do
    test "neutralizes: #{name}" do
      # The contract is "dangerous content never makes it through." Either
      # stripping (sanitized output without the forbidden token) or outright
      # rejection of malformed input satisfies that — both count as safe.
      case SvgHush.sanitize(unquote(input)) do
        {:ok, output} ->
          output_str = IO.iodata_to_binary(output)

          refute String.contains?(output_str, unquote(forbidden)),
                 "expected #{inspect(unquote(forbidden))} to be stripped, got: #{output_str}"

        {:error, _reason} ->
          :ok
      end
    end
  end

  test "passes through a benign svg" do
    svg = ~S|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="black"/></svg>|

    assert {:ok, output} = SvgHush.sanitize(svg)
    out_str = IO.iodata_to_binary(output)
    assert String.contains?(out_str, "rect")
    assert String.contains?(out_str, "black")
  end

  test "preserves an embedded raster data: URL (image/png)" do
    png_data_url =
      "data:image/png;base64," <>
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

    svg =
      ~s|<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><image href="#{png_data_url}" width="1" height="1"/></svg>|

    assert {:ok, output} = SvgHush.sanitize(svg)
    out_str = IO.iodata_to_binary(output)
    assert String.contains?(out_str, "data:image/png")
  end

  test "returns a tagged tuple for non-XML garbage rather than crashing" do
    result = SvgHush.sanitize(<<0, 1, 2, 3, 0xFF>>)
    assert match?({:ok, _}, result) or match?({:error, _}, result)
  end
end
