defmodule Qpdf.EncryptionTest do
  use ExUnit.Case, async: true

  alias Qpdf.Encryption

  describe "build_encrypt_args/1" do
    test "builds 256-bit encryption arguments with default settings" do
      assert {:ok, args} = Encryption.build_encrypt_args([])
      assert "--encrypt" in args
      assert "--bits=256" in args
    end

    test "includes passwords and allow-insecure flag when only user password is provided for 256-bit" do
      assert {:ok, args} = Encryption.build_encrypt_args(user_password: "userpass")
      assert "--user-password=userpass" in args
      assert "--allow-insecure" in args

      assert {:ok, args_both} =
               Encryption.build_encrypt_args(user_password: "u", owner_password: "o")

      assert "--user-password=u" in args_both
      assert "--owner-password=o" in args_both
      refute "--allow-insecure" in args_both
    end

    test "does not include allow-insecure for 128-bit or 40-bit with only user password" do
      assert {:ok, args_128} =
               Encryption.build_encrypt_args(key_length: 128, user_password: "userpass")

      refute "--allow-insecure" in args_128

      assert {:ok, args_40} =
               Encryption.build_encrypt_args(
                 key_length: 40,
                 user_password: "userpass",
                 allow_weak_crypto: true
               )

      refute "--allow-insecure" in args_40
    end

    test "formats permissions flags accurately for 128-bit and 256-bit" do
      opts = [
        key_length: 128,
        print: :full,
        modify: :assembly,
        extract: false,
        annotate: true,
        cleartext_metadata: true
      ]

      assert {:ok, args} = Encryption.build_encrypt_args(opts)
      assert "--bits=128" in args
      assert "--use-aes=y" in args
      assert "--print=full" in args
      assert "--modify=assembly" in args
      assert "--extract=n" in args
      assert "--annotate=y" in args
      assert "--cleartext-metadata" in args
    end

    test "formats permissions flags accurately for 40-bit" do
      opts = [
        key_length: 40,
        allow_weak_crypto: true,
        print: :none,
        modify: :form,
        extract: false,
        annotate: true,
        cleartext_metadata: true
      ]

      assert {:ok, args} = Encryption.build_encrypt_args(opts)
      assert "--allow-weak-crypto" in args
      assert "--bits=40" in args
      assert "--print=n" in args
      assert "--modify=y" in args
      assert "--extract=n" in args
      assert "--annotate=y" in args
      refute "--cleartext-metadata" in args

      assert {:ok, args_40_alt} =
               Encryption.build_encrypt_args(
                 key_length: 40,
                 allow_weak_crypto: true,
                 print: :full,
                 modify: :none
               )

      assert "--print=y" in args_40_alt
      assert "--modify=n" in args_40_alt

      assert {:ok, bool_args} =
               Encryption.build_encrypt_args(print: true, modify: false)

      assert "--print=full" in bool_args
      assert "--modify=none" in bool_args

      assert {:ok, bool_args_rev} =
               Encryption.build_encrypt_args(print: false, modify: true)

      assert "--print=none" in bool_args_rev
      assert "--modify=all" in bool_args_rev
    end

    test "rejects 40-bit without allow_weak_crypto: true" do
      assert {:error, :weak_crypto_not_allowed} = Encryption.build_encrypt_args(key_length: 40)
    end

    test "rejects 128-bit RC4 without allow_weak_crypto: true" do
      assert {:error, :weak_crypto_not_allowed} =
               Encryption.build_encrypt_args(key_length: 128, use_aes: false)

      assert {:ok, args} =
               Encryption.build_encrypt_args(
                 key_length: 128,
                 use_aes: false,
                 allow_weak_crypto: true
               )

      assert "--allow-weak-crypto" in args
      assert "--use-aes=n" in args
    end

    test "rejects invalid key lengths" do
      assert {:error, :invalid_key_length} = Encryption.build_encrypt_args(key_length: 512)
    end
  end

  describe "parse_info/1" do
    test "parses unencrypted output" do
      output = "File is not encrypted\n"
      assert {:ok, %{encrypted: false}} = Encryption.parse_info(output)
    end

    test "parses encrypted output with ciphers, permissions, and passwords" do
      sample_output = """
      R = 6
      P = -3392
      V = 5
      User password = secret
      Supplied password is user password
      stream encryption method: AESv3
      string encryption method: AESv3
      file encryption method: AESv3
      extract for any purpose: allowed
      extract for accessibility: allowed
      print low resolution: allowed
      print high resolution: not allowed
      modify document assembly: not allowed
      modify forms: not allowed
      modify annotations: allowed
      modify other: not allowed
      modify anything: not allowed
      """

      assert {:ok, info} = Encryption.parse_info(sample_output)
      assert info.encrypted == true
      assert info.r == 6
      assert info.p == -3392
      assert info.v == 5
      assert info.user_password == "secret"
      assert info.password_matched == :user
      assert info.stream_method == "AESv3"
      assert info.string_method == "AESv3"
      assert info.file_method == "AESv3"

      assert info.permissions.extract == true
      assert info.permissions.extract_accessibility == true
      assert info.permissions.print_low == true
      assert info.permissions.print_high == false
      assert info.permissions.modify_assembly == false
      assert info.permissions.modify_forms == false
      assert info.permissions.modify_annotations == true
      assert info.permissions.modify_other == false
      assert info.permissions.modify_anything == false
    end

    test "handles owner password match" do
      sample = "R = 5\nP = -4\nV = 5\nSupplied password is owner password\n"
      assert {:ok, info} = Encryption.parse_info(sample)
      assert info.password_matched == :owner
    end
  end
end
