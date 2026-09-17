defmodule Qpdf.TempTest do
  use ExUnit.Case, async: false

  alias Qpdf.Temp

  describe "tmp_dir/0" do
    test "returns System.tmp_dir!() by default" do
      assert Temp.tmp_dir() == System.tmp_dir!()
    end

    test "respects Application env override" do
      orig = Application.get_env(:qpdf, :tmp_dir)

      try do
        Application.put_env(:qpdf, :tmp_dir, "/custom/temp_test_tmp")
        assert Temp.tmp_dir() == "/custom/temp_test_tmp"
      after
        if orig do
          Application.put_env(:qpdf, :tmp_dir, orig)
        else
          Application.delete_env(:qpdf, :tmp_dir)
        end
      end
    end
  end

  describe "with_tmp_dir/1 and with_tmp_dir/2" do
    test "creates directory and cleans it up after execution" do
      ref =
        Temp.with_tmp_dir(fn dir ->
          assert File.dir?(dir)
          test_file = Path.join(dir, "test.txt")
          File.write!(test_file, "hello")
          assert File.exists?(test_file)
          dir
        end)

      refute File.exists?(ref)
    end

    test "cleans up directory even when callback raises" do
      dir_path =
        try do
          Temp.with_tmp_dir(fn dir ->
            assert File.dir?(dir)
            throw({:bail, dir})
          end)
        catch
          :throw, {:bail, dir} -> dir
        end

      refute File.exists?(dir_path)
    end

    test "supports custom prefix and options" do
      Temp.with_tmp_dir([prefix: "custom_sub", bytes: 6, sub_dir: false], fn dir ->
        assert File.dir?(dir)
        assert Path.basename(dir) =~ ~r/^custom_sub_[0-9A-F]{12}$/
      end)
    end
  end

  describe "move_file!/2" do
    test "moves file across destination paths" do
      Temp.with_tmp_dir(fn dir ->
        src = Path.join(dir, "src.txt")
        dest = Path.join(dir, "dest.txt")

        File.write!(src, "moving data")
        assert :ok = Temp.move_file!(src, dest)
        refute File.exists?(src)
        assert File.read!(dest) == "moving data"
      end)
    end
  end

  describe "resolve_input/1" do
    test "resolves existing file" do
      Temp.with_tmp_dir(fn dir ->
        file = Path.join(dir, "doc.pdf")
        File.write!(file, "%PDF-1.4")
        assert {:ok, {:file, expanded}} = Temp.resolve_input({:file, file})
        assert expanded == Path.expand(file)
      end)
    end

    test "returns :enoent for non-existent file" do
      assert {:error, :enoent} = Temp.resolve_input({:file, "/non/existent/path/never.pdf"})
    end

    test "resolves binary data" do
      assert {:ok, {:binary, "binary content"}} = Temp.resolve_input("binary content")
    end

    test "returns :invalid_input for invalid input type" do
      assert {:error, :invalid_input} = Temp.resolve_input(123)
      assert {:error, :invalid_input} = Temp.resolve_input(%{})
    end
  end

  describe "with_input_path/2" do
    test "passes existing file path directly without temporary copy" do
      Temp.with_tmp_dir(fn dir ->
        file = Path.join(dir, "doc.pdf")
        File.write!(file, "%PDF-1.4")

        assert {:ok, :ran} =
                 Temp.with_input_path({:file, file}, fn path ->
                   assert path == Path.expand(file)
                   {:ok, :ran}
                 end)
      end)
    end

    test "materializes binary input into a temporary file and cleans it up" do
      captured_path =
        Temp.with_input_path("PDF binary", fn path ->
          assert File.exists?(path)
          assert File.read!(path) == "PDF binary"
          path
        end)

      refute File.exists?(captured_path)
    end

    test "returns error on invalid input" do
      assert {:error, :invalid_input} = Temp.with_input_path(:invalid, fn _path -> :ok end)
    end
  end

  describe "with_two_inputs/4" do
    test "handles both inputs as existing files" do
      Temp.with_tmp_dir(fn dir ->
        f1 = Path.join(dir, "doc1.pdf")
        f2 = Path.join(dir, "doc2.pdf")
        File.write!(f1, "doc1")
        File.write!(f2, "doc2")

        assert {:ok, :done} =
                 Temp.with_two_inputs(
                   {:file, f1},
                   {:file, f2},
                   fn path1, path2 ->
                     assert path1 == Path.expand(f1)
                     assert path2 == Path.expand(f2)
                     {:ok, :done}
                   end,
                   {"doc1.pdf", "doc2.pdf"}
                 )
      end)
    end

    test "materializes binary when at least one input is binary" do
      Temp.with_tmp_dir(fn dir ->
        f1 = Path.join(dir, "doc1.pdf")
        File.write!(f1, "doc1")

        assert {:ok, :done} =
                 Temp.with_two_inputs(
                   {:file, f1},
                   "doc2_bytes",
                   fn path1, path2 ->
                     assert path1 == Path.expand(f1)
                     assert File.read!(path2) == "doc2_bytes"
                     {:ok, :done}
                   end,
                   {"d1.pdf", "d2.pdf"}
                 )
      end)
    end

    test "returns error if any input fails to resolve" do
      assert {:error, :invalid_input} =
               Temp.with_two_inputs("valid_bytes", :invalid, fn _, _ -> :ok end, {"a", "b"})
    end
  end

  describe "with_merged_inputs/2" do
    test "processes list of files without extra tmp dir if all are files" do
      Temp.with_tmp_dir(fn dir ->
        f1 = Path.join(dir, "f1.pdf")
        f2 = Path.join(dir, "f2.pdf")
        File.write!(f1, "f1")
        File.write!(f2, "f2")

        inputs = [{:file, f1}, {{:file, f2}, "1-2"}]

        assert {:ok, :done} =
                 Temp.with_merged_inputs(inputs, fn list ->
                   assert [{p1, nil}, {p2, "1-2"}] = list
                   assert p1 == Path.expand(f1)
                   assert p2 == Path.expand(f2)
                   {:ok, :done}
                 end)
      end)
    end

    test "materializes inputs when binary inputs are present" do
      Temp.with_tmp_dir(fn dir ->
        f1 = Path.join(dir, "f1.pdf")
        File.write!(f1, "f1")

        inputs = [{:file, f1}, "binary_page", {"other_binary", "3-5"}]

        assert {:ok, :done} =
                 Temp.with_merged_inputs(inputs, fn list ->
                   assert [{p1, nil}, {p2, nil}, {p3, "3-5"}] = list
                   assert p1 == Path.expand(f1)
                   assert File.read!(p2) == "binary_page"
                   assert File.read!(p3) == "other_binary"
                   {:ok, :done}
                 end)
      end)
    end

    test "returns error on invalid merge input" do
      assert {:error, :invalid_input} =
               Temp.with_merged_inputs([:invalid], fn _ -> :ok end)

      assert {:error, :enoent} =
               Temp.with_merged_inputs([{{:file, "/non/existent.pdf"}, "1-2"}], fn _ -> :ok end)
    end
  end

  describe "with_input_and_output_dir/2" do
    test "creates output dir with file input" do
      Temp.with_tmp_dir(fn dir ->
        f1 = Path.join(dir, "f1.pdf")
        File.write!(f1, "f1")

        assert {:ok, :done} =
                 Temp.with_input_and_output_dir({:file, f1}, fn in_path, out_dir ->
                   assert in_path == Path.expand(f1)
                   assert File.dir?(out_dir)
                   {:ok, :done}
                 end)
      end)
    end

    test "materializes binary input into separate input file in tmp dir" do
      assert {:ok, :done} =
               Temp.with_input_and_output_dir("bin_pdf", fn in_path, out_dir ->
                 assert File.read!(in_path) == "bin_pdf"
                 assert File.dir?(out_dir)
                 {:ok, :done}
               end)
    end

    test "returns error on invalid input" do
      assert {:error, :invalid_input} =
               Temp.with_input_and_output_dir(:bad_input, fn _, _ -> :ok end)
    end
  end
end
