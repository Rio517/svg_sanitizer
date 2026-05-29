defmodule SvgSanitizerTest do
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
      case SvgSanitizer.sanitize(unquote(input)) do
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

    assert {:ok, output} = SvgSanitizer.sanitize(svg)
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

    assert {:ok, output} = SvgSanitizer.sanitize(svg)
    out_str = IO.iodata_to_binary(output)
    assert String.contains?(out_str, "data:image/png")
  end

  describe "rejection paths" do
    test "non-binary input → {:error, :invalid_input}" do
      for bad <- [nil, :svg, 42, %{}, [<<"svg">>], {1, 2}] do
        assert SvgSanitizer.sanitize(bad) == {:error, :invalid_input},
               "expected :invalid_input for #{inspect(bad)}"
      end
    end

    test "oversize binary → {:error, :input_too_large} without parsing" do
      # 5 MB + 1 byte — smallest payload past the byte_size > @max_bytes
      # gate. :binary.copy makes the intent ("generate a 5 MB+1 binary")
      # obvious vs. an inline `<< 0 :: size(...) >>` bit literal.
      payload = :binary.copy(<<0>>, 5 * 1024 * 1024 + 1)
      assert SvgSanitizer.sanitize(payload) == {:error, :input_too_large}
    end

    test "binary garbage that isn't XML → {:error, :parse_error}, never {:ok, _}" do
      # The pre-hardening test accepted {:ok, _} as a valid response for
      # binary garbage. That left room for a silent sanitization bypass on
      # non-SVG bytes: producing :ok with empty/partial output. Now we
      # assert the error path explicitly.
      assert {:error, :parse_error} = SvgSanitizer.sanitize(<<0, 1, 2, 3, 0xFF>>)
      assert {:error, :parse_error} = SvgSanitizer.sanitize("not xml at all")
    end

    test "empty binary → {:error, :parse_error}" do
      # svg-hush requires actual XML content; an empty body is not a
      # well-formed SVG and should round-trip as an error, not :ok with
      # an empty payload.
      assert {:error, :parse_error} = SvgSanitizer.sanitize("")
    end
  end
end
