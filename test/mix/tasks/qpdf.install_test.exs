defmodule Mix.Tasks.Qpdf.InstallTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "runs mix qpdf.install task" do
    output =
      capture_io(fn ->
        Mix.Tasks.Qpdf.Install.run([])
      end)

    assert output =~ "qpdf is ready at"
  end
end
