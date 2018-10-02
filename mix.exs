defmodule DataDaemon.MixProject do
  use Mix.Project

  def project do
    [
      app: :data_daemon,
      version: "0.0.1",
      description: "An Elixir StatsD client made for DataDog.",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      # dialyzer: [ignore_warnings: "dialyzer.ignore-warnings", plt_add_deps: true],

      # Docs
      name: "Data Daemon",
      source_url: "https://github.com/IanLuites/data_daemon",
      homepage_url: "https://github.com/IanLuites/data_daemon",
      docs: [
        main: "readme",
        extras: ["README.md"]
      ]
    ]
  end

  def package do
    [
      name: :data_daemon,
      maintainers: ["Ian Luites"],
      licenses: ["MIT"],
      files: [
        # Elixir
        "lib/data_daemon",
        "lib/data_daemon.ex",
        ".formatter.exs",
        "mix.exs",
        "README*",
        "LICENSE*"
      ],
      links: %{
        "GitHub" => "https://github.com/IanLuites/data_daemon"
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:poolboy, "~> 1.5"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
