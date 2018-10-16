defmodule DataDaemon.LogDaemon do
  @moduledoc false
  import DataDaemon.Util, only: [package: 4]
  import IO.ANSI, only: [format: 1]
  import Logger.Formatter, only: [format_time: 1]
  import Logger.Utils, only: [timestamp: 1]

  @doc false
  @spec start_link(module) :: Supervisor.on_start()
  def start_link(_module), do: {:ok, spawn(fn -> Process.sleep(:infinity) end)}

  @doc false
  @spec metric(module, DataDaemon.key(), DataDaemon.value(), DataDaemon.type(), Keyword.t()) ::
          :ok | {:error, atom}
  def metric(_reporter, key, value, type, opts \\ []) do
    {_, time} = timestamp(false)
    IO.puts(format([:blue, [format_time(time), " [metric] ", package(key, value, type, opts)]]))
  end
end
