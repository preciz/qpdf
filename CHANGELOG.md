# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-17

### Added
- Complete Elixir wrapper around the `qpdf` CLI.
- Zero-RAM streaming pipelines with support for in-memory `binary` and disk `{:file, path}` inputs.
- Streaming output to disk using the `into:` option without holding documents in BEAM heap.
- Automated distribution and extraction of official `qpdf` AppImage binaries for Linux x86_64.
- Automatic detection of system `qpdf` executable on other platforms (macOS, ARM Linux).
- Mix task `mix qpdf.install` with `--if-missing`, `--force`, and `--version` flags.
- `QPDF_PATH` environment variable and `:executable_path` configuration support.
- `Qpdf.bin_version/0` for querying the installed `qpdf` executable version.
- Concurrency-safe installer with re-entrant `:global` transaction locking.
- Strict TLS peer verification with OS root CA trust store during AppImage downloads.
- Comprehensive PDF operations:
  - Page selection, range slicing, and extraction (`pages/2,3`).
  - Document merging with per-file page selections (`merge/2`).
  - Document splitting into single pages or page chunks (`split_pages/2,3`).
  - Watermarks, stamps, and letterheads (`overlay/3`, `underlay/3`).
  - File size and stream optimization (`optimize/2`, `optimize_images/2`, `linearize/2`).
  - Attachment embedding and extraction (Factur-X / ZUGFeRD e-invoices, XML, CSV).
  - Page geometry, bounding boxes, and dimensions (`dimensions/1,2`).
  - Encryption, decryption, password checking, and metadata inspection.
