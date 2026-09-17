defmodule Qpdf.Encryption do
  @moduledoc false

  @doc """
  Builds CLI arguments for `--encrypt` based on user options.
  """
  @spec build_encrypt_args(keyword()) ::
          {:ok, [String.t()]}
          | {:error, :weak_crypto_not_allowed | :invalid_key_length | :missing_owner_password}
  def build_encrypt_args(opts) do
    bits = Keyword.get(opts, :key_length, 256)

    with :ok <- validate_bits(bits),
         :ok <- validate_crypto_safety(opts, bits),
         :ok <- validate_password_security(opts, bits) do
      {:ok, do_build_encrypt_args(opts, bits)}
    end
  end

  defp validate_bits(bits) when bits in [40, 128, 256], do: :ok
  defp validate_bits(_), do: {:error, :invalid_key_length}

  defp validate_crypto_safety(opts, 40) do
    if Keyword.get(opts, :allow_weak_crypto, false),
      do: :ok,
      else: {:error, :weak_crypto_not_allowed}
  end

  defp validate_crypto_safety(opts, 128) do
    if Keyword.get(opts, :use_aes, true) or Keyword.get(opts, :allow_weak_crypto, false) do
      :ok
    else
      {:error, :weak_crypto_not_allowed}
    end
  end

  defp validate_crypto_safety(_opts, _bits), do: :ok

  defp validate_password_security(opts, 256) do
    user_pass = Keyword.get(opts, :user_password)
    owner_pass = Keyword.get(opts, :owner_password)
    allow_insecure = Keyword.get(opts, :allow_insecure, false)

    if not empty_or_nil?(user_pass) and empty_or_nil?(owner_pass) and not allow_insecure do
      {:error, :missing_owner_password}
    else
      :ok
    end
  end

  defp validate_password_security(_opts, _bits), do: :ok

  defp empty_or_nil?(nil), do: true
  defp empty_or_nil?(""), do: true
  defp empty_or_nil?(_), do: false

  defp do_build_encrypt_args(opts, bits) do
    user_pass = Keyword.get(opts, :user_password)
    owner_pass = Keyword.get(opts, :owner_password)
    use_aes = Keyword.get(opts, :use_aes, true)
    allow_weak = Keyword.get(opts, :allow_weak_crypto, false)
    allow_insecure = Keyword.get(opts, :allow_insecure, false)

    weak_flag = if allow_weak, do: ["--allow-weak-crypto"], else: []
    pass_args = build_pass_args(user_pass, owner_pass)
    aes_arg = if bits == 128, do: [if(use_aes, do: "--use-aes=y", else: "--use-aes=n")], else: []

    insecure_arg =
      if bits == 256 and allow_insecure and not empty_or_nil?(user_pass) and
           empty_or_nil?(owner_pass),
         do: ["--allow-insecure"],
         else: []

    permission_args = build_permission_args(opts, bits)

    weak_flag ++
      ["--encrypt"] ++
      pass_args ++
      ["--bits=#{bits}"] ++
      aes_arg ++
      insecure_arg ++
      permission_args
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

  defp build_permission_args(opts, 40) do
    [
      print_perm_arg_40(Keyword.get(opts, :print)),
      modify_perm_arg_40(Keyword.get(opts, :modify)),
      flag_perm_arg("--extract", Keyword.get(opts, :extract)),
      flag_perm_arg("--annotate", Keyword.get(opts, :annotate))
    ]
    |> List.flatten()
  end

  defp build_permission_args(opts, _bits) do
    [
      print_perm_arg(Keyword.get(opts, :print)),
      modify_perm_arg(Keyword.get(opts, :modify)),
      flag_perm_arg("--extract", Keyword.get(opts, :extract)),
      flag_perm_arg("--annotate", Keyword.get(opts, :annotate)),
      if(Keyword.get(opts, :cleartext_metadata), do: ["--cleartext-metadata"], else: [])
    ]
    |> List.flatten()
  end

  defp print_perm_arg_40(val) when val in [:none, false, "n"], do: ["--print=n"]
  defp print_perm_arg_40(val) when val in [:low, :full, true, "y"], do: ["--print=y"]
  defp print_perm_arg_40(_), do: []

  defp modify_perm_arg_40(val) when val in [:none, false, "n"], do: ["--modify=n"]

  defp modify_perm_arg_40(val) when val in [:assembly, :form, :annotate, :all, true, "y"],
    do: ["--modify=y"]

  defp modify_perm_arg_40(_), do: []

  defp print_perm_arg(val) when val in [:none, :low, :full], do: ["--print=#{val}"]
  defp print_perm_arg(true), do: ["--print=full"]
  defp print_perm_arg(false), do: ["--print=none"]
  defp print_perm_arg(_), do: []

  defp modify_perm_arg(val) when val in [:none, :assembly, :form, :annotate, :all],
    do: ["--modify=#{val}"]

  defp modify_perm_arg(true), do: ["--modify=all"]
  defp modify_perm_arg(false), do: ["--modify=none"]
  defp modify_perm_arg(_), do: []

  defp flag_perm_arg(flag, true), do: ["#{flag}=y"]
  defp flag_perm_arg(flag, false), do: ["#{flag}=n"]
  defp flag_perm_arg(_flag, _), do: []

  defp build_encryption_map(output) do
    %{
      encrypted: true,
      r: parse_int_regex(output, ~r/^R[ \t]*=[ \t]*(\d+)/m),
      p: parse_int_regex(output, ~r/^P[ \t]*=[ \t]*(-?\d+)/m),
      v: parse_int_regex(output, ~r/^V[ \t]*=[ \t]*(\d+)/m),
      user_password: parse_string_regex(output, ~r/^User password[ \t]*=[ \t]*(.*)$/m),
      password_matched: parse_password_matched(output),
      stream_method: parse_string_regex(output, ~r/^stream encryption method:[ \t]*(.*)$/m),
      string_method: parse_string_regex(output, ~r/^string encryption method:[ \t]*(.*)$/m),
      file_method: parse_string_regex(output, ~r/^file encryption method:[ \t]*(.*)$/m),
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
