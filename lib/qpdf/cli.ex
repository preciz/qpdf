defmodule Qpdf.CLI do
  @moduledoc false

  @default_opts [
    "--no-warn",
    "--warning-exit-0",
    "--decrypt"
  ]

  @type output_target :: :memory | {:file, Path.t()}

  @doc """
  Default CLI flags used across standard qpdf operations.
  """
  @spec default_opts() :: [String.t()]
  def default_opts, do: @default_opts

  @doc """
  Returns the resolved path to the qpdf executable.
  """
  @spec executable() :: String.t()
  def executable do
    Qpdf.Installer.ensure_executable!()
  end

  @doc """
  Runs the qpdf command with given arguments.
  """
  @spec run([String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def run(args, opts \\ [stderr_to_stdout: true]) do
    System.cmd(executable(), args, opts)
  end

  @doc """
  Resolves destination options and executes qpdf, directing output to memory or disk.
  """
  @spec run_into([String.t()], keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def run_into(args_before_out, opts) do
    case resolve_output_target(opts) do
      {:ok, "-", :memory} ->
        execute_into_memory(args_before_out)

      {:ok, dest_path, {:file, dest_path}} ->
        execute_into_file(args_before_out, dest_path)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Delivers raw output according to the `:into` destination option.
  """
  @spec deliver_output(binary(), keyword()) :: {:ok, binary() | Path.t()} | {:error, any()}
  def deliver_output(output, opts) do
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

  @doc """
  Resolves the `:into` option into a CLI destination target and target type.
  """
  @spec resolve_output_target(keyword()) ::
          {:ok, String.t(), output_target()} | {:error, :invalid_destination}
  def resolve_output_target(opts) do
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

  @doc """
  Runs the qpdf command capturing pure standard output without stderr mixing.
  Any standard error output is captured separately in a staging file and only returned on failure.
  """
  @spec run_stdout([String.t()]) :: {binary(), non_neg_integer()}
  def run_stdout(args) do
    case System.find_executable("sh") do
      sh when is_binary(sh) ->
        run_stdout_with_sh(sh, args)

      nil ->
        run(args, stderr_to_stdout: false)
    end
  end

  defp run_stdout_with_sh(sh, args) do
    Qpdf.Temp.with_tmp_dir(fn dir ->
      stderr_file = Path.join(dir, "stderr.txt")

      case System.cmd(sh, ["-c", ~s(exec "$@" 2> "$0"), stderr_file, executable() | args]) do
        {stdout, 0} ->
          {stdout, 0}

        {_stdout, code} ->
          {read_stderr_file(stderr_file), code}
      end
    end)
  end

  defp read_stderr_file(file) do
    if File.exists?(file), do: File.read!(file), else: ""
  end

  defp execute_into_memory(args_before_out) do
    execute_staged(args_before_out, fn staged_target ->
      {:ok, File.read!(staged_target)}
    end)
  end

  defp execute_into_file(args_before_out, dest_path) do
    execute_staged(args_before_out, fn staged_target ->
      Qpdf.Temp.move_file!(staged_target, dest_path)
      {:ok, dest_path}
    end)
  end

  defp execute_staged(args_before_out, on_success) do
    Qpdf.Temp.with_tmp_dir(fn staging_dir ->
      staged_target = Path.join(staging_dir, "staged_output.pdf")

      case run(args_before_out ++ ["--", staged_target]) do
        {_output, 0} ->
          on_success.(staged_target)

        other ->
          {:error, other}
      end
    end)
  end

  defp prepare_file_destination(path) do
    expanded = Path.expand(path)
    File.mkdir_p!(Path.dirname(expanded))
    {:ok, expanded, {:file, expanded}}
  end
end
