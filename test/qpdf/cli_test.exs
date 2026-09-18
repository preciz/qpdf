defmodule Qpdf.CLITest do
  use ExUnit.Case, async: false

  alias Qpdf.CLI

  describe "default_opts/0" do
    test "returns expected default flags" do
      assert CLI.default_opts() == ["--no-warn", "--warning-exit-0", "--decrypt"]
    end
  end

  describe "executable/0" do
    test "returns path to qpdf binary" do
      path = CLI.executable()
      assert is_binary(path)
      assert File.exists?(path)
    end
  end

  describe "run/2" do
    test "executes qpdf command" do
      {output, code} = CLI.run(["--version"])
      assert code == 0
      assert output =~ "qpdf version"
    end
  end

  describe "resolve_output_target/1" do
    test "resolves :memory target" do
      assert {:ok, "-", :memory} = CLI.resolve_output_target([])
      assert {:ok, "-", :memory} = CLI.resolve_output_target(into: :memory)
    end

    test "resolves file string target and creates parent directory" do
      tmp_dest =
        Path.join([
          System.tmp_dir!(),
          "cli_test_#{Base.encode16(:crypto.strong_rand_bytes(4))}",
          "subdir",
          "out.pdf"
        ])

      on_exit(fn -> File.rm_rf(Path.dirname(Path.dirname(tmp_dest))) end)

      assert {:ok, expanded, {:file, expanded}} = CLI.resolve_output_target(into: tmp_dest)
      assert expanded == Path.expand(tmp_dest)
      assert File.dir?(Path.dirname(expanded))
    end

    test "resolves {:file, path} target" do
      tmp_dest =
        Path.join([
          System.tmp_dir!(),
          "cli_test_#{Base.encode16(:crypto.strong_rand_bytes(4))}",
          "out.pdf"
        ])

      on_exit(fn -> File.rm_rf(Path.dirname(tmp_dest)) end)

      assert {:ok, expanded, {:file, expanded}} =
               CLI.resolve_output_target(into: {:file, tmp_dest})

      assert expanded == Path.expand(tmp_dest)
    end

    test "returns error for invalid destination" do
      assert {:error, :invalid_destination} = CLI.resolve_output_target(into: 123)
      assert {:error, :invalid_destination} = CLI.resolve_output_target(into: :unknown)
    end
  end

  describe "deliver_output/2" do
    test "delivers output directly to memory" do
      assert {:ok, "data"} = CLI.deliver_output("data", into: :memory)
    end

    test "delivers output to a file path" do
      tmp_dest =
        Path.join(System.tmp_dir!(), "deliver_#{Base.encode16(:crypto.strong_rand_bytes(4))}.txt")

      on_exit(fn -> File.rm(tmp_dest) end)

      assert {:ok, path} = CLI.deliver_output("saved content", into: tmp_dest)
      assert path == Path.expand(tmp_dest)
      assert File.read!(path) == "saved content"
    end

    test "returns error on invalid destination" do
      assert {:error, :invalid_destination} = CLI.deliver_output("data", into: :bad)
    end
  end

  describe "run_stdout/1" do
    test "captures stdout without stderr mixing" do
      sh = System.find_executable("sh")

      if sh do
        script_dir = System.tmp_dir!()
        token = Base.encode16(:crypto.strong_rand_bytes(4))
        mock_bin = Path.join(script_dir, "mock_qpdf_#{token}.sh")

        File.write!(mock_bin, """
        #!/bin/sh
        if [ "$1" = "fail" ]; then
          echo "something went wrong" >&2
          exit 1
        fi
        echo "ATTACHMENT_DATA"
        echo "WARNING: non-fatal warning" >&2
        exit 0
        """)

        File.chmod!(mock_bin, 0o755)

        orig = Application.get_env(:qpdf, :executable_path)

        try do
          Application.put_env(:qpdf, :executable_path, mock_bin)

          assert {stdout, 0} = CLI.run_stdout(["ok"])
          assert String.trim(stdout) == "ATTACHMENT_DATA"
          refute stdout =~ "WARNING"

          assert {stderr, 1} = CLI.run_stdout(["fail"])
          assert stderr =~ "something went wrong"
        after
          File.rm(mock_bin)

          if orig do
            Application.put_env(:qpdf, :executable_path, orig)
          else
            Application.delete_env(:qpdf, :executable_path)
          end
        end
      end
    end
  end

  describe "run_into/2" do
    test "returns error for invalid output destination before running" do
      assert {:error, :invalid_destination} = CLI.run_into(["--version"], into: :bad)
    end

    test "does not mix stderr into output binary when writing into: :memory" do
      sh = System.find_executable("sh")

      if sh do
        script_dir = System.tmp_dir!()
        token = Base.encode16(:crypto.strong_rand_bytes(4))
        mock_bin = Path.join(script_dir, "mock_qpdf_into_#{token}.sh")

        File.write!(mock_bin, """
        #!/bin/sh
        for last; do true; done
        echo "%PDF-1.4 mock content" > "$last"
        echo "WARNING: non-fatal stderr warning" >&2
        exit 0
        """)

        File.chmod!(mock_bin, 0o755)

        orig = Application.get_env(:qpdf, :executable_path)

        try do
          Application.put_env(:qpdf, :executable_path, mock_bin)

          assert {:ok, binary} = CLI.run_into(["dummy_arg"], into: :memory)
          assert binary =~ "%PDF-1.4 mock content"
          refute binary =~ "WARNING"
        after
          File.rm(mock_bin)

          if orig do
            Application.put_env(:qpdf, :executable_path, orig)
          else
            Application.delete_env(:qpdf, :executable_path)
          end
        end
      end
    end
  end
end
