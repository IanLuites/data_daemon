defmodule DataDaemon.LogDaemon do
  @moduledoc false
  import DataDaemon.Util, only: [package: 4]
  import IO.ANSI, only: [format: 1]
  @doc false
  @spec start_link(module, Keyword.t()) :: Supervisor.on_start()
  def start_link(module, opts \\ []) do
    children = Keyword.get(opts, :children, [])
    opts = [strategy: :one_for_one, name: Module.concat(module, Supervisor)]
    Supervisor.start_link(children, opts)
  end

  if Version.match?(System.version(), "< 1.15.0") do
    import Logger.Formatter, only: [format_time: 1]

    @doc false
    @spec metric(module, DataDaemon.key(), DataDaemon.value(), DataDaemon.type(), Keyword.t()) ::
            :ok | {:error, atom}
    def metric(_reporter, key, value, type, opts \\ []) do
      {_, time} = Logger.Utils.timestamp(false)
      IO.puts(format([:blue, [format_time(time), " [metric] ", package(key, value, type, opts)]]))
    end
  else
    import Logger.Formatter, only: [format_date: 1, format_time: 1]

    @doc false
    @spec metric(module, DataDaemon.key(), DataDaemon.value(), DataDaemon.type(), Keyword.t()) ::
            :ok | {:error, atom}
    def metric(_reporter, key, value, type, opts \\ []) do
      system_time = :os.system_time(:microsecond)
      {date, time} = Logger.Formatter.system_time_to_date_time_ms(system_time, false)

      IO.puts(
        format([
          :blue,
          [format_date(date), format_time(time), " [metric] ", package(key, value, type, opts)]
        ])
      )
    end
  end
end
