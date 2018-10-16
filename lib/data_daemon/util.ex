defmodule DataDaemon.Util do
  @moduledoc false

  @doc ~S"""
  Pack a metric as iodata.
  """
  @spec package(DataDaemon.key(), DataDaemon.value(), DataDaemon.type(), Keyword.t()) :: iodata
  def package(key, value, type, opts \\ []) do
    [key, ?:, pack_value(value), ?|, pack_type(type)]
    |> tag(opts[:tags])
  end

  @spec pack_value(DataDaemon.value()) :: iodata
  defp pack_value(value) when is_list(value), do: value
  defp pack_value(value), do: to_string(value)

  @spec tag(iodata, nil | DataDaemon.tags()) :: iodata
  defp tag(data, nil), do: data
  defp tag(data, []), do: data
  defp tag(data, tags), do: [data, "|#", Enum.intersperse(Enum.map(tags, &pack_tag/1), ?,)]

  @spec pack_type(DataDaemon.type()) :: String.t()
  defp pack_type(:counter), do: "c"
  defp pack_type(:distribution), do: "d"
  defp pack_type(:gauge), do: "g"
  defp pack_type(:histogram), do: "h"
  defp pack_type(:set), do: "s"
  defp pack_type(:timing), do: "ms"
  defp pack_type(type), do: type

  defp pack_tag({tag, value}), do: [to_string(tag), ?:, pack_tag_value(value)]
  defp pack_tag(tag), do: to_string(tag)

  defp pack_tag_value({:system, env_var}), do: System.get_env(env_var)
  defp pack_tag_value({:config, app, value}), do: Application.get_env(app, value)
  defp pack_tag_value(value), do: to_string(value)

  @unix ~N[1970-01-01 00:00:00]
  @doc ~S"""
  Convert a given timestamp to iso8601.

  Passing `nil` will return the current time.
  """
  @spec iso8601(NaiveDateTime.t() | DateTime.t() | nil | integer) :: String.t()
  def iso8601(nil), do: NaiveDateTime.to_iso8601(NaiveDateTime.utc_now()) <> "Z"
  def iso8601(ts = %NaiveDateTime{}), do: NaiveDateTime.to_iso8601(ts) <> "Z"
  def iso8601(ts = %DateTime{}), do: DateTime.to_iso8601(ts)
  def iso8601(ts) when is_integer(ts), do: iso8601(NaiveDateTime.add(@unix, ts, :millisecond))

  @doc ~S"""
  Fetch a setting from either the passed options or the application config.
  """
  @spec config(Keyword.t(), atom, atom, atom, any) :: any
  def config(opts, app, key, setting, default \\ nil) do
    Keyword.get_lazy(
      opts,
      setting,
      fn ->
        Keyword.get(Application.get_env(app, key, []), setting, default)
      end
    )
  end
end
