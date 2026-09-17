defmodule Qpdf.QpdfPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  @test_pdf_zst_path "test/fixtures/qpdf_test.pdf.zst"

  setup_all do
    pdf =
      @test_pdf_zst_path
      |> File.read!()
      |> :zstd.decompress()
      |> IO.iodata_to_binary()

    %{pdf: pdf}
  end

  property "page_count equals range length for any valid 1 <= a <= b <= 14", %{pdf: pdf} do
    check all(
            a <- integer(1..14),
            b <- integer(a..14),
            max_runs: 25
          ) do
      assert {:ok, slice} = Qpdf.pages(pdf, a..b)
      assert Qpdf.page_count(slice) == {:ok, b - a + 1}
    end
  end

  property "arbitrary page lists always produce exact page counts", %{pdf: pdf} do
    check all(
            page_list <- list_of(integer(1..14), min_length: 1, max_length: 10),
            max_runs: 20
          ) do
      assert {:ok, slice} = Qpdf.pages(pdf, page_list)
      assert Qpdf.page_count(slice) == {:ok, length(page_list)}
    end
  end

  property "splitting into N chunks and merging them back preserves total page count", %{pdf: pdf} do
    check all(
            group_size <- integer(1..14),
            max_runs: 14
          ) do
      assert {:ok, chunks} = Qpdf.split_pages(pdf, group_size)
      expected_chunks = ceil(14 / group_size)
      assert length(chunks) == expected_chunks

      assert {:ok, merged} = Qpdf.merge(chunks)
      assert Qpdf.page_count(merged) == {:ok, 14}
    end
  end

  property "rotating by angle and then back to 0 restores original orientation", %{pdf: pdf} do
    check all(
            angle <- member_of([90, 180, 270]),
            page <- integer(1..14),
            max_runs: 15
          ) do
      assert {:ok, orig_dim} = Qpdf.dimensions(pdf, page)
      assert {:ok, r1} = Qpdf.rotate(pdf, angle, page)
      assert {:ok, r2} = Qpdf.rotate(r1, 0, page)
      assert {:ok, roundtrip_dim} = Qpdf.dimensions(r2, page)

      assert roundtrip_dim.orientation == orig_dim.orientation
      assert_in_delta roundtrip_dim.width, orig_dim.width, 0.1
      assert_in_delta roundtrip_dim.height, orig_dim.height, 0.1
    end
  end

  property "arbitrary alphanumeric passwords validate cleanly", %{pdf: pdf} do
    check all(
            password <- string(:alphanumeric, min_length: 1, max_length: 32),
            max_runs: 15
          ) do
      assert {:ok, enc} =
               Qpdf.encrypt(pdf,
                 user_password: password,
                 owner_password: "owner_" <> password
               )

      assert Qpdf.requires_password?(enc) == true
      assert Qpdf.password_valid?(enc, password) == true
      assert Qpdf.password_valid?(enc, password <> "_wrong") == false
    end
  end
end
