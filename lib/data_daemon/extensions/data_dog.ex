defmodule DataDaemon.Extensions.DataDog do
  @moduledoc false
  import DataDaemon.Util, only: [unix_timestamp: 1]

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

  defp add_event_opt(:timestamp, value, event),
    do: [event, "|d:", to_string(unix_timestamp(value))]

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

  defmacro __using__(_opts \\ []) do
    quote do
      @doc ~S"""
      Distribution tracks the statistical distribution of a set of values across your infrastructure.
      """
      @spec distribution(DataDaemon.key(), integer, Keyword.t()) :: :ok | {:error, atom}
      def distribution(key, value, opts \\ []), do: metric(key, value, :distribution, opts)

      import DataDaemon.Extensions.DataDog, only: [build_event: 2]

      @doc ~S"""
      Create an event for the DataDog event stream.

      ## Options

      | **Option**                     | **Description**                                                                           |
      |--------------------------------|-------------------------------------------------------------------------------------------|
      | `:timestamp` (optional)        | Add a timestamp to the event. Default is the current timestamp.                           |
      | `:hostname` (optional)         | Add a hostname to the event. No default.                                                  |
      | `:aggregation_key` (optional)  | Add an aggregation key to group the event with others that have the same key. No default. |
      | `:priority` (optional)         | Set to `:normal` or `:low`. Default `:normal`.                                            |
      | `:source_type_name` (optional) | Add a source type to the event. No default.                                               |
      | `:alert_type` (optional)       | Set to `:error`, `:warning`, `:info` or `:success`. Default `:info`.                      |
      """
      @spec event(String.t(), String.t(), Keyword.t()) :: String.t()
      def event(title, text, opts \\ []) do
        text = String.replace(text, "\n", "\\\\n")

        metric(
          "_e{#{String.length(title)},#{String.length(text)}}",
          title,
          build_event(text, opts),
          opts
        )
      end
    end
  end
end
