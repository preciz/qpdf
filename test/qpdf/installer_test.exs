defmodule Qpdf.InstallerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Qpdf.Installer

  test "detect_target/0 detects platform" do
    assert {:ok, :linux_x86_64} = Installer.detect_target()

    assert {:error, {:unsupported_platform, {:unix, :darwin}, "arm64"}} =
             Installer.detect_target({:unix, :darwin}, "arm64")

    assert {:error, {:unsupported_platform, {:unix, :linux}, "aarch64"}} =
             Installer.detect_target({:unix, :linux}, "aarch64")
  end

  test "raise_executable_error/1 raises descriptive error" do
    assert_raise RuntimeError, ~r/No qpdf executable found/, fn ->
      Installer.raise_executable_error({:unsupported_platform, {:unix, :darwin}, "arm64"})
    end
  end

  test "app_run_path/0 returns AppRun path" do
    assert Installer.app_run_path() =~ "AppRun"
  end

  test "priv_dir/0 returns priv path" do
    assert is_binary(Installer.priv_dir())
  end

  test "tmp_dir/0 returns default or configured tmp dir" do
    assert Installer.tmp_dir() == System.tmp_dir!()

    orig = Application.get_env(:qpdf, :tmp_dir)

    try do
      Application.put_env(:qpdf, :tmp_dir, "/tmp/custom_installer_tmp")
      assert Installer.tmp_dir() == "/tmp/custom_installer_tmp"
    after
      if orig do
        Application.put_env(:qpdf, :tmp_dir, orig)
      else
        Application.delete_env(:qpdf, :tmp_dir)
      end
    end
  end

  test "find_executable/0 honors configured executable_path" do
    orig = Application.get_env(:qpdf, :executable_path)

    try do
      Application.put_env(:qpdf, :executable_path, "/bin/sh")
      assert {:ok, "/bin/sh"} = Installer.find_executable()

      Application.put_env(:qpdf, :executable_path, "/nonexistent/custom/path")

      assert capture_log(fn ->
               assert {:error, :not_found} = Installer.find_executable()
             end) =~ "does not exist"
    after
      if orig do
        Application.put_env(:qpdf, :executable_path, orig)
      else
        Application.delete_env(:qpdf, :executable_path)
      end
    end
  end

  test "find_executable/0 honors QPDF_PATH environment variable" do
    orig_env = System.get_env("QPDF_PATH")
    orig_app = Application.get_env(:qpdf, :executable_path)

    try do
      Application.delete_env(:qpdf, :executable_path)

      System.put_env("QPDF_PATH", "/bin/sh")
      assert {:ok, "/bin/sh"} = Installer.find_executable()

      # Application env takes precedence over QPDF_PATH
      Application.put_env(:qpdf, :executable_path, "/bin/sh")
      assert {:ok, "/bin/sh"} = Installer.find_executable()

      Application.delete_env(:qpdf, :executable_path)
      System.put_env("QPDF_PATH", "/nonexistent/custom/env/path")

      assert capture_log(fn ->
               assert {:error, :not_found} = Installer.find_executable()
             end) =~ "QPDF_PATH environment variable"
    after
      if orig_app do
        Application.put_env(:qpdf, :executable_path, orig_app)
      else
        Application.delete_env(:qpdf, :executable_path)
      end

      if orig_env do
        System.put_env("QPDF_PATH", orig_env)
      else
        System.delete_env("QPDF_PATH")
      end
    end
  end

  test "bin_version/0 returns version of existing binary" do
    orig_app = Application.get_env(:qpdf, :executable_path)

    try do
      case System.find_executable("qpdf") do
        path when is_binary(path) ->
          Application.put_env(:qpdf, :executable_path, path)
          assert {:ok, version} = Installer.bin_version()
          assert {:ok, ^version} = Qpdf.bin_version()
          assert is_binary(version)
          assert Regex.match?(~r/^\d+\.\d+/, version)

        nil ->
          :ok
      end

      # Non-existent executable returns :error
      Application.put_env(:qpdf, :executable_path, "/nonexistent/path")

      capture_log(fn ->
        assert Installer.bin_version() == :error
        assert Qpdf.bin_version() == :error
      end)
    after
      if orig_app do
        Application.put_env(:qpdf, :executable_path, orig_app)
      else
        Application.delete_env(:qpdf, :executable_path)
      end
    end
  end

  test "bin_version/0 returns :error when binary fails to execute" do
    orig_app = Application.get_env(:qpdf, :executable_path)

    try do
      Application.put_env(:qpdf, :executable_path, "/bin/false")
      assert Installer.bin_version() == :error
      assert Qpdf.bin_version() == :error
    after
      if orig_app do
        Application.put_env(:qpdf, :executable_path, orig_app)
      else
        Application.delete_env(:qpdf, :executable_path)
      end
    end
  end

  test "find_executable/0 honors prefer_system_executable over cached AppImage" do
    orig_prefer = Application.get_env(:qpdf, :prefer_system_executable)
    orig_ver = Application.get_env(:qpdf, :version)

    try do
      Application.put_env(:qpdf, :prefer_system_executable, true)

      case System.find_executable("qpdf") do
        path when is_binary(path) ->
          assert {:ok, ^path} = Installer.find_executable()

        nil ->
          :ok
      end

      Application.put_env(:qpdf, :prefer_system_executable, false)

      if File.exists?(Installer.app_run_path()) do
        assert {:ok, path} = Installer.find_executable()
        assert path == Installer.app_run_path()
      end
    after
      if orig_prefer do
        Application.put_env(:qpdf, :prefer_system_executable, orig_prefer)
      else
        Application.delete_env(:qpdf, :prefer_system_executable)
      end

      if orig_ver do
        Application.put_env(:qpdf, :version, orig_ver)
      else
        Application.delete_env(:qpdf, :version)
      end
    end
  end

  test "executable_path/0 returns executable string" do
    path = Qpdf.executable_path()
    assert is_binary(path)
    assert File.exists?(path)
  end

  test "version/0 returns default or configured version" do
    assert Installer.version() == "12.3.1"

    orig = Application.get_env(:qpdf, :version)

    try do
      Application.put_env(:qpdf, :version, "12.4.1")
      assert Installer.version() == "12.4.1"
      assert Installer.storage_dir() =~ "qpdf-12.4.1"
    after
      if orig do
        Application.put_env(:qpdf, :version, orig)
      else
        Application.delete_env(:qpdf, :version)
      end
    end
  end

  test "installs mock AppImage successfully" do
    port =
      start_mock_server(fn _req ->
        body =
          "#!/bin/sh\n" <>
            "mkdir -p squashfs-root/usr/bin\n" <>
            "touch squashfs-root/AppRun\n" <>
            "touch squashfs-root/usr/bin/qpdf\n" <>
            "chmod +x squashfs-root/AppRun\n" <>
            "chmod +x squashfs-root/usr/bin/qpdf\n"

        {"200 OK", body}
      end)

    test_version = "mock-success-#{Base.encode16(:crypto.strong_rand_bytes(4))}"

    try do
      assert {:ok, path} =
               Installer.install(
                 url: "http://127.0.0.1:#{port}/mock.AppImage",
                 force: true,
                 version: test_version
               )

      assert File.exists?(path)
    after
      File.rm_rf(Installer.storage_dir(test_version))
    end
  end

  test "install/1 handles download failure" do
    port =
      start_mock_server(fn _req ->
        {"404 Not Found", "File not found"}
      end)

    test_version = "mock-404-#{Base.encode16(:crypto.strong_rand_bytes(4))}"

    try do
      assert {:error, {:download_failed, 404, _}} =
               Installer.install(
                 url: "http://127.0.0.1:#{port}/missing.AppImage",
                 force: true,
                 version: test_version
               )
    after
      File.rm_rf(Installer.storage_dir(test_version))
    end
  end

  test "install/1 handles extraction failure" do
    port =
      start_mock_server(fn _req ->
        body = "#!/bin/sh\nexit 1\n"
        {"200 OK", body}
      end)

    test_version = "mock-fail-#{Base.encode16(:crypto.strong_rand_bytes(4))}"

    try do
      assert {:error, {:extraction_failed, 1, _}} =
               Installer.install(
                 url: "http://127.0.0.1:#{port}/fail.AppImage",
                 force: true,
                 version: test_version
               )
    after
      File.rm_rf(Installer.storage_dir(test_version))
    end
  end

  test "install/1 handles missing AppRun after extraction" do
    port =
      start_mock_server(fn _req ->
        body = "#!/bin/sh\nmkdir -p squashfs-root\n"
        {"200 OK", body}
      end)

    test_version = "mock-missing-apprun-#{Base.encode16(:crypto.strong_rand_bytes(4))}"

    try do
      assert {:error, :extracted_apprun_missing} =
               Installer.install(
                 url: "http://127.0.0.1:#{port}/no-apprun.AppImage",
                 force: true,
                 version: test_version
               )
    after
      File.rm_rf(Installer.storage_dir(test_version))
    end
  end

  test "ensure_executable!/0 raises on install failure" do
    port =
      start_mock_server(fn _req ->
        {"500 Internal Server Error", "server error"}
      end)

    test_version = "mock-raise-#{Base.encode16(:crypto.strong_rand_bytes(4))}"
    orig_ver = Application.get_env(:qpdf, :version)
    orig_url = Application.get_env(:qpdf, :appimage_url)

    try do
      Application.put_env(:qpdf, :version, test_version)
      Application.put_env(:qpdf, :appimage_url, "http://127.0.0.1:#{port}/error.AppImage")

      assert_raise RuntimeError, ~r/Failed to locate or install qpdf executable/, fn ->
        Installer.ensure_executable!()
      end
    after
      if orig_ver do
        Application.put_env(:qpdf, :version, orig_ver)
      else
        Application.delete_env(:qpdf, :version)
      end

      if orig_url do
        Application.put_env(:qpdf, :appimage_url, orig_url)
      else
        Application.delete_env(:qpdf, :appimage_url)
      end

      File.rm_rf(Installer.storage_dir(test_version))
    end
  end

  test "ensure_executable!/0 installs successfully when missing" do
    port =
      start_mock_server(fn _req ->
        body =
          "#!/bin/sh\n" <>
            "mkdir -p squashfs-root/usr/bin\n" <>
            "touch squashfs-root/AppRun\n" <>
            "touch squashfs-root/usr/bin/qpdf\n" <>
            "chmod +x squashfs-root/AppRun\n" <>
            "chmod +x squashfs-root/usr/bin/qpdf\n"

        {"200 OK", body}
      end)

    test_version = "mock-ensure-success-#{Base.encode16(:crypto.strong_rand_bytes(4))}"
    orig_ver = Application.get_env(:qpdf, :version)
    orig_url = Application.get_env(:qpdf, :appimage_url)

    try do
      Application.put_env(:qpdf, :version, test_version)
      Application.put_env(:qpdf, :appimage_url, "http://127.0.0.1:#{port}/success.AppImage")

      path = Installer.ensure_executable!()
      assert File.exists?(path)
    after
      if orig_ver,
        do: Application.put_env(:qpdf, :version, orig_ver),
        else: Application.delete_env(:qpdf, :version)

      if orig_url,
        do: Application.put_env(:qpdf, :appimage_url, orig_url),
        else: Application.delete_env(:qpdf, :appimage_url)

      File.rm_rf(Installer.storage_dir(test_version))
    end
  end

  test "ensure_executable!/0 serializes concurrent callers without racing" do
    call_count = :atomics.new(1, [])

    port =
      start_mock_server(fn _req ->
        :atomics.add(call_count, 1, 1)
        Process.sleep(50)

        body =
          "#!/bin/sh\n" <>
            "mkdir -p squashfs-root/usr/bin\n" <>
            "touch squashfs-root/AppRun\n" <>
            "touch squashfs-root/usr/bin/qpdf\n" <>
            "chmod +x squashfs-root/AppRun\n" <>
            "chmod +x squashfs-root/usr/bin/qpdf\n"

        {"200 OK", body}
      end)

    test_version = "mock-concurrent-#{Base.encode16(:crypto.strong_rand_bytes(4))}"
    orig_ver = Application.get_env(:qpdf, :version)
    orig_url = Application.get_env(:qpdf, :appimage_url)

    try do
      Application.put_env(:qpdf, :version, test_version)
      Application.put_env(:qpdf, :appimage_url, "http://127.0.0.1:#{port}/concurrent.AppImage")

      tasks =
        for _ <- 1..5 do
          Task.async(fn ->
            Installer.ensure_executable!()
          end)
        end

      results = Task.await_many(tasks)
      assert length(results) == 5
      assert Enum.all?(results, &File.exists?/1)
      assert :atomics.get(call_count, 1) == 1
    after
      if orig_ver,
        do: Application.put_env(:qpdf, :version, orig_ver),
        else: Application.delete_env(:qpdf, :version)

      if orig_url,
        do: Application.put_env(:qpdf, :appimage_url, orig_url),
        else: Application.delete_env(:qpdf, :appimage_url)

      File.rm_rf(Installer.storage_dir(test_version))
    end
  end

  test "fetch_file enforces strict TLS peer verification against self-signed certificates" do
    if System.find_executable("openssl") do
      tmp = System.tmp_dir!()
      suffix = Base.encode16(:crypto.strong_rand_bytes(4))
      key_path = Path.join(tmp, "test_key_#{suffix}.pem")
      cert_path = Path.join(tmp, "test_cert_#{suffix}.pem")

      System.cmd("openssl", [
        "req",
        "-x509",
        "-newkey",
        "rsa:2048",
        "-nodes",
        "-keyout",
        key_path,
        "-out",
        cert_path,
        "-days",
        "1",
        "-subj",
        "/CN=127.0.0.1"
      ])

      Application.ensure_all_started(:ssl)

      {:ok, listen} =
        :ssl.listen(0,
          certfile: String.to_charlist(cert_path),
          keyfile: String.to_charlist(key_path),
          reuseaddr: true,
          active: false
        )

      {:ok, {_, port}} = :ssl.sockname(listen)

      spawn_link(fn ->
        case :ssl.transport_accept(listen, 5000) do
          {:ok, socket} ->
            :ssl.handshake(socket, 5000)
            :ssl.close(socket)

          _ ->
            :ok
        end

        :ssl.close(listen)
      end)

      test_version = "mock-ssl-#{suffix}"

      try do
        assert {:error, {:download_failed, _reason}} =
                 Installer.install(
                   url: "https://127.0.0.1:#{port}/malicious.AppImage",
                   version: test_version
                 )
      after
        File.rm(key_path)
        File.rm(cert_path)
        :ssl.close(listen)
        File.rm_rf(Installer.storage_dir(test_version))
      end
    end
  end

  defp start_mock_server(handler) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    spawn_link(fn ->
      case :gen_tcp.accept(listen_socket, 5000) do
        {:ok, client} ->
          {:ok, req} = :gen_tcp.recv(client, 0, 5000)
          {status, body} = handler.(req)

          response =
            "HTTP/1.1 #{status}\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n" <>
              body

          :gen_tcp.send(client, response)
          :gen_tcp.close(client)

        _ ->
          :ok
      end

      :gen_tcp.close(listen_socket)
    end)

    port
  end
end
