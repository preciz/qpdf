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
    - `{:ok, binary | Path.t()}` on success
    - `{:error, any}` on failure
  """
  @spec pages(input(), integer() | Range.t() | list() | String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any}
  def pages(input, page_spec, opts \\ []) do
    spec_str = format_page_spec(page_spec)

    with_input_path(input, fn in_file ->
      args = [in_file | @default_opts] ++ ["--pages", in_file, spec_str]
      run_qpdf_into(args, opts)
    end)
  end

  @doc """
  Extracts a specific page or range from a PDF.
  Delegate to `pages/3`.
  """
  @spec page(input(), integer() | Range.t() | list() | String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any}
  def page(input, page_spec, opts \\ []), do: pages(input, page_spec, opts)

  @doc """
  Merges multiple PDFs into a single document.

  Accepts a list of inputs. Each item in the list can be:
    * an `input` (binary or `{:file, path}`) to include all its pages
    * a `{input, page_spec}` tuple to include only specific pages or ranges

  Outputs the merged PDF directly to memory or a file specified with `into:`.

  ## Examples

      # Merge multiple binaries into memory
      {:ok, merged} = Qpdf.merge([pdf1, pdf2])

      # Merge files directly to a destination path without loading bytes into BEAM memory
      {:ok, path} = Qpdf.merge([{:file, "cover.pdf"}, {:file, "body.pdf"}], into: "merged.pdf")

      # Merge specific page selections from different documents
      {:ok, merged} = Qpdf.merge([
        {{:file, "report.pdf"}, 1..5},
        {appendix_binary, "1-z:even"}
      ])
  """
  @spec merge([input() | {input(), integer() | Range.t() | list() | String.t()}], keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def merge(inputs, opts \\ []) when is_list(inputs) do
    if Enum.empty?(inputs) do
      {:error, :empty_inputs}
    else
      with_merged_inputs(inputs, fn file_specs ->
        pages_args =
          Enum.flat_map(file_specs, fn
            {path, nil} -> [path]
            {path, spec} -> [path, format_page_spec(spec)]
          end)

        args = ["--empty" | @default_opts] ++ ["--pages" | pages_args]
        run_qpdf_into(args, opts)
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
  @spec rotate(input(), integer() | String.t(), any(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def rotate(input, angle, page_spec \\ :all, opts \\ []) do
    with_input_path(input, fn in_file ->
      rotate_arg = format_rotate_arg(angle, page_spec)
      args = [in_file | @default_opts] ++ [rotate_arg]
      run_qpdf_into(args, opts)
    end)
  end

  @doc """
  Overlays pages from another PDF on top of the input document.

  Useful for applying stamps, watermarks, signatures, or foreground content.
  Outputs the result directly to standard output without intermediate disk files.

  ## Options
    * `:to` - page specification on the destination document (e.g. `1..5`, `"even"`)
    * `:from` - page specification on the overlay document
    * `:repeat` - repeat overlay pages (e.g. `"1-z"` or `true` to repeat all pages)
    * `:password` - password for the overlay document if encrypted

  ## Examples

      # Apply a 1-page watermark across all pages
      {:ok, watermarked} = Qpdf.overlay(doc, watermark_pdf, repeat: true)

      # Apply a stamp to page 1 only
      {:ok, stamped} = Qpdf.overlay(doc, stamp_pdf, to: 1)
  """
  @spec overlay(input(), input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def overlay(input, overlay_input, opts \\ []) do
    apply_layer(input, :overlay, overlay_input, opts)
  end

  @doc """
  Underlays pages from another PDF behind the input document.

  Useful for applying digital letterheads, backgrounds, or stationery.
  Outputs the result directly to standard output without intermediate disk files.

  ## Options
    * `:to` - page specification on the destination document
    * `:from` - page specification on the underlay document
    * `:repeat` - repeat underlay pages (e.g. `"1-z"` or `true` to repeat all pages)
    * `:password` - password for the underlay document if encrypted
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      # Apply a background letterhead across all pages
      {:ok, with_letterhead} = Qpdf.underlay(doc, letterhead_pdf, repeat: true)
  """
  @spec underlay(input(), input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def underlay(input, underlay_input, opts \\ []) do
    apply_layer(input, :underlay, underlay_input, opts)
  end

  @doc """
  Splits a PDF into pages or consecutive groups of pages.

  Defaults to splitting into individual single-page documents (`pages_per_group: 1`).
  When `pages_per_group > 1`, splits into multi-page documents of at most `pages_per_group` pages.

  Grouping happens inside a single `qpdf` execution, so splitting a large PDF into
  multiple chunks costs only one process invocation.

  ## Options
    * `:into` - destination directory: `:memory` (default, returns `[binary]`) or
      `path` / `{:dir, path}` (returns `[Path.t()]` without loading files into memory)

  ## Returns
    - `{:ok, [binary] | [Path.t()]}` on success, in page order
    - `{:error, any}` on failure
  """
  @spec split_pages(input(), pos_integer() | keyword(), keyword()) ::
          {:ok, [binary()] | [Path.t()]} | {:error, any()}
  def split_pages(input, opts) when is_list(opts) do
    pages_per_group = Keyword.get(opts, :pages_per_group, 1)
    split_pages(input, pages_per_group, opts)
  end

  def split_pages(input, pages_per_group \\ 1, opts \\ [])

  def split_pages(input, pages_per_group, opts)
      when is_integer(pages_per_group) and pages_per_group > 0 and is_list(opts) do
    case Keyword.get(opts, :into, :memory) do
      :memory ->
        with_input_and_output_dir(input, fn in_file, dir ->
          do_split_pages(in_file, dir, pages_per_group, :memory)
        end)

      {:dir, dir_path} when is_binary(dir_path) ->
        expanded = Path.expand(dir_path)
        File.mkdir_p!(expanded)

        with_input_path(input, fn in_file ->
          do_split_pages(in_file, expanded, pages_per_group, :paths)
        end)

      dir_path when is_binary(dir_path) ->
        expanded = Path.expand(dir_path)
        File.mkdir_p!(expanded)

        with_input_path(input, fn in_file ->
          do_split_pages(in_file, expanded, pages_per_group, :paths)
        end)

      _ ->
        {:error, :invalid_destination}
    end
  end

  @doc """
  Splits a PDF into individual pages.

  Returns `{:ok, [{page_number, page_binary | file_path}]}` where page_number is an integer.
  For a flat list of binaries without page number tuples, use `split_pages/2`.
  """
  @spec split(input(), keyword()) ::
          {:ok, [{non_neg_integer, binary() | Path.t()}]} | {:error, any}
  def split(input, opts \\ []) do
    case split_pages(input, 1, opts) do
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
  Delegate to `split_pages/3`.
  """
  @spec split_groups(input(), pos_integer, keyword()) ::
          {:ok, [binary()] | [Path.t()]} | {:error, any}
  def split_groups(input, pages_per_group, opts \\ []) do
    split_pages(input, pages_per_group, opts)
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

  @doc \"""
  Optimizes a PDF for Fast Web View (linearization).

  A linearized PDF enables viewers to display page 1 immediately over HTTP
  while the remainder of the document continues downloading.

  Outputs the linearized PDF directly to standard output without intermediate disk files.

  ## Options
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Returns
    - `{:ok, binary | Path.t()}` on success
    - `{:error, any}` on failure
  """
  @spec linearize(input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def linearize(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      args = [in_file | @default_opts] ++ ["--linearize"]
      run_qpdf_into(args, opts)
    end)
  end

  @doc """
  Optimizes and compresses a PDF document to reduce file size.

  Compresses uncompressed streams, generates object streams (packing objects into
  compressed stream containers), and recompresses Flate streams.

  Outputs the optimized PDF directly to standard output without intermediate disk files.

  ## Options
    * `:stream_data` - `:compress` (default), `:uncompress`, or `:preserve`
    * `:object_streams` - `:generate` (default), `:preserve`, or `:disable`
    * `:recompress_flate` - boolean, whether to recompress flate streams (default: `true`)
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      {:ok, compressed} = Qpdf.optimize(input)
      {:ok, compressed} = Qpdf.compress(input)
  """
  @spec optimize(input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def optimize(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      opt_args = build_optimize_args(opts)
      args = [in_file | @default_opts] ++ opt_args
      run_qpdf_into(args, opts)
    end)
  end

  @doc """
  Compresses a PDF document to reduce file size.
  Alias for `optimize/2`.
  """
  @spec compress(input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def compress(input, opts \\ []), do: optimize(input, opts)

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
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      # Encrypt with user and owner passwords
      {:ok, enc} = Qpdf.encrypt(input, user_password: "open", owner_password: "admin")

      # Encrypt with restricted permissions
      {:ok, enc} = Qpdf.encrypt(input, owner_password: "admin", print: :none, extract: false)
  """
  @spec encrypt(input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def encrypt(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      encrypt_args = build_encrypt_args(opts)
      args = [in_file, "--no-warn", "--warning-exit-0"] ++ encrypt_args
      run_qpdf_into(args, opts)
    end)
  end

  @doc """
  Decrypts an encrypted PDF document, optionally using a password.

  Outputs the unencrypted PDF directly to standard output without intermediate disk files.

  ## Options
    * `:password` - password required to decrypt the document
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      {:ok, plain_pdf} = Qpdf.decrypt(encrypted_input, password: "secret")
  """
  @spec decrypt(input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def decrypt(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      password_args =
        case Keyword.get(opts, :password) do
          nil -> []
          pass -> ["--password=#{pass}"]
        end

      args = password_args ++ [in_file, "--no-warn", "--warning-exit-0", "--decrypt"]
      run_qpdf_into(args, opts)
    end)
  end

  @doc """
  Extracts structural metadata, outlines, page details, and object trees as a decoded JSON map.

  Uses `qpdf --json`.
  Decodes the JSON output into native Elixir maps and lists using the standard library `JSON` module.

  ## Options
    * `:version` - JSON schema version (e.g. `1` or `2`, default: `2`)

  ## Returns
    - `{:ok, map}` on success
    - `{:error, any}` on failure
  """
  @spec json(input(), keyword()) :: {:ok, map()} | {:error, any()}
  def json(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      json_arg =
        case Keyword.get(opts, :version) do
          nil -> "--json"
          v -> "--json=#{v}"
        end

      args = @default_opts ++ [json_arg, in_file]

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
  Alias for `json/2`.
  """
  @spec metadata(input(), keyword()) :: {:ok, map()} | {:error, any()}
  def metadata(input, opts \\ []), do: json(input, opts)

  @doc """
  Inspects page geometry, bounding boxes, dimensions, orientation, and paper size.

  Returns width and height in points (1/72 inch), visual orientation (`:portrait`,
  `:landscape`, `:square`), rotation angle (0, 90, 180, 270), and media/crop bounding boxes.

  ## Parameters
    - `input`: The PDF as binary or `{:file, path}`
    - `page_spec`: Target page or pages:
      - `:all` (default) - returns a list of dimensions for all pages
      - integer (e.g. `1`) - returns a single dimension map for that page
      - `Range` or `list` (e.g. `1..3`) - returns a list of dimensions for specified pages

  ## Examples

      # Inspect all pages
      {:ok, pages} = Qpdf.dimensions(pdf)
      # => [%{page: 1, width: 595.28, height: 841.89, orientation: :portrait, paper_size: "A4", ...}]

      # Inspect a single page
      {:ok, page1} = Qpdf.dimensions(pdf, 1)
      page1.orientation #=> :portrait
      page1.paper_size  #=> "A4"
  """
  @spec dimensions(input(), :all | integer() | Range.t() | list()) ::
          {:ok, map() | [map()]} | {:error, any()}
  def dimensions(input, page_spec \\ :all) do
    case json(input, version: 1) do
      {:ok, data} ->
        Qpdf.Dimensions.parse(data, page_spec)

      error ->
        error
    end
  end

  @doc """
  Returns a list of all embedded attachments in the PDF.

  Extracts attachment metadata including key, filename, mime-type, description,
  creation/modification dates, and checksums.

  ## Examples

      {:ok, attachments} = Qpdf.attachments(pdf)
      # => [%{key: "invoice.xml", filename: "invoice.xml", mimetype: "application/xml", ...}]
  """
  @spec attachments(input()) :: {:ok, [map()]} | {:error, any()}
  def attachments(input) do
    case json(input) do
      {:ok, %{"attachments" => atts}} when is_map(atts) ->
        list =
          Enum.map(atts, fn {key, att_data} ->
            stream_info =
              case att_data["streams"] do
                %{"/UF" => uf} -> uf
                %{"/F" => f} -> f
                _ -> %{}
              end

            names = att_data["names"] || %{}

            filename =
              att_data["preferredname"] ||
                names["/UF"] ||
                names["/F"] ||
                key

            %{
              key: key,
              filename: filename,
              mimetype: stream_info["mimetype"],
              description: att_data["description"],
              creation_date: stream_info["creationdate"],
              modification_date: stream_info["modificationdate"],
              checksum: stream_info["checksum"],
              filespec: att_data["filespec"]
            }
          end)

        {:ok, list}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  @doc """
  Extracts the raw contents of an embedded attachment by key.

  Outputs the attachment directly into memory as a binary, or into a file if `:into` is specified.

  ## Options
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      {:ok, xml_bytes} = Qpdf.extract_attachment(pdf, "invoice.xml")
      {:ok, path} = Qpdf.extract_attachment(pdf, "invoice.xml", into: "extracted.xml")
  """
  @spec extract_attachment(input(), String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def extract_attachment(input, key, opts \\ []) when is_binary(key) do
    with_input_path(input, fn in_file ->
      case run_qpdf(["--no-warn", "--warning-exit-0", "--show-attachment=#{key}", in_file]) do
        {output, 0} ->
          deliver_output(output, opts)

        {output, _code} ->
          if String.contains?(output, "not found") do
            {:error, :not_found}
          else
            {:error, output}
          end
      end
    end)
  end

  @doc """
  Embeds an attachment (file or binary data) into the PDF document.

  Outputs the resulting PDF directly to standard output or a destination file.

  ## Options
    * `:key` - unique key for the attachment (defaults to filename or `"attachment"`)
    * `:filename` - displayed filename in PDF viewers (defaults to key or basename)
    * `:mimetype` - MIME type (e.g., `"application/xml"`, `"text/plain"`)
    * `:description` - optional description string
    * `:creation_date` - creation date string
    * `:mod_date` - modification date string
    * `:replace` - boolean, replace existing attachment if key already exists (default `false`)
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      # Embed XML invoice for Factur-X / ZUGFeRD compliance
      {:ok, embedded} = Qpdf.add_attachment(pdf, xml_binary,
        key: "factur-x.xml",
        filename: "factur-x.xml",
        mimetype: "text/xml"
      )

      # Embed a file from disk
      {:ok, embedded} = Qpdf.add_attachment(pdf, {:file, "attachment.csv"}, into: "with_csv.pdf")
  """
  @spec add_attachment(input(), input(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def add_attachment(input, attachment, opts \\ []) do
    case resolve_input(attachment) do
      {:ok, resolved_att} ->
        key =
          Keyword.get(opts, :key) ||
            case resolved_att do
              {:file, p} -> Path.basename(p)
              {:binary, _} -> "attachment"
            end

        filename =
          Keyword.get(opts, :filename) ||
            case resolved_att do
              {:file, p} -> Path.basename(p)
              {:binary, _} -> key
            end

        with_two_inputs(
          input,
          attachment,
          fn in_file, att_file ->
            att_opts = build_attachment_args(key, filename, opts)

            args =
              [in_file | @default_opts] ++ ["--add-attachment", att_file] ++ att_opts ++ ["--"]

            run_qpdf_into(args, opts)
          end,
          {"document.pdf", filename}
        )

      {:error, :enoent} = err ->
        err

      {:error, :invalid_input} ->
        {:error, :invalid_attachment}
    end
  end

  @doc """
  Removes an embedded attachment from the PDF by key.

  Outputs the resulting PDF directly to standard output or a destination file.

  ## Options
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      {:ok, cleaned_pdf} = Qpdf.remove_attachment(pdf, "factur-x.xml")
  """
  @spec remove_attachment(input(), String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def remove_attachment(input, key, opts \\ []) when is_binary(key) do
    with_input_path(input, fn in_file ->
      args = [in_file | @default_opts] ++ ["--remove-attachment=#{key}"]

      case run_qpdf_into(args, opts) do
        {:error, {output, _code}} = err ->
          if String.contains?(output, "not found"), do: {:error, :not_found}, else: err

        other ->
          other
      end
    end)
  end

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
      if(user_pass, do: ["--user-password=#{user_pass}"], else: []) ++
        if owner_pass, do: ["--owner-password=#{owner_pass}"], else: []

    insecure_arg =
      if user_pass && !owner_pass, do: ["--allow-insecure"], else: []

    permission_args =
      [
        case Keyword.get(opts, :print) do
          val when val in [:none, :low, :full] -> ["--print=#{val}"]
          _ -> []
        end,
        case Keyword.get(opts, :modify) do
          val when val in [:none, :assembly, :form, :annotate, :all] -> ["--modify=#{val}"]
          _ -> []
        end,
        case Keyword.get(opts, :extract) do
          true -> ["--extract=y"]
          false -> ["--extract=n"]
          _ -> []
        end,
        case Keyword.get(opts, :annotate) do
          true -> ["--annotate=y"]
          false -> ["--annotate=n"]
          _ -> []
        end,
        if(Keyword.get(opts, :cleartext_metadata), do: ["--cleartext-metadata"], else: [])
      ]
      |> List.flatten()

    ["--encrypt"] ++ pass_args ++ ["--bits=#{bits}"] ++ insecure_arg ++ permission_args
  end

  defp build_optimize_args(opts) do
    stream_arg =
      case Keyword.get(opts, :stream_data, :compress) do
        :compress -> ["--stream-data=compress"]
        :uncompress -> ["--stream-data=uncompress"]
        :preserve -> ["--stream-data=preserve"]
        _ -> ["--stream-data=compress"]
      end

    object_arg =
      case Keyword.get(opts, :object_streams, :generate) do
        :generate -> ["--object-streams=generate"]
        :preserve -> ["--object-streams=preserve"]
        :disable -> ["--object-streams=disable"]
        _ -> ["--object-streams=generate"]
      end

    flate_arg =
      if Keyword.get(opts, :recompress_flate, true), do: ["--recompress-flate"], else: []

    stream_arg ++ object_arg ++ flate_arg
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

  defp run_qpdf_into(args_before_out, opts) do
    case resolve_output_target(opts) do
      {:ok, out_target, target_type} ->
        args = args_before_out ++ ["--", out_target]

        case run_qpdf(args) do
          {output, 0} ->
            case target_type do
              :memory -> {:ok, output}
              {:file, dest_path} -> {:ok, dest_path}
            end

          other ->
            {:error, other}
        end

      {:error, _} = error ->
        error
    end
  end

  defp resolve_output_target(opts) do
    case Keyword.get(opts, :into, :memory) do
      :memory ->
        {:ok, "-", :memory}

      {:file, path} when is_binary(path) ->
        prepare_file_destination(path)

      path when is_binary(path) ->
        prepare_file_destination(path)

      _other ->
        {:error, :invalid_destination}
    end
  end

  defp prepare_file_destination(path) do
    expanded = Path.expand(path)
    File.mkdir_p!(Path.dirname(expanded))
    {:ok, expanded, {:file, expanded}}
  end

  defp do_split_pages(in_file, dir, pages_per_group, mode) do
    out_pattern = Path.join(dir, "page.pdf")

    split_arg =
      if pages_per_group == 1 do
        "--split-pages"
      else
        "--split-pages=#{pages_per_group}"
      end

    args = @default_opts ++ [split_arg, in_file, out_pattern]

    case run_qpdf(args) do
      {_, 0} ->
        files = list_page_files(dir)

        case mode do
          :memory -> {:ok, Enum.map(files, &File.read!/1)}
          :paths -> {:ok, files}
        end

      other ->
        {:error, other}
    end
  end

  defp deliver_output(output, opts) do
    case resolve_output_target(opts) do
      {:ok, "-", :memory} ->
        {:ok, output}

      {:ok, dest_path, {:file, dest_path}} ->
        File.write!(dest_path, output)
        {:ok, dest_path}

      {:error, _} = error ->
        error
    end
  end

  defp apply_layer(input, type, layer_input, opts) do
    with_two_inputs(
      input,
      layer_input,
      fn doc_file, layer_file ->
        flag = if type == :overlay, do: "--overlay", else: "--underlay"
        layer_opts = build_layer_args(opts)
        args = [doc_file | @default_opts] ++ [flag, layer_file] ++ layer_opts ++ ["--"]
        run_qpdf_into(args, opts)
      end,
      {"doc.pdf", "layer.pdf"}
    )
  end

  defp build_layer_args(opts) do
    [
      case Keyword.get(opts, :to) do
        nil -> []
        to_spec -> ["--to=#{format_page_spec(to_spec)}"]
      end,
      case Keyword.get(opts, :from) do
        nil -> []
        from_spec -> ["--from=#{format_page_spec(from_spec)}"]
      end,
      case Keyword.get(opts, :repeat) do
        nil -> []
        true -> ["--repeat=1-z"]
        rep -> ["--repeat=#{format_page_spec(rep)}"]
      end,
      case Keyword.get(opts, :password) do
        nil -> []
        pass -> ["--password=#{pass}"]
      end
    ]
    |> List.flatten()
  end

  defp build_attachment_args(key, filename, opts) do
    [
      ["--key=#{key}", "--filename=#{filename}"],
      if(mt = Keyword.get(opts, :mimetype), do: ["--mimetype=#{mt}"], else: []),
      if(desc = Keyword.get(opts, :description), do: ["--description=#{desc}"], else: []),
      if(cd = Keyword.get(opts, :creation_date), do: ["--creationdate=#{cd}"], else: []),
      if(md = Keyword.get(opts, :mod_date), do: ["--moddate=#{md}"], else: []),
      if(Keyword.get(opts, :replace, false), do: ["--replace"], else: [])
    ]
    |> List.flatten()
  end

  defp resolve_input({:file, path}) when is_binary(path) do
    expanded = Path.expand(path)
    if File.regular?(expanded), do: {:ok, {:file, expanded}}, else: {:error, :enoent}
  end

  defp resolve_input(binary) when is_binary(binary), do: {:ok, {:binary, binary}}
  defp resolve_input(_other), do: {:error, :invalid_input}

  defp with_input_path(input, func) do
    case resolve_input(input) do
      {:ok, {:file, path}} ->
        func.(path)

      {:ok, {:binary, binary}} ->
        with_tmp_dir(fn dir ->
          in_file = Path.join(dir, "original.pdf")
          File.write!(in_file, binary)
          func.(in_file)
        end)

      {:error, _} = error ->
        error
    end
  end

  defp with_two_inputs(input1, input2, func, {name1, name2}) do
    with {:ok, res1} <- resolve_input(input1),
         {:ok, res2} <- resolve_input(input2) do
      case {res1, res2} do
        {{:file, f1}, {:file, f2}} ->
          func.(f1, f2)

        _ ->
          with_tmp_dir(fn dir ->
            f1 = materialize_input(res1, dir, name1)
            f2 = materialize_input(res2, dir, name2)
            func.(f1, f2)
          end)
      end
    end
  end

  defp materialize_input({:file, path}, _dir, _name), do: path

  defp materialize_input({:binary, binary}, dir, name) do
    path = Path.join(dir, name)
    File.write!(path, binary)
    path
  end

  defp with_merged_inputs(inputs, func) do
    parsed =
      Enum.reduce_while(inputs, {:ok, []}, fn
        {{:file, path}, spec}, {:ok, acc} when is_binary(path) ->
          case resolve_input({:file, path}) do
            {:ok, resolved} -> {:cont, {:ok, [{resolved, spec} | acc]}}
            {:error, _} = err -> {:halt, err}
          end

        {binary, spec}, {:ok, acc} when is_binary(binary) ->
          {:cont, {:ok, [{{:binary, binary}, spec} | acc]}}

        input, {:ok, acc} ->
          case resolve_input(input) do
            {:ok, resolved} -> {:cont, {:ok, [{resolved, nil} | acc]}}
            {:error, _} = err -> {:halt, err}
          end
      end)

    case parsed do
      {:ok, reversed} ->
        items = Enum.reverse(reversed)
        has_binary? = Enum.any?(items, fn {{type, _}, _} -> type == :binary end)

        if has_binary? do
          with_tmp_dir(fn dir ->
            file_specs =
              items
              |> Enum.with_index(1)
              |> Enum.map(fn {{res, spec}, idx} ->
                path = materialize_input(res, dir, "input_#{idx}.pdf")
                {path, spec}
              end)

            func.(file_specs)
          end)
        else
          file_specs = Enum.map(items, fn {{:file, path}, spec} -> {path, spec} end)
          func.(file_specs)
        end

      {:error, _} = error ->
        error
    end
  end

  defp with_input_and_output_dir(input, func) do
    case resolve_input(input) do
      {:ok, {:file, path}} ->
        with_tmp_dir(fn dir ->
          func.(path, dir)
        end)

      {:ok, {:binary, binary}} ->
        with_tmp_dir(fn dir ->
          in_file = Path.join(dir, "original.pdf")
          File.write!(in_file, binary)
          func.(in_file, dir)
        end)

      {:error, _} = error ->
        error
    end
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
