defmodule DataDaemon.Util do
  @moduledoc false

  @doc ~S"""
  Pack a metric as iodata.
  """
  @spec package(DataDaemon.key(), DataDaemon.value(), DataDaemon.type(), Keyword.t()) :: iodata
  def package(key, value, type, opts \\ []) do
    [key, ?:, to_string(value), ?|, pack_type(type)]
    |> tag(opts[:tags])
  end

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

  defp pack_tag({tag, value}), do: [to_string(tag), ?:, pack_value(value)]
  defp pack_tag(tag), do: to_string(tag)

  defp pack_value({:system, env_var}), do: System.get_env(env_var)
  defp pack_value(value), do: to_string(value)

  @unix ~N[1970-01-01 00:00:00]
  @doc ~S"""
  Convert a given timestamp to unix epoch timestamp.

  Passing `nil` will return the current time.
  """
  @spec unix_timestamp(NaiveDateTime.t() | DateTime.t() | nil | integer) :: integer
  def unix_timestamp(nil), do: :erlang.system_time(:milli_seconds)
  def unix_timestamp(ts = %NaiveDateTime{}), do: NaiveDateTime.diff(ts, @unix, :millisecond)
  def unix_timestamp(ts = %DateTime{}), do: DateTime.to_unix(ts)
  def unix_timestamp(ts) when is_integer(ts), do: ts
end
