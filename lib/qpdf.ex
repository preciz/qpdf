defmodule Qpdf do
  @moduledoc """
  Elixir wrapper for the `qpdf` command-line tool.

  Provides functions for PDF inspection, page selection, page extraction, and splitting.
  By default, operations automatically decrypt input PDFs if they are encrypted.
  """

  @default_opts [
    "--no-warn",
    "--warning-exit-0",
    "--decrypt"
  ]

  @doc """
  Extracts specified pages or page ranges from a PDF binary.

  Accepts:
    - an integer page number (e.g. `1`)
    - an Elixir range (e.g. `1..5`)
    - a list of page numbers (e.g. `[1, 3, 5]`)
    - a qpdf page selection string (e.g. `"1-5"`, `"1-z:even"`, `"z-1"`)

  ## Parameters
    - binary: The PDF file as a binary
    - page_spec: An integer, range, list of pages, or selection string

  ## Returns
    - `{:ok, binary}` on success
    - `{:error, any}` on failure
  """
  @spec pages(binary, integer() | Range.t() | list() | String.t()) ::
          {:ok, binary} | {:error, any}
  def pages(binary, page_spec) when is_binary(binary) do
    spec_str = format_page_spec(page_spec)

    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      out_file = Path.join(dir, "pages.pdf")

      args =
        [in_file | @default_opts] ++
          ["--pages", in_file, spec_str, "--", out_file]

      case run_qpdf(args) do
        {_, 0} -> File.read(out_file)
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Extracts a specific page or range from a PDF binary.
  Delegate to `pages/2`.
  """
  @spec page(binary, integer() | Range.t() | list() | String.t()) ::
          {:ok, binary} | {:error, any}
  def page(binary, page_spec), do: pages(binary, page_spec)

  @doc """
  Splits a PDF binary into pages or consecutive groups of pages.

  Defaults to splitting into individual single-page documents (`pages_per_group: 1`).
  When `pages_per_group > 1`, splits into multi-page documents of at most `pages_per_group` pages.

  Grouping happens inside a single `qpdf` execution, so splitting a large PDF into
  multiple chunks costs only one process invocation.

  ## Parameters
    - binary: The PDF file as a binary
    - pages_per_group: Maximum number of pages per output part (default: 1)

  ## Returns
    - `{:ok, [binary]}` on success, in page order
    - `{:error, any}` on failure
  """
  @spec split_pages(binary, pos_integer()) :: {:ok, [binary]} | {:error, any}
  def split_pages(binary, pages_per_group \\ 1)
      when is_binary(binary) and is_integer(pages_per_group) and pages_per_group > 0 do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      out_file = Path.join(dir, "page.pdf")

      split_arg =
        if pages_per_group == 1 do
          "--split-pages"
        else
          "--split-pages=#{pages_per_group}"
        end

      args = @default_opts ++ [split_arg, in_file, out_file]

      case run_qpdf(args) do
        {_, 0} ->
          groups =
            dir
            |> Path.join("page*.pdf")
            |> Path.wildcard()
            |> Enum.sort()
            |> Enum.map(&File.read!/1)

          {:ok, groups}

        other ->
          {:error, other}
      end
    end)
  end

  @doc """
  Splits a PDF binary into individual pages.

  Returns `{:ok, [{page_number, page_binary}]}` where page_number is an integer.
  For a flat list of binaries without page number tuples, use `split_pages/2`.
  """
  @spec split(binary) :: {:ok, [{non_neg_integer, binary}]} | {:error, any}
  def split(binary) when is_binary(binary) do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      out_file = Path.join(dir, "page.pdf")
      args = @default_opts ++ ["--split-pages", in_file, out_file]

      case run_qpdf(args) do
        {_, 0} ->
          pages =
            dir
            |> Path.join("page*.pdf")
            |> Path.wildcard()
            |> Enum.map(fn page_path ->
              {number, ".pdf"} =
                page_path |> String.split("page-") |> List.last() |> Integer.parse()

              {number, File.read!(page_path)}
            end)
            |> Enum.sort()

          {:ok, pages}

        other ->
          {:error, other}
      end
    end)
  end

  @doc """
  Splits a PDF binary into consecutive groups of at most `pages_per_group` pages.
  Delegate to `split_pages/2`.
  """
  @spec split_groups(binary, pos_integer) :: {:ok, [binary]} | {:error, any}
  def split_groups(binary, pages_per_group) do
    split_pages(binary, pages_per_group)
  end

  @doc """
  Returns the page count of a PDF binary without splitting it.

  Uses `--show-npages`, which only reads the page tree structure without writing
  per-page files, making it very fast even on large documents.

  ## Returns
    - `{:ok, pos_integer}` on success
    - `{:error, any}` on failure
  """
  @spec page_count(binary) :: {:ok, pos_integer} | {:error, any}
  def page_count(binary) when is_binary(binary) do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      args = @default_opts ++ ["--show-npages", in_file]

      case run_qpdf(args) do
        {output, 0} ->
          case output |> String.trim() |> Integer.parse() do
            {count, ""} when count > 0 -> {:ok, count}
            _ -> {:error, {:unexpected_output, output}}
          end

        other ->
          {:error, other}
      end
    end)
  end

  @doc """
  Returns the page count of a PDF binary.
  Alias for `page_count/1`.
  """
  @spec show_npages(binary) :: {:ok, pos_integer} | {:error, any}
  def show_npages(binary), do: page_count(binary)

  @doc """
  Checks whether the given PDF binary is encrypted.

  Uses `qpdf --is-encrypted`.
  Returns `true` if encrypted, `false` if unencrypted, or `{:error, reason}` on failure.
  """
  @spec encrypted?(binary) :: boolean() | {:error, any}
  def encrypted?(binary) when is_binary(binary) do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      case run_qpdf(["--is-encrypted", in_file]) do
        {_, 0} -> true
        {_, 2} -> false
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Checks whether the PDF file is syntactically valid.

  Uses `qpdf --check`.
  Returns `:ok` if valid, or `{:error, reason}` if the PDF is corrupt or invalid.
  """
  @spec check(binary) :: :ok | {:error, any}
  def check(binary) when is_binary(binary) do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      case run_qpdf(["--warning-exit-0", "--check", in_file]) do
        {_, 0} -> :ok
        {output, code} -> {:error, {:check_failed, code, output}}
      end
    end)
  end

  @doc """
  Returns a list with the byte size of each page in the PDF.

  Uses the same default flags as `split/1` but avoids loading full page binaries
  into memory by reading file metadata directly.
  """
  @spec page_size_vector(binary) :: {:ok, [non_neg_integer]} | {:error, any}
  def page_size_vector(binary) when is_binary(binary) do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      out_file = Path.join(dir, "page.pdf")
      args = @default_opts ++ ["--split-pages", in_file, out_file]

      case run_qpdf(args) do
        {_, 0} ->
          sizes =
            dir
            |> Path.join("page*.pdf")
            |> Path.wildcard()
            |> Enum.map(fn page_path ->
              {number, ".pdf"} =
                page_path |> String.split("page-") |> List.last() |> Integer.parse()

              %{size: size} = File.stat!(page_path)
              {number, size}
            end)
            |> Enum.sort()
            |> Enum.map(fn {_number, size} -> size end)

          {:ok, sizes}

        other ->
          {:error, other}
      end
    end)
  end

  @doc """
  Returns the path to the qpdf executable, downloading and installing it if necessary.
  """
  @spec executable_path() :: String.t()
  def executable_path do
    Qpdf.Installer.ensure_executable!()
  end

  @doc """
  Returns the base temporary directory used for PDF operations.

  Defaults to `System.tmp_dir!()`, but can be configured in your application:

      config :qpdf, tmp_dir: "/path/to/custom/tmp"
  """
  @spec tmp_dir() :: String.t()
  def tmp_dir do
    Application.get_env(:qpdf, :tmp_dir) || System.tmp_dir!()
  end

  defp format_page_spec(%Range{first: first, last: last}), do: "#{first}-#{last}"
  defp format_page_spec(pages) when is_list(pages), do: Enum.join(pages, ",")
  defp format_page_spec(spec), do: to_string(spec)

  defp qpdf_executable do
    Qpdf.Installer.ensure_executable!()
  end

  defp run_qpdf(args) do
    System.cmd(qpdf_executable(), args)
  end

  defp with_tmp_dir(func) do
    dir = Path.join(tmp_dir(), "qpdf/#{Base.encode16(:crypto.strong_rand_bytes(4))}")
    File.mkdir_p!(dir)

    try do
      func.(dir)
    after
      File.rm_rf(dir)
    end
  end
end
