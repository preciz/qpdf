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
end
