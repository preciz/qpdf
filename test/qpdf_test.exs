defmodule QpdfTest do
  use ExUnit.Case, async: true

  # 14 page PDF compressed with zstd
  @test_pdf_zst_path "test/fixtures/qpdf_test.pdf.zst"

  setup do
    pdf_binary =
      @test_pdf_zst_path
      |> File.read!()
      |> :zstd.decompress()
      |> IO.iodata_to_binary()

    %{pdf_binary: pdf_binary}
  end

  describe "page/2" do
    test "extracts a specific page from a PDF", %{pdf_binary: pdf_binary} do
      {:ok, _page_binary} = Qpdf.page(pdf_binary, 1)
      {:ok, _page_binary} = Qpdf.page(pdf_binary, 14)
    end

    test "returns an error for non-existent page", %{pdf_binary: pdf_binary} do
      assert {:error, _} = Qpdf.page(pdf_binary, 15)
    end
  end

  describe "split/1" do
    test "splits a PDF into individual pages", %{pdf_binary: pdf_binary} do
      {:ok, pages} = Qpdf.split(pdf_binary)

      assert length(pages) == 14
    end

    test "returns an error for non-PDF input" do
      assert {:error, _} = Qpdf.split("not a pdf")
    end
  end

  describe "split_groups/2" do
    test "splits a PDF into groups of at most N pages", %{pdf_binary: pdf_binary} do
      {:ok, groups} = Qpdf.split_groups(pdf_binary, 5)

      # 14 pages in groups of at most 5 → 5 + 5 + 4.
      assert [5, 5, 4] == Enum.map(groups, &page_count!/1)
    end

    test "returns the groups in page order", %{pdf_binary: pdf_binary} do
      {:ok, groups} = Qpdf.split_groups(pdf_binary, 1)
      {:ok, sizes} = Qpdf.page_size_vector(pdf_binary)

      # Compared by size rather than by bytes: two qpdf runs over the same page
      # produce files of identical length that differ in the document /ID.
      assert length(groups) == 14
      assert Enum.map(groups, &byte_size/1) == sizes
    end

    test "returns one group when the PDF is shorter than the group size", %{
      pdf_binary: pdf_binary
    } do
      assert {:ok, [group]} = Qpdf.split_groups(pdf_binary, 100)
      assert page_count!(group) == 14
    end

    test "returns an error for non-PDF input" do
      assert {:error, _} = Qpdf.split_groups("not a pdf", 5)
    end
  end

  describe "page_size_vector/1" do
    test "returns a vector of page sizes", %{pdf_binary: pdf_binary} do
      {:ok, sizes} = Qpdf.page_size_vector(pdf_binary)

      assert length(sizes) == 14
      assert Enum.all?(sizes, &is_integer/1)
      assert Enum.all?(sizes, &(&1 > 0))
    end

    test "returns an error for non-PDF input" do
      assert {:error, _} = Qpdf.page_size_vector("not a pdf")
    end
  end

  describe "page_count/1" do
    test "returns the page count without splitting the PDF", %{pdf_binary: pdf_binary} do
      assert {:ok, 14} = Qpdf.page_count(pdf_binary)
    end

    test "returns an error for non-PDF input" do
      assert {:error, _} = Qpdf.page_count("not a pdf")
    end
  end

  describe "tmp_dir/0" do
    test "returns default tmp dir or configured value" do
      assert Qpdf.tmp_dir() == System.tmp_dir!()

      orig = Application.get_env(:qpdf, :tmp_dir)

      try do
        Application.put_env(:qpdf, :tmp_dir, "/custom/tmp")
        assert Qpdf.tmp_dir() == "/custom/tmp"
      after
        if orig do
          Application.put_env(:qpdf, :tmp_dir, orig)
        else
          Application.delete_env(:qpdf, :tmp_dir)
        end
      end
    end
  end

  defp page_count!(binary) do
    {:ok, count} = Qpdf.page_count(binary)
    count
  end
end
