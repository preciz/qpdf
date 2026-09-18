defmodule Qpdf.Attachments do
  @moduledoc false

  alias Qpdf.CLI
  alias Qpdf.Temp

  @default_opts CLI.default_opts()

  @type input :: binary() | {:file, Path.t()}

  @doc """
  Lists all attachments embedded within the PDF document.
  """
  @spec list(input()) :: {:ok, [map()]} | {:error, any()}
  def list(input) do
    case Qpdf.json(input) do
      {:ok, %{"attachments" => atts}} when is_map(atts) ->
        {:ok, Enum.map(atts, &parse_attachment_entry/1)}

      {:ok, _} ->
        {:ok, []}

      error ->
        error
    end
  end

  @doc """
  Extracts the raw contents of an embedded attachment by key.
  """
  @spec extract(input(), String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def extract(input, key, opts \\ []) when is_binary(key) do
    Temp.with_input_path(input, fn in_file ->
      case CLI.run_stdout(["--no-warn", "--warning-exit-0", "--show-attachment=#{key}", in_file]) do
        {output, 0} ->
          CLI.deliver_output(output, opts)

        {output, _code} ->
          handle_extract_error(output)
      end
    end)
  end

  @doc """
  Embeds an attachment (file or binary data) into the PDF document.
  """
  @spec add(input(), input(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def add(input, attachment, opts \\ []) do
    case Temp.resolve_input(attachment) do
      {:ok, resolved_att} ->
        {key, filename} = resolve_attachment_names(resolved_att, opts)

        Temp.with_two_inputs(
          input,
          attachment,
          fn in_file, att_file ->
            att_opts = build_attachment_args(key, filename, opts)

            args =
              [in_file | @default_opts] ++ ["--add-attachment", att_file] ++ att_opts ++ ["--"]

            CLI.run_into(args, opts)
          end,
          {"document.pdf", "attachment.bin"}
        )

      {:error, :enoent} = err ->
        err

      {:error, :invalid_input} ->
        {:error, :invalid_attachment}
    end
  end

  @doc """
  Removes an embedded attachment from the PDF by key.
  """
  @spec remove(input(), String.t(), keyword()) ::
          {:ok, binary() | Path.t()} | {:error, any()}
  def remove(input, key, opts \\ []) when is_binary(key) do
    Temp.with_input_path(input, fn in_file ->
      args = [in_file | @default_opts] ++ ["--remove-attachment=#{key}"]
      handle_remove_attachment_result(CLI.run_into(args, opts))
    end)
  end

  defp parse_attachment_entry({key, att_data}) do
    stream_info = extract_stream_info(att_data["streams"])
    filename = resolve_attachment_entry_filename(key, att_data)

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
  end

  defp extract_stream_info(%{"/UF" => uf}), do: uf
  defp extract_stream_info(%{"/F" => f}), do: f
  defp extract_stream_info(_), do: %{}

  defp resolve_attachment_entry_filename(key, att_data) do
    names = att_data["names"] || %{}
    att_data["preferredname"] || names["/UF"] || names["/F"] || key
  end

  defp handle_extract_error(output) do
    if String.contains?(output, "not found"), do: {:error, :not_found}, else: {:error, output}
  end

  defp resolve_attachment_names({:file, p}, opts) do
    base = Path.basename(p)
    key = Keyword.get(opts, :key, base)
    filename = Keyword.get(opts, :filename, base)
    {key, filename}
  end

  defp resolve_attachment_names({:binary, _}, opts) do
    key = Keyword.get(opts, :key, "attachment")
    filename = Keyword.get(opts, :filename, key)
    {key, filename}
  end

  defp handle_remove_attachment_result({:error, {output, _code}} = err) do
    if String.contains?(output, "not found"), do: {:error, :not_found}, else: err
  end

  defp handle_remove_attachment_result(other), do: other

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
end
