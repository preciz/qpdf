defmodule Mix.Tasks.Qpdf.Install do
  use Mix.Task

  @shortdoc "Installs the qpdf AppImage binary"

  @moduledoc """
  Installs the qpdf AppImage into priv/native.

      mix qpdf.install
      mix qpdf.install --version 12.3.1
      mix qpdf.install --force
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean, version: :string])
    {:ok, path} = Qpdf.Installer.install(opts)
    Mix.shell().info("qpdf is ready at #{path}")
  end
end
