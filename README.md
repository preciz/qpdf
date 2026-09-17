# Qpdf Elixir Wrapper

An Elixir wrapper for the [`qpdf`](https://github.com/qpdf/qpdf) command-line tool. It allows Elixir applications to interact with PDF files in-memory (as binaries) for operations such as page count inspection, page extraction, splitting, and retrieving page size information.

## Features

- **`Qpdf.page_count/1`**: Quickly returns the page count of a PDF binary without splitting it (reads only the page tree).
- **`Qpdf.page/2`**: Extracts a specific page from a PDF binary.
- **`Qpdf.split/1`**: Splits a PDF binary into individual pages.
- **`Qpdf.split_groups/2`**: Splits a PDF binary into consecutive groups of at most `pages_per_group` pages in a single `qpdf` invocation.
- **`Qpdf.page_size_vector/1`**: Returns a list of byte sizes for each page in a PDF without loading all page binaries into memory.
- **`Qpdf.executable_path/0`**: Returns the path to the resolved or installed `qpdf` executable.

## Requirements

- Elixir `~> 1.18`
- Linux x86_64 (AppImage automatically downloaded and extracted), or a system-installed `qpdf` binary (`brew install qpdf`, `apt install qpdf`, etc.) on other platforms.

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

No manual installation is required! On Linux x86_64, `qpdf` will automatically download and extract the official `qpdf` AppImage on first use (stored in `_build/qpdf/` under Mix, or `priv/native` in releases).

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

# 1. Get total page count (fast; does not extract or split)
{:ok, count} = Qpdf.page_count(pdf_binary)
IO.puts("Total pages: #{count}")

# 2. Extract a single page (e.g. page 1)
case Qpdf.page(pdf_binary, 1) do
  {:ok, page_binary} ->
    IO.puts("Extracted page 1, size: #{byte_size(page_binary)} bytes")

  {:error, reason} ->
    IO.inspect(reason)
end

# 3. Split into individual pages
case Qpdf.split(pdf_binary) do
  {:ok, pages} ->
    for {page_number, page_binary} <- pages do
      IO.puts("Page #{page_number} size: #{byte_size(page_binary)} bytes")
    end

  {:error, reason} ->
    IO.inspect(reason)
end

# 4. Split into chunks/groups of at most N pages
case Qpdf.split_groups(pdf_binary, 5) do
  {:ok, groups} ->
    IO.puts("Split into #{length(groups)} chunks of up to 5 pages each")

  {:error, reason} ->
    IO.inspect(reason)
end

# 5. Get vector of page sizes without loading page binaries into memory
case Qpdf.page_size_vector(pdf_binary) do
  {:ok, sizes} ->
    IO.inspect(sizes) # e.g., [12345, 67890, ...]

  {:error, reason} ->
    IO.inspect(reason)
end
```

## Running Tests

To run the test suite:

```bash
mix test
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

