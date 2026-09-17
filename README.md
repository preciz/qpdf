# Qpdf Elixir Wrapper

An Elixir wrapper for the [`qpdf`](https://github.com/qpdf/qpdf) command-line tool. It allows Elixir applications to interact with PDF files in-memory (as binaries) for operations such as page extraction, range selection, splitting, validation, and metadata inspection.

## Features

- **`Qpdf.pages/2`**: Extracts pages or page ranges from a PDF binary (supports single pages, Elixir ranges `1..5`, page lists, or qpdf range syntax).
- **`Qpdf.split_pages/2`**: Splits a PDF binary into individual single-page documents or consecutive multi-page chunks in a single pass.
- **`Qpdf.page_count/1`**: Quickly returns the page count of a PDF binary without splitting it (reads only the page tree).
- **`Qpdf.encrypted?/1`**: Checks whether a PDF binary is password-protected or encrypted.
- **`Qpdf.check/1`**: Validates the syntax and structural integrity of a PDF binary.
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

```elixir
# Example PDF binary
pdf_binary = File.read!("path/to/your/document.pdf")

# 1. Total page count (fast; reads page tree without extraction)
{:ok, count} = Qpdf.page_count(pdf_binary)
IO.puts("Total pages: #{count}")

# 2. Extract specific pages or ranges
# Single page:
{:ok, page1} = Qpdf.pages(pdf_binary, 1)

# Range of pages (returns a 5-page PDF):
{:ok, chunk} = Qpdf.pages(pdf_binary, 1..5)

# Selection of pages:
{:ok, pages_1_3_5} = Qpdf.pages(pdf_binary, [1, 3, 5])

# String range syntax supported by qpdf (e.g. even pages):
{:ok, even_pages} = Qpdf.pages(pdf_binary, "1-z:even")

# 3. Split into pages or groups
# Individual pages (list of binaries):
{:ok, single_pages} = Qpdf.split_pages(pdf_binary)

# Groups of at most N pages:
{:ok, five_page_chunks} = Qpdf.split_pages(pdf_binary, 5)

# 4. Check encryption and validity
false = Qpdf.encrypted?(pdf_binary)
:ok = Qpdf.check(pdf_binary)

# 5. Get vector of page sizes without loading page binaries into memory
case Qpdf.page_size_vector(pdf_binary) do
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
