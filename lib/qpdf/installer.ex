defmodule Qpdf.Installer do
  @moduledoc """
  Manages finding or downloading and extracting the qpdf AppImage.
  """

  require Logger

  @default_version "12.3.1"

  @doc """
  Ensures that the qpdf executable is available.
  Returns the path to the executable, downloading and installing it if not present.
  """
  @spec ensure_executable!() :: String.t()
  def ensure_executable! do
    case find_executable() do
      {:ok, path} ->
        path

      {:error, :not_found} ->
        # Synchronize across concurrent calls so only one download/install occurs
        :global.trans({__MODULE__, self()}, &install_if_missing!/0)
    end
  end

  defp install_if_missing! do
    with {:error, :not_found} <- find_executable(),
         {:error, reason} <- install() do
      raise_executable_error(reason)
    else
      {:ok, path} -> path
    end
  end

  @doc """
  Finds the configured or existing qpdf executable without attempting to download.
  """
  @spec find_executable() :: {:ok, String.t()} | {:error, :not_found}
  def find_executable do
    with nil <- find_configured_executable(),
         nil <- find_env_executable(),
         nil <- find_system_executable(),
         nil <- find_cached_executable() do
      {:error, :not_found}
    end
  end

  defp find_configured_executable do
    case Application.get_env(:qpdf, :executable_path) do
      nil ->
        nil

      configured ->
        if File.exists?(configured) do
          {:ok, configured}
        else
          Logger.warning("Configured :qpdf executable_path #{configured} does not exist")
          {:error, :not_found}
        end
    end
  end

  defp find_env_executable do
    case System.get_env("QPDF_PATH") do
      env when is_binary(env) and env != "" ->
        if File.exists?(env) do
          {:ok, env}
        else
          Logger.warning("QPDF_PATH environment variable #{env} does not exist")
          {:error, :not_found}
        end

      _ ->
        nil
    end
  end

  defp find_system_executable do
    if prefer_system_executable?() and system_executable_exists?() do
      {:ok, System.find_executable("qpdf")}
    end
  end

  defp find_cached_executable do
    if File.exists?(app_run_path()) do
      {:ok, app_run_path()}
    end
  end

  defp prefer_system_executable? do
    Application.get_env(:qpdf, :prefer_system_executable, false)
  end

  defp system_executable_exists? do
    is_binary(System.find_executable("qpdf"))
  end

  @doc """
  Returns the configured qpdf version.
  """
  def version do
    Application.get_env(:qpdf, :version, @default_version)
  end

  @doc """
  Returns the version of the installed qpdf executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available or cannot be run.
  """
  @spec bin_version() :: {:ok, String.t()} | :error
  def bin_version do
    with {:ok, path} <- find_executable(),
         true <- File.exists?(path) do
      try do
        case System.cmd(path, ["--version"], stderr_to_stdout: true) do
          {result, 0} ->
            case Regex.run(~r/qpdf version (\S+)/, result) do
              [_, version] -> {:ok, version}
              nil -> {:ok, String.trim(result)}
            end

          _ ->
            :error
        end
      rescue
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  @doc """
  Downloads and extracts the qpdf AppImage into priv/native or _build.
  """
  @spec install(keyword()) :: {:ok, String.t()} | {:error, any()}
  def install(opts \\ []) do
    version = Keyword.get(opts, :version) || version()
    target_path = app_run_path(version)

    if Keyword.get(opts, :force, false) or not File.exists?(target_path) do
      do_install(version, opts)
    else
      {:ok, target_path}
    end
  end

  defp do_install(version, opts) do
    case detect_target() do
      {:ok, :linux_x86_64} ->
        download_and_extract_appimage(version, opts)

      {:error, {:unsupported_platform, os, arch}} ->
        case System.find_executable("qpdf") do
          path when is_binary(path) ->
            {:ok, path}

          nil ->
            {:error, {:unsupported_platform, os, arch}}
        end
    end
  end

  @doc """
  Detects the current OS and CPU architecture.
  """
  def detect_target(os \\ nil, arch \\ nil) do
    os = os || :os.type()
    arch = arch || :erlang.system_info(:system_architecture) |> to_string()

    case os do
      {:unix, :linux} ->
        if String.contains?(arch, "x86_64") do
          {:ok, :linux_x86_64}
        else
          {:error, {:unsupported_platform, os, arch}}
        end

      _ ->
        {:error, {:unsupported_platform, os, arch}}
    end
  end

  @doc """
  Returns the priv directory for the :qpdf application.
  """
  def priv_dir do
    case :code.priv_dir(:qpdf) do
      {:error, :bad_name} ->
        Application.app_dir(:qpdf, "priv")

      path when is_list(path) ->
        List.to_string(path)

      path when is_binary(path) ->
        path
    end
  end

  @doc """
  Returns the default qpdf version.
  """
  def default_version, do: @default_version

  @doc """
  Returns the directory where the qpdf native files are stored.
  Uses `_build/qpdf-<version>` when running under Mix to keep `priv/` in the source repository clean,
  and falls back to `priv/native` in releases for the default version.
  """
  def storage_dir(version \\ nil) do
    v = version || version()

    if running_under_mix?() do
      Path.join(Path.dirname(Mix.Project.build_path()), "qpdf-#{v}")
    else
      if v == @default_version do
        Path.join(priv_dir(), "native")
      else
        Path.join([priv_dir(), "native", "qpdf-#{v}"])
      end
    end
  end

  @doc """
  Returns the expected path to the AppRun executable.
  """
  def app_run_path(version \\ nil) do
    v = version || version()
    default_path = Path.join(storage_dir(v), "AppRun")
    priv_path = Path.join([priv_dir(), "native", "AppRun"])

    cond do
      File.exists?(default_path) ->
        default_path

      v == @default_version and File.exists?(priv_path) ->
        priv_path

      true ->
        default_path
    end
  end

  defp running_under_mix? do
    case Application.get_env(:qpdf, :test_mix_mode) do
      val when is_boolean(val) ->
        val

      _ ->
        is_pid(Process.whereis(Mix.ProjectStack)) and Code.ensure_loaded?(Mix.Project)
    end
  end

  @doc """
  Returns the base temporary directory.
  """
  defdelegate tmp_dir, to: Qpdf.Temp

  defp download_and_extract_appimage(version, opts) do
    url =
      Keyword.get(opts, :url) ||
        Application.get_env(
          :qpdf,
          :appimage_url,
          "https://github.com/qpdf/qpdf/releases/download/v#{version}/qpdf-#{version}-x86_64.AppImage"
        )

    Logger.info("[qpdf] Downloading qpdf AppImage v#{version} from #{url}...")

    ensure_network_apps_started!()

    Qpdf.Temp.with_tmp_dir([prefix: "qpdf_installer", sub_dir: false, bytes: 6], fn tmp_dir ->
      appimage_file = Path.join(tmp_dir, "qpdf.AppImage")

      with :ok <- fetch_file(url, appimage_file),
           :ok <- File.chmod(appimage_file, 0o755),
           :ok <- extract_appimage(appimage_file, tmp_dir),
           :ok <- deploy_extracted(tmp_dir, version) do
        {:ok, app_run_path(version)}
      end
    end)
  end

  defp fetch_file(url, destination) do
    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    http_opts = [autoredirect: true, ssl: ssl_opts]
    request = {String.to_charlist(url), []}

    case :httpc.request(:get, request, http_opts, stream: String.to_charlist(destination)) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_, status, reason}, _headers, _body}} ->
        {:error, {:download_failed, status, reason}}

      {:error, reason} ->
        {:error, {:download_failed, reason}}
    end
  end

  defp extract_appimage(appimage_file, tmp_dir) do
    Logger.info("[qpdf] Extracting AppImage...")

    case System.cmd(appimage_file, ["--appimage-extract"], cd: tmp_dir) do
      {_, 0} ->
        extracted_apprun = Path.join([tmp_dir, "squashfs-root", "AppRun"])

        if File.exists?(extracted_apprun) do
          :ok
        else
          {:error, :extracted_apprun_missing}
        end

      {output, code} ->
        {:error, {:extraction_failed, code, output}}
    end
  end

  defp deploy_extracted(tmp_dir, version) do
    dest_dir = storage_dir(version)
    extracted_dir = Path.join(tmp_dir, "squashfs-root")

    File.mkdir_p!(Path.dirname(dest_dir))
    File.rm_rf(dest_dir)

    case File.rename(extracted_dir, dest_dir) do
      :ok ->
        post_deploy(dest_dir)

      {:error, _} ->
        # Fallback to copy if cross-device rename (e.g. tmpfs to ext4) fails
        with {:ok, _} <- File.cp_r(extracted_dir, dest_dir) do
          post_deploy(dest_dir)
        end
    end
  end

  defp post_deploy(native_dir) do
    app_run = Path.join(native_dir, "AppRun")
    File.chmod!(app_run, 0o755)

    qpdf_bin = Path.join([native_dir, "usr", "bin", "qpdf"])
    if File.exists?(qpdf_bin), do: File.chmod!(qpdf_bin, 0o755)

    Logger.info("[qpdf] Successfully installed qpdf to #{native_dir}")
    :ok
  end

  defp ensure_network_apps_started! do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
  end

  @doc false
  def raise_executable_error({:unsupported_platform, os, arch}) do
    raise RuntimeError, """
    No qpdf executable found!
    Auto-download of the qpdf AppImage is currently supported on Linux x86_64.
    Current platform: #{inspect(os)} (#{arch}).

    Please install qpdf via your system package manager (e.g., `brew install qpdf` or `apt install qpdf`),
    or configure the executable path in your config:

        config :qpdf, executable_path: "/path/to/qpdf"
    """
  end

  @doc false
  def raise_executable_error(reason) do
    raise RuntimeError, "Failed to locate or install qpdf executable: #{inspect(reason)}"
  end
end
