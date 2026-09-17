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
      assert {:error, :invalid_input} = Qpdf.pages(12_345, 1)
    end
  end

  describe "merge/1" do
    test "merges multiple binaries", %{pdf_binary: pdf_binary} do
      {:ok, merged} = Qpdf.merge([pdf_binary, pdf_binary])
      assert page_count!(merged) == 28
    end

    test "merges multiple {:file, path} inputs", %{pdf_file: pdf_file} do
      {:ok, merged} = Qpdf.merge([{:file, pdf_file}, {:file, pdf_file}])
      assert page_count!(merged) == 28
    end

    test "merges mixed binary and {:file, path} inputs with page ranges", %{
      pdf_binary: pdf_binary,
      pdf_file: pdf_file
    } do
      {:ok, merged} = Qpdf.merge([{{:file, pdf_file}, 1..2}, {pdf_binary, "1-3"}])
      assert page_count!(merged) == 5
    end

    test "returns :empty_inputs for empty list" do
      assert {:error, :empty_inputs} = Qpdf.merge([])
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.merge([{:file, "/non/existent.pdf"}])
    end

    test "returns :invalid_input for invalid items" do
      assert {:error, :invalid_input} = Qpdf.merge([12_345])
    end
  end

  describe "rotate/2 and rotate/3" do
    test "rotates all pages by 90 degrees", %{pdf_binary: pdf_binary} do
      {:ok, rotated} = Qpdf.rotate(pdf_binary, 90)
      assert page_count!(rotated) == 14
      assert :ok = Qpdf.check(rotated)
    end

    test "rotates a specific page by 180 degrees", %{pdf_binary: pdf_binary} do
      {:ok, rotated} = Qpdf.rotate(pdf_binary, 180, 2)
      assert page_count!(rotated) == 14
      assert :ok = Qpdf.check(rotated)
    end

    test "rotates a page range with {:file, path}", %{pdf_file: pdf_file} do
      {:ok, rotated} = Qpdf.rotate({:file, pdf_file}, 270, 1..3)
      assert page_count!(rotated) == 14
      assert :ok = Qpdf.check(rotated)
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.rotate({:file, "/non/existent.pdf"}, 90)
    end

    test "returns :invalid_input for invalid input type" do
      assert {:error, :invalid_input} = Qpdf.rotate(12_345, 90)
    end

    test "returns error for invalid rotation angle", %{pdf_binary: pdf_binary} do
      assert {:error, _} = Qpdf.rotate(pdf_binary, 45)
    end
  end

  describe "overlay/3 and underlay/3" do
    test "overlays a page across all pages with repeat: true", %{pdf_binary: pdf_binary} do
      {:ok, page1} = Qpdf.pages(pdf_binary, 1)
      {:ok, overlaid} = Qpdf.overlay(pdf_binary, page1, repeat: true)
      assert page_count!(overlaid) == 14
      assert :ok = Qpdf.check(overlaid)
    end

    test "overlays on specific page only", %{pdf_binary: pdf_binary} do
      {:ok, page1} = Qpdf.pages(pdf_binary, 1)
      {:ok, overlaid} = Qpdf.overlay(pdf_binary, page1, to: 1, from: 1)
      assert page_count!(overlaid) == 14
      assert :ok = Qpdf.check(overlaid)

      {:ok, overlaid2} = Qpdf.overlay(pdf_binary, page1, repeat: "1")
      assert page_count!(overlaid2) == 14
      assert :ok = Qpdf.check(overlaid2)
    end

    test "underlays with {:file, path}", %{pdf_file: pdf_file, pdf_binary: pdf_binary} do
      {:ok, page1} = Qpdf.pages(pdf_binary, 1)
      tmp_bg = Path.join(System.tmp_dir!(), "bg.pdf")
      File.write!(tmp_bg, page1)

      try do
        {:ok, underlaid} = Qpdf.underlay({:file, pdf_file}, {:file, tmp_bg}, repeat: true)
        assert page_count!(underlaid) == 14
        assert :ok = Qpdf.check(underlaid)
      after
        File.rm(tmp_bg)
      end
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.overlay({:file, "/non/existent.pdf"}, "binary")
      assert {:error, :enoent} = Qpdf.overlay("binary", {:file, "/non/existent.pdf"})
      assert {:error, :enoent} = Qpdf.underlay({:file, "/non/existent.pdf"}, "binary")
    end

    test "returns :invalid_input for invalid input" do
      assert {:error, :invalid_input} = Qpdf.overlay(12_345, "binary")
      assert {:error, :invalid_input} = Qpdf.underlay("binary", 12_345)
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

  describe "linearize/1 and linearized?/1" do
    test "checks non-linearized PDF", %{pdf_binary: pdf_binary, pdf_file: pdf_file} do
      assert Qpdf.linearized?(pdf_binary) == false
      assert Qpdf.linearized?({:file, pdf_file}) == false
    end

    test "linearizes a PDF and verifies it is linearized", %{
      pdf_binary: pdf_binary,
      pdf_file: pdf_file
    } do
      {:ok, lin_bin} = Qpdf.linearize(pdf_binary)
      assert Qpdf.linearized?(lin_bin) == true
      assert page_count!(lin_bin) == 14

      {:ok, lin_file} = Qpdf.linearize({:file, pdf_file})
      assert Qpdf.linearized?(lin_file) == true
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.linearized?({:file, "/non/existent.pdf"})
      assert {:error, :enoent} = Qpdf.linearize({:file, "/non/existent.pdf"})
    end

    test "returns :invalid_input for invalid input" do
      assert {:error, :invalid_input} = Qpdf.linearized?(12_345)
      assert {:error, :invalid_input} = Qpdf.linearize(12_345)
    end
  end

  describe "optimize/2 and compress/1" do
    test "optimizes and compresses PDF binary", %{pdf_binary: pdf_binary} do
      {:ok, opt} = Qpdf.optimize(pdf_binary)
      assert byte_size(opt) < byte_size(pdf_binary)
      assert page_count!(opt) == 14
      assert :ok = Qpdf.check(opt)

      {:ok, comp} = Qpdf.compress(pdf_binary)
      assert byte_size(comp) < byte_size(pdf_binary)
      assert page_count!(comp) == 14
    end

    test "optimizes with options", %{pdf_binary: pdf_binary} do
      {:ok, opt1} =
        Qpdf.optimize(pdf_binary,
          stream_data: :compress,
          object_streams: :generate,
          recompress_flate: true
        )

      assert page_count!(opt1) == 14
      assert :ok = Qpdf.check(opt1)

      {:ok, opt2} =
        Qpdf.optimize(pdf_binary,
          stream_data: :uncompress,
          object_streams: :preserve,
          recompress_flate: false
        )

      assert page_count!(opt2) == 14

      {:ok, opt3} =
        Qpdf.optimize(pdf_binary,
          stream_data: :preserve,
          object_streams: :disable
        )

      assert page_count!(opt3) == 14
    end

    test "optimizes with {:file, path}", %{pdf_file: pdf_file, pdf_binary: pdf_binary} do
      {:ok, opt} = Qpdf.optimize({:file, pdf_file})
      assert byte_size(opt) < byte_size(pdf_binary)
      assert page_count!(opt) == 14
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.optimize({:file, "/non/existent.pdf"})
      assert {:error, :enoent} = Qpdf.compress({:file, "/non/existent.pdf"})
    end

    test "returns :invalid_input for invalid input" do
      assert {:error, :invalid_input} = Qpdf.optimize(12_345)
      assert {:error, :invalid_input} = Qpdf.compress(12_345)
    end
  end

  describe "encrypt/2 and decrypt/2" do
    test "encrypts and decrypts with passwords", %{pdf_binary: pdf_binary} do
      {:ok, enc} =
        Qpdf.encrypt(pdf_binary,
          user_password: "user",
          owner_password: "owner",
          key_length: 256,
          print: :none,
          modify: :none,
          extract: false,
          annotate: false,
          cleartext_metadata: true
        )

      assert Qpdf.encrypted?(enc) == true

      # Decrypt with correct password
      {:ok, dec} = Qpdf.decrypt(enc, password: "user")
      assert Qpdf.encrypted?(dec) == false
      assert page_count!(dec) == 14

      # Decrypt with wrong password fails
      assert {:error, _} = Qpdf.decrypt(enc, password: "wrong")
    end

    test "encrypts with user password only (insecure)", %{pdf_binary: pdf_binary} do
      {:ok, enc} = Qpdf.encrypt(pdf_binary, user_password: "user123")
      assert Qpdf.encrypted?(enc) == true

      {:ok, dec} = Qpdf.decrypt(enc, password: "user123")
      assert Qpdf.encrypted?(dec) == false
    end

    test "encrypts and decrypts with {:file, path}", %{pdf_file: pdf_file} do
      {:ok, enc} =
        Qpdf.encrypt({:file, pdf_file}, user_password: "fileuser", owner_password: "fileowner")

      assert Qpdf.encrypted?(enc) == true

      tmp_enc = Path.join(System.tmp_dir!(), "enc_unit_test.pdf")
      File.write!(tmp_enc, enc)

      try do
        {:ok, dec} = Qpdf.decrypt({:file, tmp_enc}, password: "fileuser")
        assert Qpdf.encrypted?(dec) == false
        assert page_count!(dec) == 14
      after
        File.rm(tmp_enc)
      end
    end

    test "encrypts with custom permissions", %{pdf_binary: pdf_binary} do
      {:ok, enc} =
        Qpdf.encrypt(pdf_binary,
          user_password: "open",
          owner_password: "admin",
          print: :full,
          modify: :all,
          extract: true,
          annotate: true,
          cleartext_metadata: true
        )

      assert Qpdf.encrypted?(enc) == true
      {:ok, dec} = Qpdf.decrypt(enc, password: "open")
      assert Qpdf.encrypted?(dec) == false
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.encrypt({:file, "/non/existent.pdf"})
      assert {:error, :enoent} = Qpdf.decrypt({:file, "/non/existent.pdf"})
    end

    test "returns :invalid_input for invalid input" do
      assert {:error, :invalid_input} = Qpdf.encrypt(12_345)
      assert {:error, :invalid_input} = Qpdf.decrypt(12_345)
    end
  end

  describe "json/1 and metadata/1" do
    test "decodes JSON structure from binary", %{pdf_binary: pdf_binary} do
      {:ok, data} = Qpdf.json(pdf_binary)
      assert is_map(data)
      assert Map.has_key?(data, "version")
      assert Map.has_key?(data, "pages")
      assert length(data["pages"]) == 14

      {:ok, meta} = Qpdf.metadata(pdf_binary)
      assert meta == data
    end

    test "decodes JSON structure with {:file, path}", %{pdf_file: pdf_file} do
      {:ok, data} = Qpdf.json({:file, pdf_file})
      assert is_map(data)
      assert length(data["pages"]) == 14
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.json({:file, "/non/existent.pdf"})
      assert {:error, :enoent} = Qpdf.metadata({:file, "/non/existent.pdf"})
    end

    test "returns :invalid_input for invalid input" do
      assert {:error, :invalid_input} = Qpdf.json(12_345)
      assert {:error, :invalid_input} = Qpdf.metadata(12_345)
    end

    test "returns error for non-PDF input" do
      assert {:error, _} = Qpdf.json("not a pdf")
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

  describe ":into destination option" do
    test "writes pages directly to file", %{pdf_binary: pdf_binary, pdf_file: pdf_file} do
      dest1 =
        Path.join(
          System.tmp_dir!(),
          "out_pages_1_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf"
        )

      dest2 =
        Path.join(
          System.tmp_dir!(),
          "out_pages_2_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf"
        )

      on_exit(fn ->
        File.rm(dest1)
        File.rm(dest2)
      end)

      assert {:ok, ^dest1} = Qpdf.pages(pdf_binary, 1..2, into: dest1)
      assert File.exists?(dest1)
      assert page_count!({:file, dest1}) == 2

      assert {:ok, ^dest2} = Qpdf.page({:file, pdf_file}, 1, into: {:file, dest2})
      assert File.exists?(dest2)
      assert page_count!({:file, dest2}) == 1
    end

    test "merges directly to file", %{pdf_file: pdf_file} do
      dest =
        Path.join(
          System.tmp_dir!(),
          "out_merged_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf"
        )

      on_exit(fn -> File.rm(dest) end)

      assert {:ok, ^dest} = Qpdf.merge([{:file, pdf_file}, {:file, pdf_file}], into: dest)
      assert File.exists?(dest)
      assert page_count!({:file, dest}) == 28
    end

    test "rotates directly to file", %{pdf_file: pdf_file} do
      dest =
        Path.join(
          System.tmp_dir!(),
          "out_rotated_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf"
        )

      on_exit(fn -> File.rm(dest) end)

      assert {:ok, ^dest} = Qpdf.rotate({:file, pdf_file}, 90, 1, into: dest)
      assert File.exists?(dest)
      assert page_count!({:file, dest}) == 14
    end

    test "overlays and underlays directly to file", %{pdf_binary: pdf_binary} do
      {:ok, page1} = Qpdf.page(pdf_binary, 1)

      dest_ov =
        Path.join(System.tmp_dir!(), "out_ov_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf")

      dest_un =
        Path.join(System.tmp_dir!(), "out_un_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf")

      on_exit(fn ->
        File.rm(dest_ov)
        File.rm(dest_un)
      end)

      assert {:ok, ^dest_ov} = Qpdf.overlay(pdf_binary, page1, into: dest_ov)
      assert File.exists?(dest_ov)

      assert {:ok, ^dest_un} = Qpdf.underlay(pdf_binary, page1, into: dest_un)
      assert File.exists?(dest_un)
    end

    test "linearizes and optimizes directly to file", %{pdf_file: pdf_file} do
      dest_lin =
        Path.join(System.tmp_dir!(), "out_lin_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf")

      dest_opt =
        Path.join(System.tmp_dir!(), "out_opt_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf")

      on_exit(fn ->
        File.rm(dest_lin)
        File.rm(dest_opt)
      end)

      assert {:ok, ^dest_lin} = Qpdf.linearize({:file, pdf_file}, into: dest_lin)
      assert File.exists?(dest_lin)
      assert Qpdf.linearized?({:file, dest_lin}) == true

      assert {:ok, ^dest_opt} = Qpdf.optimize({:file, pdf_file}, into: dest_opt)
      assert File.exists?(dest_opt)
    end

    test "encrypts and decrypts directly to file", %{pdf_file: pdf_file} do
      dest_enc =
        Path.join(System.tmp_dir!(), "out_enc_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf")

      dest_dec =
        Path.join(System.tmp_dir!(), "out_dec_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf")

      on_exit(fn ->
        File.rm(dest_enc)
        File.rm(dest_dec)
      end)

      assert {:ok, ^dest_enc} =
               Qpdf.encrypt({:file, pdf_file}, user_password: "foo", into: dest_enc)

      assert File.exists?(dest_enc)
      assert Qpdf.encrypted?({:file, dest_enc}) == true

      assert {:ok, ^dest_dec} = Qpdf.decrypt({:file, dest_enc}, password: "foo", into: dest_dec)
      assert File.exists?(dest_dec)
      assert Qpdf.encrypted?({:file, dest_dec}) == false
    end

    test "splits pages directly to directory without loading binaries into memory", %{
      pdf_file: pdf_file
    } do
      dest_dir1 =
        Path.join(System.tmp_dir!(), "split_dir_1_#{Base.encode16(:crypto.strong_rand_bytes(4))}")

      dest_dir2 =
        Path.join(System.tmp_dir!(), "split_dir_2_#{Base.encode16(:crypto.strong_rand_bytes(4))}")

      on_exit(fn ->
        File.rm_rf(dest_dir1)
        File.rm_rf(dest_dir2)
      end)

      assert {:ok, files} = Qpdf.split_pages({:file, pdf_file}, into: dest_dir1)
      assert length(files) == 14
      assert Enum.all?(files, &File.exists?/1)
      assert Enum.all?(files, &is_binary/1)

      assert {:ok, groups} = Qpdf.split_pages({:file, pdf_file}, 5, into: {:dir, dest_dir2})
      assert length(groups) == 3
      assert Enum.all?(groups, &File.exists?/1)

      assert {:ok, indexed} = Qpdf.split({:file, pdf_file}, into: dest_dir1)
      assert length(indexed) == 14
      assert [{1, file1} | _] = indexed
      assert is_binary(file1)
      assert File.exists?(file1)
    end

    test "returns error for invalid into option", %{pdf_binary: pdf_binary} do
      assert {:error, :invalid_destination} = Qpdf.pages(pdf_binary, 1, into: :unsupported)
      assert {:error, :invalid_destination} = Qpdf.split_pages(pdf_binary, into: :unsupported)
    end
  end

  describe "attachments/1, extract_attachment/3, add_attachment/3, and remove_attachment/3" do
    test "returns empty list when document has no attachments", %{pdf_binary: pdf_binary} do
      assert {:ok, []} = Qpdf.attachments(pdf_binary)
    end

    test "adds, lists, extracts, and removes binary attachment", %{pdf_binary: pdf_binary} do
      payload = "Hello attachment payload content <xml>123</xml>"

      {:ok, with_att} =
        Qpdf.add_attachment(pdf_binary, payload,
          key: "invoice.xml",
          filename: "factur-x.xml",
          mimetype: "text/xml",
          description: "E-Invoice",
          creation_date: "D:20260101000000Z",
          mod_date: "D:20260102000000Z"
        )

      assert {:ok, [att]} = Qpdf.attachments(with_att)
      assert att.key == "invoice.xml"
      assert att.filename == "factur-x.xml"
      assert att.mimetype == "text/xml"
      assert att.description == "E-Invoice"

      # Extract to memory
      assert {:ok, ^payload} = Qpdf.extract_attachment(with_att, "invoice.xml")

      # Extract directly to file with into: {:file, ...}
      dest_extracted =
        Path.join(
          System.tmp_dir!(),
          "extracted_#{Base.encode16(:crypto.strong_rand_bytes(4))}.xml"
        )

      on_exit(fn -> File.rm(dest_extracted) end)

      assert {:ok, ^dest_extracted} =
               Qpdf.extract_attachment(with_att, "invoice.xml", into: {:file, dest_extracted})

      assert File.read!(dest_extracted) == payload

      # Extract non-existent key
      assert {:error, :not_found} = Qpdf.extract_attachment(with_att, "non_existent")

      # Remove attachment
      {:ok, cleaned} = Qpdf.remove_attachment(with_att, "invoice.xml")
      assert {:ok, []} = Qpdf.attachments(cleaned)

      # Removing non-existent key
      assert {:error, :not_found} = Qpdf.remove_attachment(cleaned, "non_existent")
    end

    test "adds attachment from file with into: option", %{pdf_file: pdf_file} do
      att_src =
        Path.join(
          System.tmp_dir!(),
          "source_att_#{Base.encode16(:crypto.strong_rand_bytes(4))}.csv"
        )

      File.write!(att_src, "id,name\n1,Alice\n2,Bob")

      dest_pdf =
        Path.join(
          System.tmp_dir!(),
          "with_csv_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf"
        )

      on_exit(fn ->
        File.rm(att_src)
        File.rm(dest_pdf)
      end)

      assert {:ok, ^dest_pdf} =
               Qpdf.add_attachment({:file, pdf_file}, {:file, att_src}, into: dest_pdf)

      assert {:ok, [att]} = Qpdf.attachments({:file, dest_pdf})
      assert att.key == Path.basename(att_src)
      assert att.filename == Path.basename(att_src)

      # Replace attachment
      {:ok, replaced} =
        Qpdf.add_attachment({:file, dest_pdf}, "updated content",
          key: Path.basename(att_src),
          replace: true
        )

      assert {:ok, "updated content"} =
               Qpdf.extract_attachment(replaced, Path.basename(att_src))
    end

    test "returns errors for invalid attachments or paths", %{pdf_binary: pdf_binary} do
      assert {:error, :invalid_attachment} = Qpdf.add_attachment(pdf_binary, 12_345)

      assert {:error, :enoent} =
               Qpdf.add_attachment(pdf_binary, {:file, "/non/existent/file.txt"})

      assert {:error, :invalid_input} = Qpdf.add_attachment(12_345, "content")
      assert {:error, _} = Qpdf.attachments("not a pdf")
    end

    test "safely handles path traversal and collision filenames", %{pdf_binary: pdf_binary} do
      victim_path =
        Path.join(
          System.tmp_dir!(),
          "traversal_victim_#{Base.encode16(:crypto.strong_rand_bytes(4))}.txt"
        )

      File.rm(victim_path)

      # 1. Path traversal filename must not write outside temp dir
      {:ok, with_traversal} =
        Qpdf.add_attachment(pdf_binary, "traversal payload",
          key: "traversal_key",
          filename: "../../#{Path.basename(victim_path)}"
        )

      refute File.exists?(victim_path)
      assert {:ok, [att]} = Qpdf.attachments(with_traversal)
      assert att.filename == "../../#{Path.basename(victim_path)}"
      assert {:ok, "traversal payload"} = Qpdf.extract_attachment(with_traversal, "traversal_key")

      # 2. Collision filename "document.pdf" must not overwrite main input
      {:ok, with_collision} =
        Qpdf.add_attachment(pdf_binary, "collision payload",
          key: "collision_key",
          filename: "document.pdf"
        )

      assert page_count!(with_collision) == 14
      assert {:ok, "collision payload"} = Qpdf.extract_attachment(with_collision, "collision_key")
    end
  end

  describe "dimensions/1 and dimensions/2" do
    test "returns dimensions for all pages", %{pdf_binary: pdf_binary, pdf_file: pdf_file} do
      assert {:ok, dims} = Qpdf.dimensions(pdf_binary)
      assert length(dims) == 14

      page1 = hd(dims)
      assert page1.page == 1
      assert page1.width == 439.37
      assert page1.height == 666.14
      assert page1.rotation == 0
      assert page1.orientation == :portrait
      assert page1.box.media == [0.0, 0.0, 439.37, 666.14]
      assert page1.box.crop == [0.0, 0.0, 439.37, 666.14]

      # Works with {:file, path}
      assert {:ok, file_dims} = Qpdf.dimensions({:file, pdf_file})
      assert length(file_dims) == 14
    end

    test "returns single page dimension when integer page is given", %{pdf_binary: pdf_binary} do
      assert {:ok, page1} = Qpdf.dimensions(pdf_binary, 1)
      assert page1.page == 1
      assert page1.orientation == :portrait

      assert {:error, :not_found} = Qpdf.dimensions(pdf_binary, 999)
    end

    test "returns dimensions for Range or list", %{pdf_binary: pdf_binary} do
      assert {:ok, range_dims} = Qpdf.dimensions(pdf_binary, 1..3)
      assert length(range_dims) == 3
      assert Enum.map(range_dims, & &1.page) == [1, 2, 3]

      assert {:ok, list_dims} = Qpdf.dimensions(pdf_binary, [1, 5, 10])
      assert length(list_dims) == 3
      assert Enum.map(list_dims, & &1.page) == [1, 5, 10]
    end

    test "updates dimensions and orientation when page is rotated", %{pdf_binary: pdf_binary} do
      {:ok, rotated} = Qpdf.rotate(pdf_binary, 90, 1)

      assert {:ok, rot_page1} = Qpdf.dimensions(rotated, 1)
      assert rot_page1.rotation == 90
      assert rot_page1.width == 666.14
      assert rot_page1.height == 439.37
      assert rot_page1.orientation == :landscape
    end

    test "detects paper size and square orientation", %{pdf_binary: pdf_binary} do
      {:ok, page1} = Qpdf.page(pdf_binary, 1)

      a4_pdf = :binary.replace(page1, "439.37 666.14", "595.28 841.89")
      assert {:ok, a4_dim} = Qpdf.dimensions(a4_pdf, 1)
      assert a4_dim.paper_size == "A4"

      sq_pdf = :binary.replace(page1, "439.37 666.14", "500.00 500.00")
      assert {:ok, sq_dim} = Qpdf.dimensions(sq_pdf, 1)
      assert sq_dim.orientation == :square
    end

    test "returns errors for invalid input or page spec", %{pdf_binary: pdf_binary} do
      assert {:error, :invalid_page_spec} = Qpdf.dimensions(pdf_binary, "invalid")
      assert {:error, _} = Qpdf.dimensions("not a pdf")
    end
  end

  describe "json/2 version option" do
    test "supports version: 1 and version: 2", %{pdf_binary: pdf_binary} do
      assert {:ok, v2} = Qpdf.json(pdf_binary, version: 2)
      assert v2["version"] == 2

      assert {:ok, v1} = Qpdf.json(pdf_binary, version: 1)
      assert v1["version"] == 1
      assert Map.has_key?(v1, "objects")
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

  describe "optimize_images/2" do
    test "optimizes raster images in PDF binary", %{pdf_binary: pdf_binary} do
      assert {:ok, opt_bin} = Qpdf.optimize_images(pdf_binary)
      assert is_binary(opt_bin)
      assert page_count!(opt_bin) == 14
    end

    test "optimizes with {:file, path} and destination :into", %{pdf_file: pdf_file} do
      tmp_out =
        Path.join(System.tmp_dir!(), "opt_img_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf")

      try do
        assert {:ok, ^tmp_out} =
                 Qpdf.optimize_images({:file, pdf_file},
                   jpeg_quality: 75,
                   min_width: 50,
                   min_height: 50,
                   min_area: 2_500,
                   keep_inline_images: true,
                   externalize_inline_images: true,
                   remove_unreferenced: true,
                   into: tmp_out
                 )

        assert File.exists?(tmp_out)
        assert page_count!(File.read!(tmp_out)) == 14
      after
        File.rm(tmp_out)
      end
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Qpdf.optimize_images({:file, "/non/existent.pdf"})
    end

    test "returns :invalid_input for invalid input" do
      assert {:error, :invalid_input} = Qpdf.optimize_images(12_345)
    end
  end

  describe "password_valid?/2 and requires_password?/1" do
    test "validates passwords for encrypted PDF", %{pdf_binary: pdf_binary} do
      {:ok, enc} =
        Qpdf.encrypt(pdf_binary, user_password: "user_secret", owner_password: "admin_secret")

      assert Qpdf.requires_password?(enc) == true
      assert Qpdf.password_valid?(enc, "user_secret") == true
      assert Qpdf.password_valid?(enc, "admin_secret") == true
      assert Qpdf.password_valid?(enc, "wrong_pass") == false
      assert Qpdf.password_valid?(enc, "") == false
    end

    test "handles owner-only encrypted PDF (empty user password)", %{pdf_binary: pdf_binary} do
      {:ok, enc_owner} =
        Qpdf.encrypt(pdf_binary, owner_password: "admin_secret")

      assert Qpdf.requires_password?(enc_owner) == false
      assert Qpdf.password_valid?(enc_owner, "") == true
      assert Qpdf.password_valid?(enc_owner, "admin_secret") == true
      assert Qpdf.password_valid?(enc_owner, "wrong_pass") == false
    end

    test "returns false for unencrypted PDF", %{pdf_binary: pdf_binary, pdf_file: pdf_file} do
      assert Qpdf.requires_password?(pdf_binary) == false
      assert Qpdf.password_valid?(pdf_binary, "any_pass") == false
      assert Qpdf.password_valid?(pdf_binary, "") == false

      assert Qpdf.requires_password?({:file, pdf_file}) == false
      assert Qpdf.password_valid?({:file, pdf_file}, "any_pass") == false
    end

    test "handles {:file, path} for encrypted PDF", %{pdf_binary: pdf_binary} do
      {:ok, enc} = Qpdf.encrypt(pdf_binary, user_password: "pw", owner_password: "admin")

      tmp_enc =
        Path.join(
          System.tmp_dir!(),
          "pw_valid_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf"
        )

      File.write!(tmp_enc, enc)

      try do
        assert Qpdf.requires_password?({:file, tmp_enc}) == true
        assert Qpdf.password_valid?({:file, tmp_enc}, "pw") == true
        assert Qpdf.password_valid?({:file, tmp_enc}, "wrong") == false
      after
        File.rm(tmp_enc)
      end
    end

    test "returns errors for invalid input or password" do
      assert {:error, :invalid_input} = Qpdf.requires_password?(12_345)
      assert {:error, :invalid_input} = Qpdf.password_valid?(12_345, "secret")
      assert {:error, :invalid_password} = Qpdf.password_valid?("binary", 12_345)
      assert {:error, :enoent} = Qpdf.password_valid?({:file, "/non/existent.pdf"}, "secret")
      assert {:error, :enoent} = Qpdf.requires_password?({:file, "/non/existent.pdf"})
      assert {:error, _} = Qpdf.requires_password?("not a pdf")
      assert {:error, _} = Qpdf.password_valid?("not a pdf", "secret")
    end
  end

  describe "encryption_info/1 and encryption_info/2" do
    test "returns encrypted: false for unencrypted PDF", %{
      pdf_binary: pdf_binary,
      pdf_file: pdf_file
    } do
      assert {:ok, %{encrypted: false}} = Qpdf.encryption_info(pdf_binary)
      assert {:ok, %{encrypted: false}} = Qpdf.encryption_info({:file, pdf_file})
    end

    test "extracts encryption parameters for encrypted PDF", %{pdf_binary: pdf_binary} do
      {:ok, enc} =
        Qpdf.encrypt(pdf_binary,
          user_password: "open_user",
          owner_password: "admin_owner",
          key_length: 256,
          print: :low,
          modify: :form,
          extract: false,
          annotate: true
        )

      # Without password
      assert {:ok, info} = Qpdf.encryption_info(enc)
      assert info.encrypted == true
      assert info.r == 6
      assert is_integer(info.p)
      assert info.stream_method =~ "AES"
      assert info.permissions.extract == false
      assert info.permissions.extract_accessibility == true
      assert info.permissions.print_low == true
      assert info.permissions.print_high == false
      assert info.permissions.modify_forms == true
      assert info.permissions.modify_assembly == true
      assert info.permissions.modify_annotations == true
      assert info.password_matched == nil

      # With matching user password
      assert {:ok, user_info} = Qpdf.encryption_info(enc, password: "open_user")
      assert user_info.password_matched == :user
      assert user_info.user_password == "open_user"

      # With matching owner password
      assert {:ok, owner_info} = Qpdf.encryption_info(enc, password: "admin_owner")
      assert owner_info.password_matched == :owner
    end

    test "works with {:file, path}", %{pdf_binary: pdf_binary} do
      {:ok, enc} = Qpdf.encrypt(pdf_binary, user_password: "file_pw")

      tmp_enc =
        Path.join(
          System.tmp_dir!(),
          "enc_info_#{Base.encode16(:crypto.strong_rand_bytes(4))}.pdf"
        )

      File.write!(tmp_enc, enc)

      try do
        assert {:ok, info} = Qpdf.encryption_info({:file, tmp_enc}, password: "file_pw")
        assert info.encrypted == true
        assert info.password_matched == :user
      after
        File.rm(tmp_enc)
      end
    end

    test "returns errors for invalid input" do
      assert {:error, :invalid_input} = Qpdf.encryption_info(12_345)
      assert {:error, :enoent} = Qpdf.encryption_info({:file, "/non/existent.pdf"})
      assert {:error, _} = Qpdf.encryption_info("not a pdf")
    end
  end

  defp page_count!(binary) do
    {:ok, count} = Qpdf.page_count(binary)
    count
  end
end
