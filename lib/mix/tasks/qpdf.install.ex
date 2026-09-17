defmodule Mix.Tasks.Qpdf.Install do
  use Mix.Task

  @shortdoc "Installs the qpdf AppImage binary"

  @moduledoc """
  Installs the qpdf AppImage into priv/native or _build.

      mix qpdf.install
      mix qpdf.install --version 12.3.1
      mix qpdf.install --force
      mix qpdf.install --if-missing
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [force: :boolean, version: :string, if_missing: :boolean]
      )

    if opts[:if_missing] && !opts[:force] && executable_present?(opts) do
      path = resolved_path(opts)
      Mix.shell().info("qpdf is already installed at #{path}")
    else
      {:ok, path} = Qpdf.Installer.install(opts)
      Mix.shell().info("qpdf is ready at #{path}")
    end
  end

  defp executable_present?(opts) do
    case Keyword.get(opts, :version) do
      nil ->
        match?({:ok, _}, Qpdf.Installer.find_executable())

      version ->
        File.exists?(Qpdf.Installer.app_run_path(version))
    end
  end

  defp resolved_path(opts) do
    case Keyword.get(opts, :version) do
      nil ->
        case Qpdf.Installer.find_executable() do
          {:ok, path} -> path
          _ -> Qpdf.Installer.app_run_path()
        end

      version ->
        Qpdf.Installer.app_run_path(version)
    end
  end
end
