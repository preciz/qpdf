defmodule Qpdf.Temp do
  @moduledoc false

  @type input_res :: {:file, Path.t()} | {:binary, binary()}

  @doc """
  Returns the base temporary directory.
  """
  @spec tmp_dir() :: String.t()
  def tmp_dir do
    Application.get_env(:qpdf, :tmp_dir) || System.tmp_dir!()
  end

  @doc """
  Executes `func` within an isolated, newly created temporary directory.
  Guarantees cleanup after execution or on failure.
  """
  @spec with_tmp_dir((Path.t() -> result)) :: result when result: any()
  def with_tmp_dir(func) when is_function(func, 1) do
    with_tmp_dir([], func)
  end

  @spec with_tmp_dir(keyword(), (Path.t() -> result)) :: result when result: any()
  def with_tmp_dir(opts, func) when is_list(opts) and is_function(func, 1) do
    prefix = Keyword.get(opts, :prefix, "qpdf")
    bytes = Keyword.get(opts, :bytes, 4)
    sub_dir = Keyword.get(opts, :sub_dir, true)

    token = Base.encode16(:crypto.strong_rand_bytes(bytes))

    dir =
      if sub_dir do
        Path.join([tmp_dir(), prefix, token])
      else
        Path.join(tmp_dir(), "#{prefix}_#{token}")
      end

    File.mkdir_p!(dir)

    try do
      func.(dir)
    after
      File.rm_rf(dir)
    end
  end

  @doc """
  Moves a file from `src` to `dest`, falling back to copy and remove across
  different filesystems or devices.
  """
  @spec move_file!(Path.t(), Path.t()) :: :ok
  def move_file!(src, dest) do
    case File.rename(src, dest) do
      :ok ->
        :ok

      {:error, _reason} ->
        File.cp!(src, dest)
        File.rm!(src)
    end
  end

  @doc """
  Resolves a given input into either a validated file path or binary.
  """
  @spec resolve_input(any()) :: {:ok, input_res()} | {:error, any()}
  def resolve_input({:file, path}) when is_binary(path) do
    expanded = Path.expand(path)
    if File.regular?(expanded), do: {:ok, {:file, expanded}}, else: {:error, :enoent}
  end

  def resolve_input(binary) when is_binary(binary), do: {:ok, {:binary, binary}}
  def resolve_input(_other), do: {:error, :invalid_input}

  @doc """
  Provides a guaranteed file path for a single input to `func`.
  """
  @spec with_input_path(any(), (Path.t() -> result)) :: result | {:error, any()}
        when result: any()
  def with_input_path(input, func) do
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

  @doc """
  Provides guaranteed file paths for two inputs to `func`.
  """
  @spec with_two_inputs(any(), any(), (Path.t(), Path.t() -> result), {String.t(), String.t()}) ::
          result | {:error, any()}
        when result: any()
  def with_two_inputs(input1, input2, func, names) do
    with {:ok, res1} <- resolve_input(input1),
         {:ok, res2} <- resolve_input(input2) do
      dispatch_two_inputs(res1, res2, func, names)
    end
  end

  defp dispatch_two_inputs({:file, f1}, {:file, f2}, func, _names) do
    func.(f1, f2)
  end

  defp dispatch_two_inputs(res1, res2, func, {name1, name2}) do
    with_tmp_dir(fn dir ->
      f1 = materialize_input(res1, dir, name1)
      f2 = materialize_input(res2, dir, name2)
      func.(f1, f2)
    end)
  end

  @doc """
  Processes multiple inputs for merging, materializing in temporary directory if necessary.
  """
  @spec with_merged_inputs(list(), (list() -> result)) :: result | {:error, any()}
        when result: any()
  def with_merged_inputs(inputs, func) do
    with {:ok, reversed} <- parse_merge_inputs(inputs) do
      dispatch_merged_inputs(Enum.reverse(reversed), func)
    end
  end

  defp parse_merge_inputs(inputs) do
    Enum.reduce_while(inputs, {:ok, []}, fn item, {:ok, acc} ->
      case parse_merge_item(item) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp parse_merge_item({{type, path}, spec}) when type == :file and is_binary(path) do
    case resolve_input({:file, path}) do
      {:ok, resolved} -> {:ok, {resolved, spec}}
      {:error, _} = err -> err
    end
  end

  defp parse_merge_item({binary, spec}) when is_binary(binary) do
    {:ok, {{:binary, binary}, spec}}
  end

  defp parse_merge_item(input) do
    case resolve_input(input) do
      {:ok, resolved} -> {:ok, {resolved, nil}}
      {:error, _} = err -> err
    end
  end

  defp dispatch_merged_inputs(items, func) do
    if Enum.any?(items, fn {{type, _}, _} -> type == :binary end) do
      with_tmp_dir(fn dir ->
        func.(materialize_all_inputs(items, dir))
      end)
    else
      func.(Enum.map(items, fn {{:file, path}, spec} -> {path, spec} end))
    end
  end

  @doc """
  Materializes a resolved input into `dir` with `name` if binary, or returns the existing path.
  """
  @spec materialize_input(input_res(), Path.t(), String.t()) :: Path.t()
  def materialize_input({:file, path}, _dir, _name), do: path

  def materialize_input({:binary, binary}, dir, name) do
    path = Path.join(dir, name)
    File.write!(path, binary)
    path
  end

  @doc """
  Materializes all items into `dir` when needed.
  """
  @spec materialize_all_inputs(list(), Path.t()) :: list()
  def materialize_all_inputs(items, dir) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {{res, spec}, idx} ->
      {materialize_input(res, dir, "input_#{idx}.pdf"), spec}
    end)
  end

  @doc """
  Provides both an input file path and a dedicated output directory to `func`.
  """
  @spec with_input_and_output_dir(any(), (Path.t(), Path.t() -> result)) ::
          result | {:error, any()}
        when result: any()
  def with_input_and_output_dir(input, func) do
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
end
