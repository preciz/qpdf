defmodule Mix.Tasks.Qpdf.InstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Qpdf.Install

  test "runs mix qpdf.install task" do
    output =
      capture_io(fn ->
        Install.run([])
      end)

    assert output =~ "qpdf is ready at"
  end

  test "runs mix qpdf.install --if-missing when already installed" do
    output =
      capture_io(fn ->
        Install.run(["--if-missing"])
      end)

    assert output =~ "qpdf is already installed at"
  end

  test "runs mix qpdf.install --if-missing --force" do
    output =
      capture_io(fn ->
        Install.run(["--if-missing", "--force"])
      end)

    assert output =~ "qpdf is ready at"
  end

  test "runs mix qpdf.install --if-missing with --version when already installed" do
    version = Qpdf.Installer.version()

    output =
      capture_io(fn ->
        Install.run(["--if-missing", "--version", version])
      end)

    assert output =~ "qpdf is already installed at"
  end
end
