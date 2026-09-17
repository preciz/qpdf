# Qpdf Elixir Wrapper

An Elixir wrapper for the [`qpdf`](https://github.com/qpdf/qpdf) command-line tool. It allows Elixir applications to interact with PDF files in-memory (as binaries) or directly from disk (`{:file, path}`) for operations such as page extraction, range selection, splitting, validation, and metadata inspection.

## Features

- **Input Flexibility**: All functions accept either an in-memory `binary` or `{:file, path}`. When using `{:file, path}`, operations avoid loading the document into BEAM memory or writing redundant temporary copies to disk.
- **`Qpdf.pages/2`**: Extracts pages or page ranges from a PDF (supports single pages, Elixir ranges `1..5`, page lists, or qpdf range syntax), streaming output directly to memory.
- **`Qpdf.merge/1`**: Combines multiple PDFs and page selections into a single document in a single execution.
- **`Qpdf.rotate/2,3`**: Rotates all pages or specific page ranges by any multiple of 90 degrees.
- **`Qpdf.linearize/1` & `linearized?/1`**: Optimizes PDFs for Fast Web View (page-at-a-time streaming over HTTP) and verifies linearization status.
- **`Qpdf.encrypt/2` & `decrypt/2`**: Applies password protection and permission restrictions (printing, extraction, form filling) or removes encryption.
- **`Qpdf.json/1` (or `metadata/1`)**: Parses the complete document structure, outlines/bookmarks, and page geometry as native Elixir data.
- **`Qpdf.split_pages/2`**: Splits a PDF into individual single-page documents or consecutive multi-page chunks in a single pass.
- **`Qpdf.page_count/1`**: Quickly returns the page count of a PDF without splitting it (reads only the page tree).
- **`Qpdf.encrypted?/1`**: Checks whether a PDF is password-protected or encrypted.
- **`Qpdf.check/1`**: Validates the syntax and structural integrity of a PDF.
- **`Qpdf.page_size_vector/1`**: Returns a list of byte sizes for each page in a PDF without loading all page binaries into memory.
- **`Qpdf.executable_path/0`**: Returns the path to the resolved or installed `qpdf` executable.

## Requirements

- Elixir `~> 1.18`
- Linux x86_64 (official AppImage automatically downloaded and extracted), or a system-installed `qpdf` binary (`brew install qpdf`, `apt install qpdf`, etc.) on other platforms.

## Installation

Add `:qpdf` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:qpdf, "~> 0.1.0"}
  ]
end
```

Then run `mix deps.get`.

### Automatic Binary Setup

No manual installation is required! On Linux x86_64, `qpdf` will automatically download and extract the official `qpdf` AppImage on first use (stored in `_build/qpdf-<version>/` under Mix, or `priv/native` in releases).

If running on macOS or ARM Linux, `qpdf` will automatically detect and use your system-installed `qpdf` executable if present.

You can also pre-install or pre-cache the binary explicitly (for example, in your Dockerfile or CI build):

```bash
mix qpdf.install
```

Optional flags:
- `mix qpdf.install --version 12.3.1` — Installs a specific version.
- `mix qpdf.install --force` — Overwrites an existing installation.

### Configuration

You can configure the binary lookup behavior in your `config/config.exs`:

```elixir
# Explicitly point to a system or custom binary
config :qpdf, executable_path: "/usr/bin/qpdf"

# Prefer a system-installed qpdf if available, falling back to auto-downloading the AppImage
config :qpdf, prefer_system_executable: true

# Specify a specific qpdf release version (default: "12.3.1")
config :qpdf, version: "12.3.1"

# Optional: custom base temporary directory for PDF processing and downloads (default: System.tmp_dir!())
config :qpdf, tmp_dir: "/mnt/scratch"
```

## Usage

All operations accept either an in-memory `binary` or a file path `{:file, "path/to/doc.pdf"}`.

```elixir
# Inputs can be in-memory binaries:
pdf_binary = File.read!("document.pdf")

# ...or direct file references on disk (zero memory copying):
pdf_file = {:file, "document.pdf"}

# 1. Total page count (fast; reads page tree without extraction)
{:ok, count} = Qpdf.page_count(pdf_file)
IO.puts("Total pages: #{count}")

# 2. Extract specific pages or ranges (streamed directly to stdout into memory)
{:ok, page1} = Qpdf.pages(pdf_file, 1)
{:ok, chunk} = Qpdf.pages(pdf_file, 1..5)
{:ok, pages_1_3_5} = Qpdf.pages(pdf_file, [1, 3, 5])
{:ok, even_pages} = Qpdf.pages(pdf_file, "1-z:even")

# 3. Merge multiple documents and selections
{:ok, merged} = Qpdf.merge([
  pdf_file,
  {{:file, "appendix.pdf"}, 1..3},
  pdf_binary
])

# 4. Rotate pages (e.g. fix landscape scans)
{:ok, rotated_all} = Qpdf.rotate(pdf_file, 90)
{:ok, rotated_page2} = Qpdf.rotate(pdf_file, 180, 2)

# 5. Linearize for Fast Web View (HTTP streaming)
false = Qpdf.linearized?(pdf_file)
{:ok, web_pdf} = Qpdf.linearize(pdf_file)
true = Qpdf.linearized?(web_pdf)

# 6. Encrypt and decrypt
{:ok, secure_pdf} = Qpdf.encrypt(pdf_file,
  user_password: "open",
  owner_password: "admin",
  print: :none,
  extract: false
)
{:ok, plain_pdf} = Qpdf.decrypt(secure_pdf, password: "open")

# 7. Extract document metadata, outlines, and structural tree as JSON map
{:ok, metadata} = Qpdf.json(pdf_file)
IO.inspect(metadata["outlines"])

# 8. Split into pages or groups
{:ok, single_pages} = Qpdf.split_pages(pdf_binary)
{:ok, five_page_chunks} = Qpdf.split_pages(pdf_file, 5)

# 9. Check encryption and validity
false = Qpdf.encrypted?(pdf_file)
:ok = Qpdf.check(pdf_file)

# 10. Get vector of page sizes without loading page binaries into memory
case Qpdf.page_size_vector(pdf_file) do
  {:ok, sizes} ->
    IO.inspect(sizes) # e.g., [12345, 67890, ...]

  {:error, reason} ->
    IO.inspect(reason)
end
```

## Backward Compatibility

The original functions remain available as aliases/delegates:
- `Qpdf.page/2` delegates to `Qpdf.pages/2`.
- `Qpdf.split/1` returns `{:ok, [{page_number, page_binary}]}`.
- `Qpdf.split_groups/2` delegates to `Qpdf.split_pages/2`.
- `Qpdf.show_npages/1` is an alias for `Qpdf.page_count/1`.

## Running Tests

To run the test suite:

```bash
mix test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
