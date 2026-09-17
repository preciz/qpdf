# Qpdf Elixir Wrapper

[![CI](https://github.com/preciz/qpdf/actions/workflows/ci.yml/badge.svg)](https://github.com/preciz/qpdf/actions/workflows/ci.yml)

An Elixir wrapper for the [`qpdf`](https://github.com/qpdf/qpdf) command-line tool. It allows Elixir applications to interact with PDF files in-memory (as binaries) or directly from disk (`{:file, path}`) for operations such as page extraction, range selection, splitting, validation, and metadata inspection.

## Features

- **Flexible I/O & Zero-RAM Pipelines**: Accept in-memory `binary` or `{:file, path}` inputs, and stream outputs directly to memory or disk files (`into: path`) without heap overhead.
- **Page Manipulation**: Merge, split, rotate, extract, and reorder pages or page ranges using native ranges, lists, or qpdf spec strings.
- **Watermarks & Layers**: Apply foreground stamps/overlays and background letterheads/stationery with page-targeting and repetition.
- **Optimization & Security**: Compress streams and object streams, linearize for Fast Web View, and manage encryption, passwords, and permissions.
- **Embedded Files & Geometry**: Embed, extract, list, and remove attachments (Factur-X / ZUGFeRD e-invoices, XML, CSV), and inspect page geometry, bounding boxes, and dimensions.
- **Zero-Setup Distribution**: Automatically downloads and extracts pre-built official `qpdf` binaries on Linux x86_64, or uses the system executable.

## Requirements

- Elixir `~> 1.19`
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
- `mix qpdf.install --if-missing` — Installs only if the executable is not already installed.
- `mix qpdf.install --version 12.3.1` — Installs a specific version.
- `mix qpdf.install --force` — Overwrites an existing installation.

### Configuration

You can configure the binary lookup behavior via environment variables or in your `config/config.exs`:

```bash
# Set custom binary location via environment variable (useful in Docker / CI)
export QPDF_PATH="/usr/bin/qpdf"
```

```elixir
# Or explicitly point to a system or custom binary in config
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

# Optimize raster images with DCT (JPEG) recompression
{:ok, image_optimized} = Qpdf.optimize_images(pdf_file,
  jpeg_quality: 80,
  min_area: 10_000,
  remove_unreferenced: true
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

# Validate passwords and check if password is required
true = Qpdf.requires_password?(secure_pdf)
true = Qpdf.password_valid?(secure_pdf, "open")
false = Qpdf.password_valid?(secure_pdf, "wrong")

# Inspect detailed encryption parameters (cipher, revision, permission flags)
{:ok, enc_info} = Qpdf.encryption_info(secure_pdf)
IO.inspect(enc_info.r)             # => 6
IO.inspect(enc_info.stream_method) # => "AESv3"
IO.inspect(enc_info.permissions.print_high) # => false

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

# 15. Check installed qpdf binary version
{:ok, version} = Qpdf.bin_version()
IO.puts("Running qpdf #{version}")
```

## Backward Compatibility

Convenience aliases and delegates are available across the API:
- `Qpdf.page/2,3` delegates to `Qpdf.pages/3`.
- `Qpdf.split/1,2` delegates to `Qpdf.split_pages/3` and returns `{:ok, [{page_number, page_output}]}`.
- `Qpdf.split_groups/2,3` delegates to `Qpdf.split_pages/3`.
- `Qpdf.show_npages/1` is an alias for `Qpdf.page_count/1`.
- `Qpdf.metadata/1,2` is an alias for `Qpdf.json/1,2`.
- `Qpdf.compress/1,2` is an alias for `Qpdf.optimize/1,2`.

## Running Tests

To run the test suite:

```bash
mix test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
