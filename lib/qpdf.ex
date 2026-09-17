defmodule Qpdf do
  @moduledoc """
  Elixir wrapper for the `qpdf` command-line tool.

  Provides functions for PDF inspection, page selection, page extraction, and splitting.
  By default, operations automatically decrypt input PDFs if they are encrypted.

  ## Input Types

  All PDF processing functions accept `t:input/0`, which can be:
    * `binary` - in-memory PDF data
    * `{:file, path}` - path to an existing PDF file on disk

  When passing `{:file, path}`, `qpdf` directly reads the file on disk, avoiding
  loading the entire document into BEAM memory or writing redundant temporary copies.
  """

  @default_opts [
    "--no-warn",
    "--warning-exit-0",
    "--decrypt"
  ]

  @type input :: binary() | {:file, Path.t()}

  @doc """
  Extracts specified pages or page ranges from a PDF.

  Accepts:
    - an integer page number (e.g. `1`)
    - an Elixir range (e.g. `1..5`)
    - a list of page numbers (e.g. `[1, 3, 5]`)
    - a qpdf page selection string (e.g. `"1-5"`, `"1-z:even"`, `"z-1"`)

  ## Parameters
    - input: The PDF as a binary or `{:file, path}`
    - page_spec: An integer, range, list of pages, or selection string

  ## Returns
    - `{:ok, binary}` on success
    - `{:error, any}` on failure
  """
  @spec pages(input(), integer() | Range.t() | list() | String.t()) ::
          {:ok, binary} | {:error, any}
  def pages(input, page_spec) do
    spec_str = format_page_spec(page_spec)

    with_input_path(input, fn in_file ->
      args =
        [in_file | @default_opts] ++
          ["--pages", in_file, spec_str, "--", "-"]

      case run_qpdf(args) do
        {output, 0} -> {:ok, output}
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Extracts a specific page or range from a PDF.
  Delegate to `pages/2`.
  """
  @spec page(input(), integer() | Range.t() | list() | String.t()) ::
          {:ok, binary} | {:error, any}
  def page(input, page_spec), do: pages(input, page_spec)

  @doc """
  Merges multiple PDFs into a single document.

  Accepts a list of inputs. Each item in the list can be:
    * an `input` (binary or `{:file, path}`) to include all its pages
    * a `{input, page_spec}` tuple to include only specific pages or ranges

  Outputs the merged PDF directly to standard output without intermediate disk files.

  ## Examples

      # Merge multiple binaries
      {:ok, merged} = Qpdf.merge([pdf1, pdf2])

      # Merge files directly from disk without reading them into memory
      {:ok, merged} = Qpdf.merge([{:file, "cover.pdf"}, {:file, "body.pdf"}])

      # Merge specific page selections from different documents
      {:ok, merged} = Qpdf.merge([
        {{:file, "report.pdf"}, 1..5},
        {appendix_binary, "1-z:even"}
      ])
  """
  @spec merge([input() | {input(), integer() | Range.t() | list() | String.t()}]) ::
          {:ok, binary()} | {:error, any()}
  def merge(inputs) when is_list(inputs) do
    if Enum.empty?(inputs) do
      {:error, :empty_inputs}
    else
      with_merged_inputs(inputs, fn file_specs ->
        pages_args =
          Enum.flat_map(file_specs, fn
            {path, nil} -> [path]
            {path, spec} -> [path, format_page_spec(spec)]
          end)

        args = ["--empty" | @default_opts] ++ ["--pages" | pages_args] ++ ["--", "-"]

        case run_qpdf(args) do
          {output, 0} -> {:ok, output}
          other -> {:error, other}
        end
      end)
    end
  end

  @doc """
  Rotates pages in a PDF by a specified angle.

  The angle must be a multiple of 90 (e.g. `90`, `180`, `270`, `-90`).
  By default, all pages are rotated. A specific page, range, or page specification
  can optionally be provided.

  Outputs the rotated PDF directly to standard output without intermediate disk files.

  ## Examples

      # Rotate all pages 90 degrees clockwise
      {:ok, rotated} = Qpdf.rotate(input, 90)

      # Rotate only page 2 by 180 degrees
      {:ok, rotated} = Qpdf.rotate(input, 180, 2)

      # Rotate a range of pages
      {:ok, rotated} = Qpdf.rotate(input, 90, 1..5)
  """
  @spec rotate(input(), integer() | String.t(), any()) ::
          {:ok, binary()} | {:error, any()}
  def rotate(input, angle, page_spec \\ :all) do
    with_input_path(input, fn in_file ->
      rotate_arg = format_rotate_arg(angle, page_spec)

      args =
        [in_file | @default_opts] ++
          [rotate_arg, "--", "-"]

      case run_qpdf(args) do
        {output, 0} -> {:ok, output}
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Splits a PDF into pages or consecutive groups of pages.

  Defaults to splitting into individual single-page documents (`pages_per_group: 1`).
  When `pages_per_group > 1`, splits into multi-page documents of at most `pages_per_group` pages.

  Grouping happens inside a single `qpdf` execution, so splitting a large PDF into
  multiple chunks costs only one process invocation.

  ## Parameters
    - input: The PDF as a binary or `{:file, path}`
    - pages_per_group: Maximum number of pages per output part (default: 1)

  ## Returns
    - `{:ok, [binary]}` on success, in page order
    - `{:error, any}` on failure
  """
  @spec split_pages(input(), pos_integer()) :: {:ok, [binary]} | {:error, any}
  def split_pages(input, pages_per_group \\ 1)
      when is_integer(pages_per_group) and pages_per_group > 0 do
    with_input_and_output_dir(input, fn in_file, dir ->
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
            |> list_page_files()
            |> Enum.map(&File.read!/1)

          {:ok, groups}

        other ->
          {:error, other}
      end
    end)
  end

  @doc """
  Splits a PDF into individual pages.

  Returns `{:ok, [{page_number, page_binary}]}` where page_number is an integer.
  For a flat list of binaries without page number tuples, use `split_pages/2`.
  """
  @spec split(input()) :: {:ok, [{non_neg_integer, binary}]} | {:error, any}
  def split(input) do
    case split_pages(input, 1) do
      {:ok, pages} ->
        indexed =
          pages
          |> Enum.with_index(1)
          |> Enum.map(fn {page, index} -> {index, page} end)

        {:ok, indexed}

      error ->
        error
    end
  end

  @doc """
  Splits a PDF into consecutive groups of at most `pages_per_group` pages.
  Delegate to `split_pages/2`.
  """
  @spec split_groups(input(), pos_integer) :: {:ok, [binary]} | {:error, any}
  def split_groups(input, pages_per_group) do
    split_pages(input, pages_per_group)
  end

  @doc """
  Returns the page count of a PDF without splitting it.

  Uses `--show-npages`, which only reads the page tree structure without writing
  per-page files, making it very fast even on large documents.

  ## Returns
    - `{:ok, pos_integer}` on success
    - `{:error, any}` on failure
  """
  @spec page_count(input()) :: {:ok, pos_integer} | {:error, any}
  def page_count(input) do
    with_input_path(input, fn in_file ->
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
  Returns the page count of a PDF.
  Alias for `page_count/1`.
  """
  @spec show_npages(input()) :: {:ok, pos_integer} | {:error, any}
  def show_npages(input), do: page_count(input)

  @doc """
  Checks whether the given PDF is encrypted.

  Uses `qpdf --is-encrypted`.
  Returns `true` if encrypted, `false` if unencrypted, or `{:error, reason}` on failure.
  """
  @spec encrypted?(input()) :: boolean() | {:error, any}
  def encrypted?(input) do
    with_input_path(input, fn in_file ->
      case run_qpdf(["--is-encrypted", in_file]) do
        {_, 0} -> true
        {_, 2} -> false
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Checks whether the given PDF is linearized (optimized for Fast Web View).

  Uses `qpdf --check-linearization`.
  Returns `true` if linearized, `false` if not linearized, or `{:error, reason}` on failure.
  """
  @spec linearized?(input()) :: boolean() | {:error, any()}
  def linearized?(input) do
    with_input_path(input, fn in_file ->
      case run_qpdf(["--check-linearization", in_file]) do
        {output, 0} ->
          cond do
            String.contains?(output, "no linearization errors") -> true
            String.contains?(output, "not linearized") -> false
            true -> false
          end

        other ->
          {:error, other}
      end
    end)
  end

  @doc """
  Optimizes a PDF for Fast Web View (linearization).

  A linearized PDF enables viewers to display page 1 immediately over HTTP
  while the remainder of the document continues downloading.

  Outputs the linearized PDF directly to standard output without intermediate disk files.

  ## Parameters
    - input: The PDF as a binary or `{:file, path}`

  ## Returns
    - `{:ok, binary}` on success
    - `{:error, any}` on failure
  """
  @spec linearize(input()) :: {:ok, binary()} | {:error, any()}
  def linearize(input) do
    with_input_path(input, fn in_file ->
      args = [in_file | @default_opts] ++ ["--linearize", "--", "-"]

      case run_qpdf(args) do
        {output, 0} -> {:ok, output}
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Encrypts a PDF document with password protection and access permissions.

  Outputs the encrypted PDF directly to standard output without intermediate disk files.

  ## Options
    * `:user_password` - password required to open the PDF (default: `""`)
    * `:owner_password` - password required to modify permissions (default: `""`)
    * `:key_length` - encryption key length: `40`, `128`, or `256` (default: `256`)
    * `:print` - print permission: `:none`, `:low`, or `:full`
    * `:modify` - modification permission: `:none`, `:assembly`, `:form`, `:annotate`, or `:all`
    * `:extract` - boolean, allow text/graphic extraction
    * `:annotate` - boolean, allow annotations and commenting
    * `:cleartext_metadata` - boolean, keep metadata unencrypted

  ## Examples

      # Encrypt with user and owner passwords
      {:ok, enc} = Qpdf.encrypt(input, user_password: "open", owner_password: "admin")

      # Encrypt with restricted permissions
      {:ok, enc} = Qpdf.encrypt(input, owner_password: "admin", print: :none, extract: false)
  """
  @spec encrypt(input(), keyword()) :: {:ok, binary()} | {:error, any()}
  def encrypt(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      encrypt_args = build_encrypt_args(opts)
      args = [in_file, "--no-warn", "--warning-exit-0"] ++ encrypt_args ++ ["--", "-"]

      case run_qpdf(args) do
        {output, 0} -> {:ok, output}
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Decrypts an encrypted PDF document, optionally using a password.

  Outputs the unencrypted PDF directly to standard output without intermediate disk files.

  ## Options
    * `:password` - password required to decrypt the document

  ## Examples

      {:ok, plain_pdf} = Qpdf.decrypt(encrypted_input, password: "secret")
  """
  @spec decrypt(input(), keyword()) :: {:ok, binary()} | {:error, any()}
  def decrypt(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      password_args =
        case Keyword.get(opts, :password) do
          nil -> []
          pass -> ["--password=#{pass}"]
        end

      args = password_args ++ [in_file, "--no-warn", "--warning-exit-0", "--decrypt", "--", "-"]

      case run_qpdf(args) do
        {output, 0} -> {:ok, output}
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Extracts structural metadata, outlines, page details, and object trees as a decoded JSON map.

  Uses `qpdf --json`.
  Decodes the JSON output into native Elixir maps and lists using the standard library `JSON` module.

  ## Parameters
    - input: The PDF as a binary or `{:file, path}`

  ## Returns
    - `{:ok, map}` on success
    - `{:error, any}` on failure
  """
  @spec json(input()) :: {:ok, map()} | {:error, any()}
  def json(input) do
    with_input_path(input, fn in_file ->
      args = @default_opts ++ ["--json", in_file]

      case run_qpdf(args) do
        {output, 0} ->
          case JSON.decode(output) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, {:invalid_json, reason}}
          end

        other ->
          {:error, other}
      end
    end)
  end

  @doc """
  Extracts document metadata and structure as a map.
  Alias for `json/1`.
  """
  @spec metadata(input()) :: {:ok, map()} | {:error, any()}
  def metadata(input), do: json(input)

  @doc """
  Checks whether the PDF file is syntactically valid.

  Uses `qpdf --check`.
  Returns `:ok` if valid, or `{:error, reason}` if the PDF is corrupt or invalid.
  """
  @spec check(input()) :: :ok | {:error, any}
  def check(input) do
    with_input_path(input, fn in_file ->
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
  @spec page_size_vector(input()) :: {:ok, [non_neg_integer]} | {:error, any}
  def page_size_vector(input) do
    with_input_and_output_dir(input, fn in_file, dir ->
      out_file = Path.join(dir, "page.pdf")
      args = @default_opts ++ ["--split-pages", in_file, out_file]

      case run_qpdf(args) do
        {_, 0} ->
          sizes =
            dir
            |> list_page_files()
            |> Enum.map(fn page_path -> File.stat!(page_path).size end)

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

  defp format_rotate_arg(angle, spec) when spec in [:all, nil] do
    "--rotate=#{angle}"
  end

  defp format_rotate_arg(angle, spec) do
    "--rotate=#{angle}:#{format_page_spec(spec)}"
  end

  defp build_encrypt_args(opts) do
    user_pass = Keyword.get(opts, :user_password)
    owner_pass = Keyword.get(opts, :owner_password)
    bits = Keyword.get(opts, :key_length, 256)

    pass_args =
      []
      |> then(fn acc -> if user_pass, do: acc ++ ["--user-password=#{user_pass}"], else: acc end)
      |> then(fn acc ->
        if owner_pass, do: acc ++ ["--owner-password=#{owner_pass}"], else: acc
      end)

    insecure_arg =
      if user_pass && !owner_pass, do: ["--allow-insecure"], else: []

    permission_args =
      []
      |> then(fn acc ->
        case Keyword.get(opts, :print) do
          val when val in [:none, :low, :full] -> acc ++ ["--print=#{val}"]
          _ -> acc
        end
      end)
      |> then(fn acc ->
        case Keyword.get(opts, :modify) do
          val when val in [:none, :assembly, :form, :annotate, :all] -> acc ++ ["--modify=#{val}"]
          _ -> acc
        end
      end)
      |> then(fn acc ->
        case Keyword.get(opts, :extract) do
          true -> acc ++ ["--extract=y"]
          false -> acc ++ ["--extract=n"]
          _ -> acc
        end
      end)
      |> then(fn acc ->
        case Keyword.get(opts, :annotate) do
          true -> acc ++ ["--annotate=y"]
          false -> acc ++ ["--annotate=n"]
          _ -> acc
        end
      end)
      |> then(fn acc ->
        case Keyword.get(opts, :cleartext_metadata) do
          true -> acc ++ ["--cleartext-metadata"]
          _ -> acc
        end
      end)

    ["--encrypt"] ++ pass_args ++ ["--bits=#{bits}"] ++ insecure_arg ++ permission_args
  end

  defp list_page_files(dir) do
    dir
    |> Path.join("page*.pdf")
    |> Path.wildcard()
    |> Enum.sort_by(fn path ->
      case Regex.run(~r/page-(\d+)/, Path.basename(path)) do
        [_, num] -> String.to_integer(num)
        _ -> path
      end
    end)
  end

  defp qpdf_executable do
    Qpdf.Installer.ensure_executable!()
  end

  defp run_qpdf(args, opts \\ [stderr_to_stdout: true]) do
    System.cmd(qpdf_executable(), args, opts)
  end

  defp with_input_path(input, func) do
    case resolve_input(input) do
      {:file, path} ->
        func.(path)

      {:binary, binary} ->
        with_tmp_dir(fn dir ->
          in_file = Path.join(dir, "original.pdf")
          File.write!(in_file, binary)
          func.(in_file)
        end)

      {:error, _} = error ->
        error
    end
  end

  defp with_merged_inputs(inputs, func) do
    parsed =
      Enum.reduce_while(inputs, {:ok, []}, fn
        {{:file, path}, spec}, {:ok, acc} ->
          expanded = Path.expand(path)

          if File.regular?(expanded) do
            {:cont, {:ok, [{:file, expanded, spec} | acc]}}
          else
            {:halt, {:error, :enoent}}
          end

        {:file, path}, {:ok, acc} ->
          expanded = Path.expand(path)

          if File.regular?(expanded) do
            {:cont, {:ok, [{:file, expanded, nil} | acc]}}
          else
            {:halt, {:error, :enoent}}
          end

        {binary, spec}, {:ok, acc} when is_binary(binary) ->
          {:cont, {:ok, [{:binary, binary, spec} | acc]}}

        binary, {:ok, acc} when is_binary(binary) ->
          {:cont, {:ok, [{:binary, binary, nil} | acc]}}

        _other, _acc ->
          {:halt, {:error, :invalid_input}}
      end)

    case parsed do
      {:ok, reversed} ->
        items = Enum.reverse(reversed)
        has_binary? = Enum.any?(items, fn {type, _, _} -> type == :binary end)

        if has_binary? do
          with_tmp_dir(fn dir ->
            file_specs =
              items
              |> Enum.with_index(1)
              |> Enum.map(fn
                {{:binary, bin, spec}, idx} ->
                  file_path = Path.join(dir, "input_#{idx}.pdf")
                  File.write!(file_path, bin)
                  {file_path, spec}

                {{:file, path, spec}, _idx} ->
                  {path, spec}
              end)

            func.(file_specs)
          end)
        else
          file_specs = Enum.map(items, fn {:file, path, spec} -> {path, spec} end)
          func.(file_specs)
        end

      {:error, _} = error ->
        error
    end
  end

  defp with_input_and_output_dir(input, func) do
    case resolve_input(input) do
      {:file, path} ->
        with_tmp_dir(fn dir ->
          func.(path, dir)
        end)

      {:binary, binary} ->
        with_tmp_dir(fn dir ->
          in_file = Path.join(dir, "original.pdf")
          File.write!(in_file, binary)
          func.(in_file, dir)
        end)

      {:error, _} = error ->
        error
    end
  end

  defp resolve_input({:file, path}) when is_binary(path) do
    expanded = Path.expand(path)

    if File.regular?(expanded) do
      {:file, expanded}
    else
      {:error, :enoent}
    end
  end

  defp resolve_input(binary) when is_binary(binary), do: {:binary, binary}
  defp resolve_input(_other), do: {:error, :invalid_input}

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
