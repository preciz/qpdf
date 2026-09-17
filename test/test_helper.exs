defmodule Qpdf.TestHelper do
  @test_pdf_zst_path Path.expand("fixtures/qpdf_test.pdf.zst", __DIR__)

  def sample_pdf do
    Application.get_env(:qpdf, :test_sample_pdf) || load_sample_pdf()
  end

  def load_sample_pdf do
    binary =
      if Code.ensure_loaded?(:zstd) and function_exported?(:zstd, :decompress, 1) do
        @test_pdf_zst_path
        |> File.read!()
        |> :zstd.decompress()
        |> IO.iodata_to_binary()
      else
        zstd = System.find_executable("zstd") || raise("No zstd decompression available.")
        {output, 0} = System.cmd(zstd, ["-d", "-c", @test_pdf_zst_path])
        output
      end

    Application.put_env(:qpdf, :test_sample_pdf, binary)
    binary
  end
end

Qpdf.TestHelper.load_sample_pdf()
ExUnit.start()
