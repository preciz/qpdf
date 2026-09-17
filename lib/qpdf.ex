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

  alias Qpdf.Attachments
  alias Qpdf.CLI
  alias Qpdf.Encryption
  alias Qpdf.Installer
  alias Qpdf.Temp

  @default_opts CLI.default_opts()

  @type input :: binary() | {:file, Path.t()}

  @doc """
  Returns the version of the installed qpdf executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available or cannot be run.

  ## Examples

      case Qpdf.bin_version() do
        {:ok, version} -> IO.puts("Running qpdf \#{version}")
        :error -> IO.puts("qpdf is not installed")
      end
  """
  @spec bin_version() :: {:ok, String.t()} | :error
  defdelegate bin_version, to: Installer

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
        with_input_path(input, fn in_file ->
          do_split_pages(in_file, nil, pages_per_group, :memory)
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
        {output, 0} -> parse_page_count(output)
        other -> {:error, other}
      end
    end)
  end

  defp parse_page_count(output) do
    case output |> String.trim() |> Integer.parse() do
      {count, ""} when count > 0 -> {:ok, count}
      _ -> {:error, {:unexpected_output, output}}
    end
  end

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
        {output, 0} -> parse_linearized(output)
        other -> {:error, other}
      end
    end)
  end

  defp parse_linearized(output) do
    cond do
      String.contains?(output, "no linearization errors") -> true
      String.contains?(output, "not linearized") -> false
      true -> false
    end
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
  Optimizes raster images within a PDF document using DCT (JPEG) compression.

  Combines `qpdf --optimize-images` with optional filtering by image dimensions,
  JPEG quality levels, inline image handling, and unreferenced resource cleanup.

  Outputs the optimized PDF directly to standard output or a destination file.

  ## Options
    * `:jpeg_quality` - integer from `0` (lowest) to `100` (highest)
    * `:min_width` - minimum image width in pixels to optimize
    * `:min_height` - minimum image height in pixels to optimize
    * `:min_area` - minimum image area (width * height in pixels) to optimize
    * `:keep_inline_images` - boolean, if `true`, exclude inline images from optimization (default `false`)
    * `:externalize_inline_images` - boolean, convert inline images to regular image objects (default `false`)
    * `:remove_unreferenced` - boolean, remove unreferenced fonts/images from page resource dictionaries (default `false`)
    * `:into` - destination: `:memory` (default) or `path` / `{:file, path}`

  ## Examples

      # Basic image optimization
      {:ok, optimized_pdf} = Qpdf.optimize_images(pdf)

      # Target images with quality and minimum area thresholds
      {:ok, compact_pdf} = Qpdf.optimize_images(pdf,
        jpeg_quality: 80,
        min_area: 10_000,
        remove_unreferenced: true,
        into: "compact.pdf"
      )
  """
  @spec optimize_images(input(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def optimize_images(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      opt_args = build_image_optimize_args(opts)
      args = [in_file | @default_opts] ++ opt_args
      run_qpdf_into(args, opts)
    end)
  end

  @doc """
  Encrypts a PDF document with password protection and access permissions.

  Outputs the encrypted PDF directly to standard output without intermediate disk files.

  ## Options
    * `:user_password` - password required to open the PDF (default: `""`)
    * `:owner_password` - password required to modify permissions (default: `""`)
    * `:key_length` - encryption key length: `40` (requires `allow_weak_crypto: true`), `128`, or `256` (default: `256`)
    * `:use_aes` - boolean, use AES encryption for 128-bit keys (default: `true`)
    * `:allow_weak_crypto` - boolean, allow writing insecure/legacy encryption (required for `key_length: 40` or 128-bit RC4, default: `false`)
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
    with {:ok, encrypt_args} <- Encryption.build_encrypt_args(opts) do
      with_input_path(input, fn in_file ->
        args = [in_file, "--no-warn", "--warning-exit-0"] ++ encrypt_args
        run_qpdf_into(args, opts)
      end)
    end
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
  Checks whether the given password is valid to open the encrypted PDF.

  Uses `qpdf --requires-password`.
  Returns `true` if the password is valid (user or owner password),
  or `false` if the password is wrong or the document is not encrypted.

  ## Parameters
    - `input`: The PDF as a binary or `{:file, path}`
    - `password`: The password string to test

  ## Examples

      Qpdf.password_valid?(pdf, "secret") #=> true
      Qpdf.password_valid?(pdf, "wrong")  #=> false
  """
  @spec password_valid?(input(), String.t()) :: boolean() | {:error, any()}
  def password_valid?(input, password) when is_binary(password) do
    with_input_path(input, fn in_file ->
      case run_qpdf(["--no-warn", "--password=#{password}", "--requires-password", in_file]) do
        {_, 3} -> true
        {"", 0} -> false
        {"", 2} -> false
        other -> {:error, other}
      end
    end)
  end

  def password_valid?(_input, _password), do: {:error, :invalid_password}

  @doc """
  Checks whether the given PDF requires a password to open.

  Returns `true` if a user password is required to open the document,
  or `false` if the document is unencrypted or opens with an empty user password.

  ## Examples

      Qpdf.requires_password?(pdf) #=> true | false
  """
  @spec requires_password?(input()) :: boolean() | {:error, any()}
  def requires_password?(input) do
    with_input_path(input, fn in_file ->
      case run_qpdf(["--no-warn", "--requires-password", in_file]) do
        {"", 0} -> true
        {"", 2} -> false
        {_, 3} -> false
        other -> {:error, other}
      end
    end)
  end

  @doc """
  Returns detailed encryption parameters, cipher methods, and access permissions for a PDF.

  Uses `qpdf --show-encryption`.
  Returns `{:ok, %{encrypted: false}}` if the document is not encrypted.
  If encrypted, returns `{:ok, map()}` with encryption revision (`:r`), permission integer (`:p`),
  cipher methods (`:stream_method`, `:string_method`, `:file_method`), permissions map,
  and password details if supplied or recoverable.

  ## Options
    * `:password` - optional password to test against the document

  ## Examples

      # Inspect an encrypted PDF
      {:ok, info} = Qpdf.encryption_info(pdf)
      info.encrypted     #=> true
      info.r             #=> 6 (Revision)
      info.stream_method #=> "AESv3"
      info.permissions.print_high #=> false

      # Test password type
      {:ok, info} = Qpdf.encryption_info(pdf, password: "admin")
      info.password_matched #=> :owner
  """
  @spec encryption_info(input(), keyword()) :: {:ok, map()} | {:error, any()}
  def encryption_info(input, opts \\ []) do
    with_input_path(input, fn in_file ->
      pass_arg =
        case Keyword.get(opts, :password) do
          nil -> []
          pass -> ["--password=#{pass}"]
        end

      args = ["--no-warn"] ++ pass_arg ++ ["--show-encryption", in_file]

      case run_qpdf(args) do
        {output, 0} -> Encryption.parse_info(output)
        other -> {:error, other}
      end
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
        {output, 0} -> decode_json_output(output)
        other -> {:error, other}
      end
    end)
  end

  defp decode_json_output(output) do
    case JSON.decode(output) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

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
  defdelegate attachments(input), to: Attachments, as: :list

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
  defdelegate extract_attachment(input, key, opts \\ []), to: Attachments, as: :extract

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
  defdelegate add_attachment(input, attachment, opts \\ []), to: Attachments, as: :add

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
  defdelegate remove_attachment(input, key, opts \\ []), to: Attachments, as: :remove

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
  defdelegate executable_path(), to: CLI, as: :executable

  @doc """
  Returns the base temporary directory used for PDF operations.

  Defaults to `System.tmp_dir!()`, but can be configured in your application:

      config :qpdf, tmp_dir: "/path/to/custom/tmp"
  """
  @spec tmp_dir() :: String.t()
  defdelegate tmp_dir(), to: Temp

  defp format_page_spec(%Range{first: first, last: last, step: step}) when step in [1, -1] do
    "#{first}-#{last}"
  end

  defp format_page_spec(%Range{} = range), do: Enum.join(range, ",")
  defp format_page_spec(pages) when is_list(pages), do: Enum.join(pages, ",")
  defp format_page_spec(spec), do: to_string(spec)

  defp format_rotate_arg(angle, spec) when spec in [:all, nil] do
    "--rotate=#{angle}"
  end

  defp format_rotate_arg(angle, spec) do
    "--rotate=#{angle}:#{format_page_spec(spec)}"
  end

  defp build_optimize_args(opts) do
    stream_arg = stream_data_arg(Keyword.get(opts, :stream_data, :compress))
    object_arg = object_streams_arg(Keyword.get(opts, :object_streams, :generate))

    flate_arg =
      if Keyword.get(opts, :recompress_flate, true), do: ["--recompress-flate"], else: []

    stream_arg ++ object_arg ++ flate_arg
  end

  defp stream_data_arg(:uncompress), do: ["--stream-data=uncompress"]
  defp stream_data_arg(:preserve), do: ["--stream-data=preserve"]
  defp stream_data_arg(_compress), do: ["--stream-data=compress"]

  defp object_streams_arg(:preserve), do: ["--object-streams=preserve"]
  defp object_streams_arg(:disable), do: ["--object-streams=disable"]
  defp object_streams_arg(_generate), do: ["--object-streams=generate"]

  defp build_image_optimize_args(opts) do
    [
      ["--optimize-images"],
      jpeg_quality_arg(Keyword.get(opts, :jpeg_quality)),
      min_dimension_arg("--oi-min-width", Keyword.get(opts, :min_width)),
      min_dimension_arg("--oi-min-height", Keyword.get(opts, :min_height)),
      min_dimension_arg("--oi-min-area", Keyword.get(opts, :min_area)),
      if(Keyword.get(opts, :keep_inline_images), do: ["--keep-inline-images"], else: []),
      if(Keyword.get(opts, :externalize_inline_images),
        do: ["--externalize-inline-images"],
        else: []
      ),
      if(Keyword.get(opts, :remove_unreferenced),
        do: ["--remove-unreferenced-resources=yes"],
        else: []
      )
    ]
    |> List.flatten()
  end

  defp jpeg_quality_arg(quality) when is_integer(quality) and quality in 0..100 do
    ["--jpeg-quality=#{quality}"]
  end

  defp jpeg_quality_arg(_), do: []

  defp min_dimension_arg(flag, val) when is_integer(val) and val > 0 do
    ["#{flag}=#{val}"]
  end

  defp min_dimension_arg(_flag, _), do: []

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

  defp run_qpdf(args, opts \\ [stderr_to_stdout: true]), do: CLI.run(args, opts)
  defp run_qpdf_into(args, opts), do: CLI.run_into(args, opts)

  defp do_split_pages(in_file, dest_dir, pages_per_group, mode) do
    with_tmp_dir(fn staging_dir ->
      out_pattern = Path.join(staging_dir, "page.pdf")
      split_arg = split_pages_arg(pages_per_group)
      args = @default_opts ++ [split_arg, in_file, out_pattern]

      case run_qpdf(args) do
        {_, 0} ->
          format_split_output(list_page_files(staging_dir), dest_dir, mode)

        other ->
          {:error, other}
      end
    end)
  end

  defp split_pages_arg(1), do: "--split-pages"
  defp split_pages_arg(pages_per_group), do: "--split-pages=#{pages_per_group}"

  defp format_split_output(staged_files, _dest_dir, :memory) do
    {:ok, Enum.map(staged_files, &File.read!/1)}
  end

  defp format_split_output(staged_files, dest_dir, :paths) do
    dest_files =
      Enum.map(staged_files, fn staged_file ->
        dest_path = Path.join(dest_dir, Path.basename(staged_file))
        Temp.move_file!(staged_file, dest_path)
        dest_path
      end)

    {:ok, dest_files}
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
      spec_layer_arg("--to", Keyword.get(opts, :to)),
      spec_layer_arg("--from", Keyword.get(opts, :from)),
      repeat_layer_arg(Keyword.get(opts, :repeat)),
      pass_layer_arg(Keyword.get(opts, :password))
    ]
    |> List.flatten()
  end

  defp spec_layer_arg(_flag, nil), do: []
  defp spec_layer_arg(flag, spec), do: ["#{flag}=#{format_page_spec(spec)}"]

  defp repeat_layer_arg(nil), do: []
  defp repeat_layer_arg(true), do: ["--repeat=1-z"]
  defp repeat_layer_arg(rep), do: ["--repeat=#{format_page_spec(rep)}"]

  defp pass_layer_arg(nil), do: []
  defp pass_layer_arg(pass), do: ["--password=#{pass}"]

  defp with_input_path(input, func), do: Temp.with_input_path(input, func)
  defp with_two_inputs(i1, i2, func, names), do: Temp.with_two_inputs(i1, i2, func, names)
  defp with_merged_inputs(inputs, func), do: Temp.with_merged_inputs(inputs, func)
  defp with_input_and_output_dir(input, func), do: Temp.with_input_and_output_dir(input, func)
  defp with_tmp_dir(func), do: Temp.with_tmp_dir(func)
end
