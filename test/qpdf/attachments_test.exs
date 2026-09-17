defmodule Qpdf.AttachmentsTest do
  use ExUnit.Case, async: true

  alias Qpdf.Attachments

  setup do
    pdf_binary = Qpdf.TestHelper.sample_pdf()
    %{pdf_binary: pdf_binary}
  end

  describe "Qpdf.Attachments" do
    test "list/1, add/3, extract/3, remove/3 cycle", %{pdf_binary: pdf_binary} do
      assert {:ok, []} = Attachments.list(pdf_binary)

      payload = "test payload 12345"

      {:ok, with_att} =
        Attachments.add(pdf_binary, payload,
          key: "test.txt",
          filename: "my_test.txt",
          mimetype: "text/plain",
          description: "Test description",
          creation_date: "D:20260101000000Z",
          mod_date: "D:20260102000000Z",
          replace: true
        )

      assert {:ok, [att]} = Attachments.list(with_att)
      assert att.key == "test.txt"
      assert att.filename == "my_test.txt"
      assert att.mimetype == "text/plain"
      assert att.description == "Test description"

      # Extract to memory
      assert {:ok, ^payload} = Attachments.extract(with_att, "test.txt")

      # Extract to file
      dest =
        Path.join(System.tmp_dir!(), "att_out_#{Base.encode16(:crypto.strong_rand_bytes(4))}.txt")

      on_exit(fn -> File.rm(dest) end)
      assert {:ok, ^dest} = Attachments.extract(with_att, "test.txt", into: dest)
      assert File.read!(dest) == payload

      # Extract missing
      assert {:error, :not_found} = Attachments.extract(with_att, "missing.key")

      # Remove
      assert {:ok, cleaned} = Attachments.remove(with_att, "test.txt")
      assert {:ok, []} = Attachments.list(cleaned)

      # Remove missing
      assert {:error, :not_found} = Attachments.remove(cleaned, "missing.key")
    end

    test "add/3 errors on invalid inputs", %{pdf_binary: pdf_binary} do
      assert {:error, :invalid_attachment} = Attachments.add(pdf_binary, 12_345)
      assert {:error, :enoent} = Attachments.add(pdf_binary, {:file, "/non/existent/path.txt"})
    end
  end
end
