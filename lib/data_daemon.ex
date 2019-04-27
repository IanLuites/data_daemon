defmodule DataDaemon do
  @moduledoc ~S"""
  DataDog StatsD reporter.

  ## Quick Setup

  ```elixir
  # In your config/config.exs file
  config :my_app, Sample.DataDog,
    url: "statsd+udp://localhost:8125"

  # In your application code
  defmodule Sample.DataDog do
    @moduledoc ~S"My DataDog reporter."
    use DataDaemon,
      otp_app: :my_app,
      extensions: [:datadog]
  end

  defmodule Sample.App do
    alias Sample.DataDog

    def send_metrics do
      tags = [zone: "us-east-1a"]

      DataDog.gauge("request.queue_depth", 12, tags: tags)

      DataDog.distribution("connections", 123, tags: tags)
      DataDog.histogram("request.file_size", 1034, tags: tags)

      DataDog.timing("request.duration", 34, tags: tags)

      DataDog.increment("request.count_total", tags: tags)
      DataDog.decrement("request.count_total", tags: tags)
      DataDog.count("request.count_total", 2, tags: tags)
    end
  end
  ```
  """

  @typedoc ~S"""
  Metric key.
  """
  @type key :: iodata

  @typedoc ~S"""
  Possible metric values.
  """
  @type value :: integer | float | String.t()

  @typedoc ~S"""
  Supported metric types.
  """
  @type type :: :counter | :gauge | :histogram | :set | :timing

  @typedoc ~S"""
  Metric tag value.
  """
  @type tag ::
          :atom
          | String.Chars.t()
          | {:system, String.t()}
          | {:config, atom, atom}

  @typedoc ~S"""
  Metric tags.
  """
  @type tags :: [tag | {tag, tag}]

  @extensions %{
    datadog: DataDaemon.Extensions.DataDog,
    erlang_vm: DataDaemon.Extensions.VM
  }

  import DataDaemon.Util, only: [config: 5, package: 4]

  @doc @moduledoc
  defmacro __using__(opts \\ []) do
    otp_app = opts[:otp_app] || raise "Must set `otp_app:`."
    otp_config = Application.get_env(otp_app, __CALLER__.module, [])
    config = fn setting, default -> config(opts, otp_app, __CALLER__.module, setting, default) end
    namespace = if ns = config.(:namespace, nil), do: String.replace(ns, ~r/^(.*?)\.*$/, "\\1.")
    decorators = if config.(:decorators, true), do: __MODULE__.Decorators.enable()
    plug = if config.(:plug, true) && Code.ensure_loaded?(Plug), do: __MODULE__.Plug.enable()
    tags = config.(:tags, [])

    mode =
      case config.(:mode, :send) do
        :send -> quote(do: alias(DataDaemon, as: DataDaemonDriver))
        :log -> quote(do: alias(DataDaemon.LogDaemon, as: DataDaemonDriver))
        :test -> quote(do: alias(DataDaemon.TestDaemon, as: DataDaemonDriver))
      end

    extensions =
      case config.(:extensions, []) do
        nil -> []
        extensions when is_list(extensions) -> Enum.map(extensions, &(@extensions[&1] || &1))
        extension -> [@extensions[extension] || extension]
      end

    extension_imports =
      Enum.reduce(
        extensions,
        nil,
        &quote location: :keep do
          unquote(&2)
          use unquote(&1), unquote(opts)
        end
      )

    hound_config = Keyword.merge(opts[:hound] || [], otp_config[:hound] || [])

    quote location: :keep do
      @opts unquote(opts |> Keyword.merge(otp_config) |> Keyword.put(:hound, hound_config))

      ### Base ###
      unquote(mode)

      @doc false
      @spec otp :: atom
      def otp, do: unquote(otp_app)

      @doc false
      @spec child_spec(opts :: Keyword.t()) :: map
      def child_spec(opts \\ []), do: DataDaemon.child_spec(__MODULE__, opts)

      @doc ~S"""
      Start the DataDaemon.
      """
      @spec start_link(opts :: Keyword.t()) :: Supervisor.on_start()
      def start_link(opts \\ []) do
        options =
          @opts
          |> Keyword.merge(Application.get_env(otp(), __MODULE__, []))
          |> Keyword.merge(opts)

        with started = {:ok, _} <- DataDaemonDriver.start_link(__MODULE__, options) do
          Enum.each(unquote(extensions), & &1.init(__MODULE__, options))
          started
        end
      end

      ### Extensions / Plugs ###

      unquote(extension_imports)
      unquote(decorators)
      unquote(plug)

      ### Methods ###

      @doc ~S"""
      Count tracks how many times something happened per second.
      """
      @spec count(DataDaemon.key(), integer, Keyword.t()) :: :ok | {:error, atom}
      def count(key, value, opts \\ []), do: metric(key, value, :counter, opts)

      @doc ~S"""
      Increment is an alias of count with a default of 1.
      """
      @spec increment(DataDaemon.key(), integer | Keyword.t(), Keyword.t()) ::
              :ok | {:error, atom}
      def increment(key, value \\ 1, opts \\ [])

      def increment(key, value, opts) when is_number(value),
        do: metric(key, value, :counter, opts)

      def increment(key, opts, []) when is_list(opts), do: metric(key, 1, :counter, opts)

      @doc ~S"""
      Decrement is just count of -x. (Default: 1)
      """
      @spec decrement(DataDaemon.key(), integer | Keyword.t(), Keyword.t()) ::
              :ok | {:error, atom}
      def decrement(key, value, opts) when is_number(value),
        do: metric(key, -value, :counter, opts)

      def decrement(key, opts, []) when is_list(opts), do: metric(key, -1, :counter, opts)

      @doc ~S"""
      Gauge measures the value of a metric at a particular time.
      """
      @spec gauge(DataDaemon.key(), integer, Keyword.t()) :: :ok | {:error, atom}
      def gauge(key, value, opts \\ []), do: metric(key, value, :gauge, opts)

      @doc ~S"""
      Histogram tracks the statistical distribution of a set of values on each host.
      """
      @spec histogram(DataDaemon.key(), integer, Keyword.t()) :: :ok | {:error, atom}
      def histogram(key, value, opts \\ []), do: metric(key, value, :histogram, opts)

      @doc ~S"""
      Set counts the number of unique elements in a group.
      """
      @spec set(DataDaemon.key(), String.t(), Keyword.t()) :: :ok | {:error, atom}
      def set(key, value, opts \\ []), do: metric(key, value, :set, opts)

      @doc ~S"""
      Timing sends timing information.
      """
      @spec timing(DataDaemon.key(), integer, Keyword.t()) :: :ok | {:error, atom}
      def timing(key, value, opts \\ []), do: metric(key, value, :timing, opts)

      @doc ~S"""
      """
      @spec metric(DataDaemon.key(), DataDaemon.value(), DataDaemon.type(), Keyword.t()) ::
              :ok | {:error, atom}
      def metric(key, value, type, opts \\ []),
        do:
          send_metric(
            unquote(if namespace, do: quote(do: [unquote(namespace), key]), else: quote(do: key)),
            value,
            type,
            unquote(
              if tags == [],
                do: quote(do: opts),
                else:
                  quote(do: Keyword.update(opts, :tags, unquote(tags), &(unquote(tags) ++ &1)))
            )
          )

      defp send_metric(key, value, type, opts),
        do: DataDaemonDriver.metric(__MODULE__, key, value, type, opts)
    end
  end

  ### Connection Logic ###

  @doc false
  @spec child_spec(module, opts :: Keyword.t()) :: map
  def child_spec(module, opts \\ []) do
    %{
      id: module,
      start: {module, :start_link, [opts]}
    }
  end

  alias DataDaemon.{Hound, Resolver}

  @doc false
  @spec start_link(module, Keyword.t()) :: Supervisor.on_start()
  def start_link(module, opts \\ []) do
    children = [
      Resolver.child_spec(module, opts),
      Hound.child_spec(module, opts)
      | Keyword.get(opts, :children, [])
    ]

    opts = [strategy: :one_for_one, name: Module.concat(module, Supervisor)]
    Supervisor.start_link(children, opts)
  end

  @doc false
  @spec metric(module, DataDaemon.key(), DataDaemon.value(), DataDaemon.type(), Keyword.t()) ::
          :ok | {:error, atom}
  def metric(reporter, key, value, type, opts \\ []) do
    :poolboy.transaction(
      reporter,
      &GenServer.cast(&1, {:metric, package(key, value, type, opts)}),
      5000
    )
  end
end
