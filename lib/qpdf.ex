defmodule Qpdf do
  @moduledoc """
  qpdf command wrapper

  By default we want to decrypt PDFs if they are encrypted.

  Note: The --pages option in qpdf isn't working properly (checked on version 11.2.0)
  """

  @default_opts [
    "--no-warn",
    "--warning-exit-0",
    "--decrypt"
  ]

  @doc """
  Extracts a specific page from a PDF binary.

  ## Parameters
    - binary: The PDF file as a binary
    - page_number: The page number to extract (integer or string)

  ## Returns
    - {:ok, binary} on success
    - {:error, any} on failure
  """
  @spec page(binary, integer | String.t()) :: {:ok, binary} | {:error, any}
  def page(binary, page_number) when is_binary(binary) do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      out_file = Path.join(dir, "page.pdf")

      args =
        [in_file | @default_opts] ++
          ["--pages", in_file, to_string(page_number), "--", out_file]

      case run_qpdf(args) do
        {_, 0} -> File.read(out_file)
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Splits a PDF binary into individual pages.

  ## Parameters
    - binary: The PDF file as a binary

  ## Returns
    - {:ok, [{page_number, page_binary}]} on success, where page_number is a non-negative integer
    - {:error, any} on failure
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
  Splits a PDF binary into consecutive groups of at most `pages_per_group`
  pages, in page order.

  `split/1` is the `pages_per_group == 1` case. Grouping happens inside a
  single qpdf run, so splitting a large PDF into a handful of parts costs one
  invocation rather than one per part.

  ## Parameters
    - binary: The PDF file as a binary
    - pages_per_group: Maximum number of pages per output part

  ## Returns
    - {:ok, [binary]} on success, in page order
    - {:error, any} on failure
  """
  @spec split_groups(binary, pos_integer) :: {:ok, [binary]} | {:error, any}
  def split_groups(binary, pages_per_group)
      when is_binary(binary) and is_integer(pages_per_group) and pages_per_group > 0 do
    with_tmp_dir(fn dir ->
      in_file = Path.join(dir, "original.pdf")
      File.write!(in_file, binary)

      out_file = Path.join(dir, "page.pdf")
      args = @default_opts ++ ["--split-pages=#{pages_per_group}", in_file, out_file]

      case run_qpdf(args) do
        {_, 0} ->
          # qpdf names the parts `page-<first>-<last>.pdf`, zero-padded to a
          # width shared by every part, so sorting the names is page order.
          # The `page-` prefix keeps `original.pdf` out of the wildcard.
          groups =
            dir
            |> Path.join("page-*.pdf")
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
  Returns a vector with the byte size of each page in the PDF.

  Uses the same default flags as split/1 but avoids loading full page binaries
  into memory by only reading file sizes.
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
  Returns the page count of a PDF binary without splitting it.

  Uses `--show-npages`, which only reads the page tree — unlike `split/1` or
  `page_size_vector/1` it never writes a per-page file, so it stays cheap on
  very large multi-hundred-page artifacts.

  ## Returns
    - {:ok, pos_integer} on success
    - {:error, any} on failure (not a PDF, corrupt file, etc.)
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
  Returns the path to the qpdf executable, downloading and installing it if necessary.
  """
  @spec executable_path() :: String.t()
  def executable_path do
    Qpdf.Installer.ensure_executable!()
  end

  defp qpdf_executable do
    Qpdf.Installer.ensure_executable!()
  end

  defp run_qpdf(args) do
    System.cmd(qpdf_executable(), args)
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
