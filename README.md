# Qpdf Elixir Wrapper

An Elixir wrapper for the [`qpdf`](https://github.com/qpdf/qpdf) command-line tool. It allows Elixir applications to interact with PDF files in-memory (as binaries) or directly from disk (`{:file, path}`) for operations such as page extraction, range selection, splitting, validation, and metadata inspection.

## Features

- **Input Flexibility**: All functions accept either an in-memory `binary` or `{:file, path}`. When using `{:file, path}`, operations avoid loading the document into BEAM memory or writing redundant temporary copies to disk.
- **Output Destination Polymorphism (`:into`)**: All generation and transformation functions accept `into: :memory` (default), `into: "path/to/file.pdf"`, or `into: {:file, "path/to/file.pdf"}`. When writing directly to disk, bytes are streamed from `qpdf` directly to the target file with zero BEAM memory consumption.
- **`Qpdf.pages/3`**: Extracts pages or page ranges from a PDF (supports single pages, Elixir ranges `1..5`, page lists, or qpdf range syntax), streaming output directly to memory or a file.
- **`Qpdf.merge/2`**: Combines multiple PDFs and page selections into a single document in a single execution.
- **`Qpdf.rotate/3,4`**: Rotates all pages or specific page ranges by any multiple of 90 degrees.
- **`Qpdf.overlay/3` & `underlay/3`**: Overlays foreground watermarks/stamps or underlays background letterheads and stationery with optional page repeat.
- **`Qpdf.optimize/2` & `compress/2`**: Reduces PDF file size by compressing uncompressed streams, packing objects into compressed object streams, and recompressing Flate streams.
- **`Qpdf.attachments/1`, `add_attachment/3`, `extract_attachment/3`, `remove_attachment/3`**: Full support for PDF embedded files (Factur-X / ZUGFeRD e-invoices, audit logs, XML/CSV attachments) with zero-RAM extraction and insertion.
- **`Qpdf.dimensions/1,2`**: Inspects page geometry, bounding boxes (MediaBox, CropBox), width/height in points, visual orientation (`:portrait`, `:landscape`, `:square`), and detects standard paper sizes (`A4`, `Letter`, etc.).
- **`Qpdf.linearize/2` & `linearized?/1`**: Optimizes PDFs for Fast Web View (page-at-a-time streaming over HTTP) and verifies linearization status.
- **`Qpdf.encrypt/2` & `decrypt/2`**: Applies password protection and permission restrictions (printing, extraction, form filling) or removes encryption.
- **`Qpdf.json/1,2` (or `metadata/1,2`**: Parses the complete document structure, outlines/bookmarks, and page geometry as native Elixir data (supports `--json` schema version 1 and 2).
- **`Qpdf.split_pages/2,3`**: Splits a PDF into individual single-page documents or consecutive multi-page chunks in a single pass directly into memory or disk directories.
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

All operations accept either an in-memory `binary` or a file path `{:file, "path/to/doc.pdf"}`. Every generation and transformation function also accepts the `:into` option to stream output directly into a target file without loading it into BEAM memory.

```elixir
# Inputs can be in-memory binaries:
pdf_binary = File.read!("document.pdf")

# ...or direct file references on disk (zero memory copying):
pdf_file = {:file, "document.pdf"}

# 1. Total page count (fast; reads page tree without extraction)
{:ok, count} = Qpdf.page_count(pdf_file)
IO.puts("Total pages: #{count}")

# 2. Extract specific pages or ranges
{:ok, page1} = Qpdf.pages(pdf_file, 1)
{:ok, chunk} = Qpdf.pages(pdf_file, 1..5)
{:ok, pages_1_3_5} = Qpdf.pages(pdf_file, [1, 3, 5])
{:ok, even_pages} = Qpdf.pages(pdf_file, "1-z:even")

# Extract directly to a file on disk (zero BEAM memory overhead)
{:ok, path} = Qpdf.pages(pdf_file, 1..3, into: "chapter1.pdf")

# 3. Merge multiple documents and selections
{:ok, merged} = Qpdf.merge([
  pdf_file,
  {{:file, "appendix.pdf"}, 1..3},
  pdf_binary
])

# Merge disk-to-disk directly
{:ok, path} = Qpdf.merge([{:file, "part1.pdf"}, {:file, "part2.pdf"}], into: "final.pdf")

# 4. Watermarks and Letterheads (Overlay & Underlay)
# Apply a foreground watermark stamp across all pages
{:ok, stamped} = Qpdf.overlay(pdf_file, {:file, "stamp.pdf"}, repeat: true)

# Apply a digital letterhead background
{:ok, with_header} = Qpdf.underlay(pdf_file, {:file, "letterhead.pdf"}, repeat: true)

# 5. File size optimization and compression
{:ok, compressed} = Qpdf.optimize(pdf_file,
  stream_data: :compress,
  object_streams: :generate,
  recompress_flate: true
)

# 6. Embedded Files and Attachments (Factur-X / ZUGFeRD)
# Embed an electronic invoice XML
{:ok, with_invoice} = Qpdf.add_attachment(pdf_file, xml_data,
  key: "factur-x.xml",
  filename: "factur-x.xml",
  mimetype: "text/xml",
  description: "Factur-X E-Invoice"
)

# List all embedded attachments
{:ok, attachments} = Qpdf.attachments(with_invoice)
# => [%{key: "factur-x.xml", filename: "factur-x.xml", mimetype: "text/xml", ...}]

# Extract an attachment directly to memory or a file
{:ok, xml_bytes} = Qpdf.extract_attachment(with_invoice, "factur-x.xml")
{:ok, path} = Qpdf.extract_attachment(with_invoice, "factur-x.xml", into: "invoice.xml")

# Remove an attachment
{:ok, cleaned} = Qpdf.remove_attachment(with_invoice, "factur-x.xml")

# 7. Page Geometry and Dimensions
# Inspect all pages
{:ok, dims} = Qpdf.dimensions(pdf_file)

# Inspect a single page
{:ok, page1_dim} = Qpdf.dimensions(pdf_file, 1)
IO.inspect(page1_dim.width)        # => 595.28
IO.inspect(page1_dim.height)       # => 841.89
IO.inspect(page1_dim.orientation)  # => :portrait
IO.inspect(page1_dim.paper_size)   # => "A4"
IO.inspect(page1_dim.box.media)    # => [0.0, 0.0, 595.28, 841.89]

# 8. Rotate pages
{:ok, rotated_all} = Qpdf.rotate(pdf_file, 90)
{:ok, rotated_page2} = Qpdf.rotate(pdf_file, 180, 2)

# 9. Linearize for Fast Web View (HTTP streaming)
false = Qpdf.linearized?(pdf_file)
{:ok, web_pdf} = Qpdf.linearize(pdf_file)
true = Qpdf.linearized?(web_pdf)

# 10. Encrypt and decrypt
{:ok, secure_pdf} = Qpdf.encrypt(pdf_file,
  user_password: "open",
  owner_password: "admin",
  print: :none,
  extract: false
)
{:ok, plain_pdf} = Qpdf.decrypt(secure_pdf, password: "open")

# 11. Extract document metadata, outlines, and structural tree as JSON map
{:ok, metadata} = Qpdf.json(pdf_file)
IO.inspect(metadata["outlines"])

# 12. Split into pages or groups (to memory or disk directory)
{:ok, single_pages} = Qpdf.split_pages(pdf_binary)
{:ok, five_page_chunks} = Qpdf.split_pages(pdf_file, 5)

# Split directly into a destination directory without loading pages into memory
{:ok, page_paths} = Qpdf.split_pages(pdf_file, into: "/path/to/output_dir")

# 13. Check encryption and validity
false = Qpdf.encrypted?(pdf_file)
:ok = Qpdf.check(pdf_file)

# 14. Get vector of page sizes without loading page binaries into memory
{:ok, sizes} = Qpdf.page_size_vector(pdf_file)
IO.inspect(sizes) # e.g., [12345, 67890, ...]
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
