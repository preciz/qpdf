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

    tmp_dir =
      Path.join(System.tmp_dir!(), "qpdf_test_#{Base.encode16(:crypto.strong_rand_bytes(4))}")

    File.mkdir_p!(tmp_dir)
    pdf_file = Path.join(tmp_dir, "sample.pdf")
    File.write!(pdf_file, pdf_binary)

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    %{pdf_binary: pdf_binary, pdf_file: pdf_file}
  end

  describe "pages/2 and page/2" do
    test "extracts a single page with integer", %{pdf_binary: pdf_binary} do
      {:ok, page_binary} = Qpdf.pages(pdf_binary, 1)
      assert page_count!(page_binary) == 1

      {:ok, page14_binary} = Qpdf.page(pdf_binary, 14)
      assert page_count!(page14_binary) == 1
    end

    test "extracts a page range with Range struct", %{pdf_binary: pdf_binary} do
      {:ok, chunk} = Qpdf.pages(pdf_binary, 1..3)
      assert page_count!(chunk) == 3
    end

    test "extracts pages with list", %{pdf_binary: pdf_binary} do
      {:ok, chunk} = Qpdf.pages(pdf_binary, [1, 3, 5])
      assert page_count!(chunk) == 3
    end

    test "extracts pages with qpdf string syntax", %{pdf_binary: pdf_binary} do
      {:ok, chunk} = Qpdf.pages(pdf_binary, "1-3")
      assert page_count!(chunk) == 3
    end

    test "returns an error for non-existent page", %{pdf_binary: pdf_binary} do
      assert {:error, _} = Qpdf.pages(pdf_binary, 15)
    end

    test "extracts pages with {:file, path}", %{pdf_file: pdf_file} do
      {:ok, page_binary} = Qpdf.pages({:file, pdf_file}, 1)
      assert page_count!(page_binary) == 1

      {:ok, range_binary} = Qpdf.page({:file, pdf_file}, 1..3)
      assert page_count!(range_binary) == 3
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.pages({:file, "/non/existent/file.pdf"}, 1)
    end

    test "returns :invalid_input for invalid input type" do
      assert {:error, :invalid_input} = Qpdf.pages(12345, 1)
    end
  end

  describe "split_pages/2" do
    test "splits into individual pages by default", %{pdf_binary: pdf_binary} do
      {:ok, pages} = Qpdf.split_pages(pdf_binary)
      assert length(pages) == 14
      assert Enum.all?(pages, fn p -> page_count!(p) == 1 end)
    end

    test "splits into groups of at most N pages", %{pdf_binary: pdf_binary} do
      {:ok, groups} = Qpdf.split_pages(pdf_binary, 5)
      assert [5, 5, 4] == Enum.map(groups, &page_count!/1)
    end

    test "splits with {:file, path}", %{pdf_file: pdf_file} do
      {:ok, pages} = Qpdf.split_pages({:file, pdf_file})
      assert length(pages) == 14
      assert Enum.all?(pages, fn p -> page_count!(p) == 1 end)

      {:ok, groups} = Qpdf.split_pages({:file, pdf_file}, 5)
      assert [5, 5, 4] == Enum.map(groups, &page_count!/1)
    end

    test "returns an error for non-PDF input" do
      assert {:error, _} = Qpdf.split_pages("not a pdf", 5)
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.split_pages({:file, "/non/existent/file.pdf"})
    end
  end

  describe "split/1 and split_groups/2 (backward compatibility)" do
    test "split/1 returns tagged tuples", %{pdf_binary: pdf_binary} do
      {:ok, pages} = Qpdf.split(pdf_binary)
      assert length(pages) == 14
      assert {1, _page1} = List.first(pages)
      assert {14, _page14} = List.last(pages)
    end

    test "split/1 with {:file, path}", %{pdf_file: pdf_file} do
      {:ok, pages} = Qpdf.split({:file, pdf_file})
      assert length(pages) == 14
      assert {1, _page1} = List.first(pages)
      assert {14, _page14} = List.last(pages)
    end

    test "split/1 returns error for non-PDF input" do
      assert {:error, _} = Qpdf.split("not a pdf")
    end

    test "split_groups/2 delegates to split_pages/2", %{pdf_binary: pdf_binary} do
      {:ok, groups} = Qpdf.split_groups(pdf_binary, 5)
      assert [5, 5, 4] == Enum.map(groups, &page_count!/1)
    end
  end

  describe "page_count/1 and show_npages/1" do
    test "returns the page count without splitting the PDF", %{pdf_binary: pdf_binary} do
      assert {:ok, 14} = Qpdf.page_count(pdf_binary)
      assert {:ok, 14} = Qpdf.show_npages(pdf_binary)
    end

    test "returns the page count with {:file, path}", %{pdf_file: pdf_file} do
      assert {:ok, 14} = Qpdf.page_count({:file, pdf_file})
      assert {:ok, 14} = Qpdf.show_npages({:file, pdf_file})
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.page_count({:file, "/non/existent/file.pdf"})
    end

    test "returns an error for non-PDF input" do
      assert {:error, _} = Qpdf.page_count("not a pdf")
    end
  end

  describe "encrypted?/1" do
    test "returns false for unencrypted PDF", %{pdf_binary: pdf_binary, pdf_file: pdf_file} do
      assert Qpdf.encrypted?(pdf_binary) == false
      assert Qpdf.encrypted?({:file, pdf_file}) == false
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.encrypted?({:file, "/non/existent/file.pdf"})
    end

    test "returns true for encrypted PDF", %{pdf_binary: pdf_binary} do
      dir =
        Path.join(System.tmp_dir!(), "enc_test_#{Base.encode16(:crypto.strong_rand_bytes(4))}")

      File.mkdir_p!(dir)
      in_file = Path.join(dir, "in.pdf")
      out_file = Path.join(dir, "out.pdf")
      File.write!(in_file, pdf_binary)

      try do
        {_, 0} =
          System.cmd(Qpdf.executable_path(), [
            in_file,
            "--encrypt",
            "user",
            "owner",
            "256",
            "--",
            out_file
          ])

        enc_bin = File.read!(out_file)
        assert Qpdf.encrypted?(enc_bin) == true
        assert Qpdf.encrypted?({:file, out_file}) == true
      after
        File.rm_rf(dir)
      end
    end
  end

  describe "check/1" do
    test "returns :ok for valid PDF", %{pdf_binary: pdf_binary, pdf_file: pdf_file} do
      assert :ok = Qpdf.check(pdf_binary)
      assert :ok = Qpdf.check({:file, pdf_file})
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.check({:file, "/non/existent/file.pdf"})
    end

    test "returns error for corrupt or non-PDF input" do
      assert {:error, _} = Qpdf.check("not a pdf")
    end
  end

  describe "page_size_vector/1" do
    test "returns a vector of page sizes", %{pdf_binary: pdf_binary, pdf_file: pdf_file} do
      {:ok, sizes} = Qpdf.page_size_vector(pdf_binary)

      assert length(sizes) == 14
      assert Enum.all?(sizes, &is_integer/1)
      assert Enum.all?(sizes, &(&1 > 0))

      {:ok, file_sizes} = Qpdf.page_size_vector({:file, pdf_file})
      assert file_sizes == sizes
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.page_size_vector({:file, "/non/existent/file.pdf"})
    end

    test "returns an error for non-PDF input" do
      assert {:error, _} = Qpdf.page_size_vector("not a pdf")
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
