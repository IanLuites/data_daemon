defmodule DataDaemon.Extensions.DataDog do
  @moduledoc false
  import DataDaemon.Util, only: [config: 5, iso8601: 1]

  @event_fields ~w(
    timestamp
    hostname
    aggregation_key
    priority
    source_type_name
    alert_type
  )a

  @doc false
  @spec build_event(String.t(), Keyword.t()) :: iodata
  def build_event(text, opts \\ []),
    do: Enum.reduce(@event_fields, text, &add_event_opt(&1, opts[&1], &2))

  @spec add_event_opt(atom, any, iodata) :: iodata
  defp add_event_opt(opt, {:system, env}, event),
    do: add_event_opt(opt, System.get_env(env), event)

  defp add_event_opt(:timestamp, value, event), do: [event, "|d:", iso8601(value)]

  defp add_event_opt(:hostname, nil, event), do: event
  defp add_event_opt(:hostname, hostname, event), do: [event, "|h:", hostname]

  defp add_event_opt(:aggregation_key, nil, event), do: event
  defp add_event_opt(:aggregation_key, key, event), do: [event, "|k:", key]

  defp add_event_opt(:priority, nil, event), do: [event, "|p:normal"]
  defp add_event_opt(:priority, priority, event), do: [event, "|p:", to_string(priority)]

  defp add_event_opt(:source_type_name, nil, event), do: event
  defp add_event_opt(:source_type_name, name, event), do: [event, "|s:", name]

  defp add_event_opt(:alert_type, nil, event), do: [event, "|t:info"]
  defp add_event_opt(:alert_type, type, event), do: [event, "|t:", to_string(type)]

  @doc false
  @spec child_spec(module, Keyword.t()) :: false
  def child_spec(_daemon, _opts \\ []), do: false

  @doc false
  @spec init(module, Keyword.t()) :: :ok
  def init(daemon, opts \\ []) do
    handler =
      opts[:error_handler] ||
        Keyword.get(Application.get_env(opts[:otp_app], daemon, []), :error_handler, false)

    if handler do
      level = if(handler === true, do: :info, else: handler)

      :error_logger.add_report_handler(
        DataDaemon.Extensions.DataDog.ErrorHandler,
        {daemon, level}
      )

      Logger.add_backend({DataDaemon.Extensions.DataDog.ErrorHandler, {daemon, level}})
    end

    :ok
  end

  defmacro __using__(opts \\ []) do
    tags = config(opts, opts[:otp_app], __CALLER__.module, :tags, [])

    quote location: :keep do
      @doc """
      Distribution tracks the statistical distribution of a set of values across your infrastructure.

      The value for the given metric key needs to be an integer.

      ## Example

      ```elixir
      iex> #{inspect(__MODULE__)}.distribution("connections", 123)
      :ok

      iex> #{inspect(__MODULE__)}.distribution("connections", 123, zone: "us-east-1a")
      :ok
      ```
      """
      @spec distribution(DataDaemon.key(), integer, Keyword.t()) :: :ok | {:error, atom}
      def distribution(key, value, opts \\ []), do: metric(key, value, "d", opts)

      import DataDaemon.Extensions.DataDog, only: [build_event: 2]

      @doc """
      Create an event for the DataDog event stream.

      The event consist of a string title and text,
      the latter can be multi-line.

      ## Options

      | **Option**                     | **Description**                                                                           |
      |--------------------------------|-------------------------------------------------------------------------------------------|
      | `:timestamp` (optional)        | Add a timestamp to the event. Default is the current timestamp.                           |
      | `:hostname` (optional)         | Add a hostname to the event. No default.                                                  |
      | `:aggregation_key` (optional)  | Add an aggregation key to group the event with others that have the same key. No default. |
      | `:priority` (optional)         | Set to `:normal` or `:low`. Default `:normal`.                                            |
      | `:source_type_name` (optional) | Add a source type to the event. No default.                                               |
      | `:alert_type` (optional)       | Set to `:error`, `:warning`, `:info` or `:success`. Default `:info`.                      |

      ## Example

      ```elixir
      iex> #{inspect(__MODULE__)}.event("Event Title", "Event body.\\nMore details")
      :ok

      iex> #{inspect(__MODULE__)}.event("Event Title", "Event body.\\nMore details", zone: "us-east-1a")
      :ok
      ```
      """
      @spec event(String.t(), String.t(), Keyword.t()) :: :ok | {:error, atom}
      def event(title, text, opts \\ []) do
        text = String.replace(text, "\n", "\\n")

        __MODULE__.Driver.send_metric(
          "_e{#{String.length(title)},#{String.length(text)}}",
          title,
          build_event(text, opts),
          unquote(
            if tags == [],
              do: quote(do: opts),
              else: quote(do: Keyword.update(opts, :tags, unquote(tags), &(unquote(tags) ++ &1)))
          )
        )
      end
    end
  end

  defmodule ErrorHandler do
    @moduledoc false
    @behaviour :gen_event
    @unix_g 62_167_219_200

    @ignored ~w(info_report)a

    @doc false
    @impl :gen_event
    def init({_, {module, level}}) do
      {:ok, hostname} = :inet.gethostname()
      {:ok, %{module: module, hostname: hostname, level: upgrade_level(level)}}
    end

    @doc false
    @impl :gen_event
    def handle_event(event, state)

    def handle_event(:flush, state), do: {:ok, state}

    def handle_event({_level, gl, _event}, state) when node(gl) != node(), do: {:ok, state}
    def handle_event({level, _gl, _event}, state) when level in @ignored, do: {:ok, state}

    def handle_event(
          {level, _gl, {Logger, message, timestamp, meta}},
          state = %{module: module, hostname: hostname, level: min_level}
        ) do
      unless Logger.compare_levels(min_level, level) == :gt do
        level = translate_level(level)
        {{year, month, day}, {hour, minute, second, _millisecond}} = timestamp
        message = if is_list(message), do: :erlang.iolist_to_binary(message), else: message

        ts =
          :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}}) -
            @unix_g

        case String.split(message, "\n", parts: 2, trim: true) do
          [title] ->
            report(module, level, title, inspect(meta), ts, hostname)

          [title, message] ->
            report(module, level, title, message <> "\n\n" <> inspect(meta), ts, hostname)
        end
      end

      {:ok, state}
    end

    def handle_event({_level, _gl, _event}, state) do
      # Erlang errors, implement at later point
      {:ok, state}
    end

    @spec report(
            atom,
            :error | :info | :debug | :warn,
            String.t(),
            String.t(),
            integer,
            String.t()
          ) :: atom
    defp report(module, level, title, message, timestamp, hostname) do
      module.event(title, message,
        timestamp: timestamp,
        alert_type: level,
        hostname: hostname
      )
    end

    @spec translate_level(atom) :: atom
    defp translate_level(:error), do: :error
    defp translate_level(:info), do: :info
    defp translate_level(:debug), do: :info
    defp translate_level(:warn), do: :warning

    @spec upgrade_level(atom) :: atom
    defp upgrade_level(level)

    if Version.match?(System.version(), ">= 1.15.0") do
      defp upgrade_level(:warn), do: :warning
    end

    defp upgrade_level(level), do: level

    @doc false
    @impl :gen_event
    def handle_call(request, _state), do: exit({:bad_call, request})

    @doc false
    @impl :gen_event
    def handle_info(_message, state), do: {:ok, state}
    @doc false
    @impl :gen_event
    def terminate(_reason, _state), do: :ok

    @doc false
    @impl :gen_event
    def code_change(_old_vsn, state, _extra), do: {:ok, state}
  end
end
