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

  test "runs mix qpdf.install --if-missing with non-default version does not treat priv/native as installed" do
    priv_apprun = Path.join([Qpdf.Installer.priv_dir(), "native", "AppRun"])
    File.mkdir_p!(Path.dirname(priv_apprun))
    File.touch!(priv_apprun)

    non_installed_version = "99.99.99"

    try do
      # Target path for non-default version should not resolve to priv_apprun
      target_path = Qpdf.Installer.app_run_path(non_installed_version)
      refute target_path == priv_apprun
      refute File.exists?(target_path)
    after
      File.rm(priv_apprun)
    end
  end
end
