defmodule Qpdf.Encryption do
  @moduledoc false

  @doc """
  Builds CLI arguments for `--encrypt` based on user options.
  """
  @spec build_encrypt_args(keyword()) :: [String.t()]
  def build_encrypt_args(opts) do
    user_pass = Keyword.get(opts, :user_password)
    owner_pass = Keyword.get(opts, :owner_password)
    bits = Keyword.get(opts, :key_length, 256)

    pass_args = build_pass_args(user_pass, owner_pass)
    insecure_arg = if user_pass && !owner_pass, do: ["--allow-insecure"], else: []
    permission_args = build_permission_args(opts)

    ["--encrypt"] ++ pass_args ++ ["--bits=#{bits}"] ++ insecure_arg ++ permission_args
  end

  @doc """
  Parses raw output from `qpdf --show-encryption` into a structured map.
  """
  @spec parse_info(String.t()) :: {:ok, map()}
  def parse_info(output) do
    if String.contains?(output, "File is not encrypted") do
      {:ok, %{encrypted: false}}
    else
      {:ok, build_encryption_map(output)}
    end
  end

  defp build_pass_args(user_pass, owner_pass) do
    user_args = if user_pass, do: ["--user-password=#{user_pass}"], else: []
    owner_args = if owner_pass, do: ["--owner-password=#{owner_pass}"], else: []
    user_args ++ owner_args
  end

  defp build_permission_args(opts) do
    [
      print_perm_arg(Keyword.get(opts, :print)),
      modify_perm_arg(Keyword.get(opts, :modify)),
      flag_perm_arg("--extract", Keyword.get(opts, :extract)),
      flag_perm_arg("--annotate", Keyword.get(opts, :annotate)),
      if(Keyword.get(opts, :cleartext_metadata), do: ["--cleartext-metadata"], else: [])
    ]
    |> List.flatten()
  end

  defp print_perm_arg(val) when val in [:none, :low, :full], do: ["--print=#{val}"]
  defp print_perm_arg(_), do: []

  defp modify_perm_arg(val) when val in [:none, :assembly, :form, :annotate, :all],
    do: ["--modify=#{val}"]

  defp modify_perm_arg(_), do: []

  defp flag_perm_arg(flag, true), do: ["#{flag}=y"]
  defp flag_perm_arg(flag, false), do: ["#{flag}=n"]
  defp flag_perm_arg(_flag, _), do: []

  defp build_encryption_map(output) do
    %{
      encrypted: true,
      r: parse_int_regex(output, ~r/^R\s*=\s*(\d+)/m),
      p: parse_int_regex(output, ~r/^P\s*=\s*(-?\d+)/m),
      v: parse_int_regex(output, ~r/^V\s*=\s*(\d+)/m),
      user_password: parse_string_regex(output, ~r/^User password\s*=\s*(.*)$/m),
      password_matched: parse_password_matched(output),
      stream_method: parse_string_regex(output, ~r/^stream encryption method:\s*(.*)$/m),
      string_method: parse_string_regex(output, ~r/^string encryption method:\s*(.*)$/m),
      file_method: parse_string_regex(output, ~r/^file encryption method:\s*(.*)$/m),
      permissions: parse_encryption_permissions(output)
    }
  end

  defp parse_int_regex(text, regex) do
    case Regex.run(regex, text) do
      [_, val] -> String.to_integer(val)
      _ -> nil
    end
  end

  defp parse_string_regex(text, regex) do
    case Regex.run(regex, text) do
      [_, val] ->
        trimmed = String.trim(val)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  defp parse_password_matched(output) do
    cond do
      String.contains?(output, "Supplied password is user password") -> :user
      String.contains?(output, "Supplied password is owner password") -> :owner
      true -> nil
    end
  end

  defp parse_encryption_permissions(output) do
    %{
      extract: String.contains?(output, "extract for any purpose: allowed"),
      extract_accessibility: String.contains?(output, "extract for accessibility: allowed"),
      print_low: String.contains?(output, "print low resolution: allowed"),
      print_high: String.contains?(output, "print high resolution: allowed"),
      modify_assembly: String.contains?(output, "modify document assembly: allowed"),
      modify_forms: String.contains?(output, "modify forms: allowed"),
      modify_annotations: String.contains?(output, "modify annotations: allowed"),
      modify_other: String.contains?(output, "modify other: allowed"),
      modify_anything: String.contains?(output, "modify anything: allowed")
    }
  end
end
