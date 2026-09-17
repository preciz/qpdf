defmodule Qpdf.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/preciz/qpdf"

  def project do
    [
      app: :qpdf,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      docs: docs(),
      deps: deps(),
      test_coverage: [summary: [threshold: 90]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.4", only: [:dev, :test]}
    ]
  end

  defp description do
    "Elixir wrapper for the qpdf command-line tool with automatic binary management."
  end

  defp package do
    [
      maintainers: ["Barna Kovacs"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
