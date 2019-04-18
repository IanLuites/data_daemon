defmodule DataDaemon.Hound do
  @moduledoc false
  use GenServer
  require Logger
  alias DataDaemon.Resolver

  @header_size 7
  @delimiter "\n"
  @delimiter_size 1

  @doc false
  @spec child_spec(atom, opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(pool, opts \\ []) do
    hound = opts[:hound] || []

    :poolboy.child_spec(
      pool,
      [
        name: {:local, pool},
        worker_module: __MODULE__,
        size: resolve_config(hound, :size, 1),
        max_overflow: resolve_config(hound, :overflow, 5)
      ],
      {pool, opts}
    )
  end

  ## Client API

  @doc false
  @spec start_link({module, opts :: Keyword.t()}) :: GenServer.on_start()
  def start_link({daemon, opts}) do
    GenServer.start_link(
      __MODULE__,
      %{
        socket: nil,
        opts: opts,
        daemon: daemon,
        resolver: Module.concat(daemon, "Resolver"),
        udp_wait: resolve_config(opts, :udp_wait, 5_000),
        udp_size: resolve_config(opts, :udp_size, 1_472)
      },
      []
    )
  end

  @spec resolve_config(Keyword.t(), atom, integer | atom) :: integer | no_return
  defp resolve_config(opts, option, default) do
    case opts[option] || default do
      nil -> default
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      value when is_atom(value) -> value
      {:system, value} -> String.to_integer(System.get_env(value) || to_string(default))
    end
  end

  ## Server API

  @impl GenServer
  def init(state = %{resolver: resolver}) do
    {ip, port} = Resolver.host(resolver)
    header = build_header(ip, port)

    state =
      Map.merge(state, %{
        buffer: header,
        size: @header_size,
        header: header,
        timer: nil
      })

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:metric, data}, state = %{socket: nil}) do
    {:noreply, send_or_buffer(data, %{state | socket: open()})}
  end

  def handle_cast({:metric, data}, state) do
    {:noreply, send_or_buffer(data, state)}
  end

  @impl GenServer
  def handle_info({:refresh_header, ip, port}, state) do
    {:noreply, %{state | header: build_header(ip, port)}}
  end

  def handle_info(:force_send, state = %{socket: socket, buffer: buffer, header: header}) do
    send_buffer(socket, buffer)
    {:noreply, %{state | buffer: header, size: @header_size, timer: nil}}
  end

  def handle_info({:inet_reply, _, :ok}, state), do: {:noreply, state}

  def handle_info({:inet_reply, _, {:error, reason}}, state) do
    Logger.error(fn -> ": Reporter Error: #{reason}" end)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{socket: socket}) do
    if socket, do: :gen_udp.close(socket)

    :ok
  end

  @spec open :: :gen_udp.socket()
  defp open do
    {:ok, socket} = :gen_udp.open(0, active: false)

    socket
  end

  @spec send_or_buffer(iodata, map) :: map
  defp send_or_buffer(
         data,
         state = %{
           timer: timer,
           socket: socket,
           buffer: buffer,
           size: size,
           header: header,
           udp_size: udp_size,
           udp_wait: udp_wait
         }
       ) do
    data_size = :erlang.iolist_size(data) + @delimiter_size
    new_size = size + data_size

    cond do
      size == @header_size ->
        %{state | buffer: [buffer, data], size: new_size, timer: start_timer(timer, udp_wait)}

      new_size < udp_size ->
        %{
          state
          | buffer: [buffer, @delimiter, data],
            size: new_size,
            timer: start_timer(timer, udp_wait)
        }

      new_size == udp_size ->
        send_buffer(socket, buffer)
        %{state | buffer: header, size: @header_size, timer: clear_timer(timer)}

      :send_and_create ->
        send_buffer(socket, buffer)
        new_timer = start_timer(clear_timer(timer), udp_wait)

        %{state | buffer: [header, data], size: @header_size + data_size, timer: new_timer}
    end
  end

  @spec clear_timer(any) :: nil
  defp clear_timer(nil), do: nil

  defp clear_timer(timer) do
    Process.cancel_timer(timer)
    nil
  end

  @spec start_timer(any, pos_integer) :: any
  defp start_timer(nil, udp_wait), do: Process.send_after(self(), :force_send, udp_wait)
  defp start_timer(timer, _), do: timer

  @spec send_buffer(:gen_udp.socket(), iodata) :: boolean
  defp send_buffer(socket, buffer), do: Port.command(socket, buffer)

  @spec build_header(tuple, integer) :: iodata
  defp build_header({ip1, ip2, ip3, ip4}, port) do
    [
      1,
      :erlang.band(:erlang.bsr(port, 8), 0xFF),
      :erlang.band(port, 0xFF),
      :erlang.band(ip1, 0xFF),
      :erlang.band(ip2, 0xFF),
      :erlang.band(ip3, 0xFF),
      :erlang.band(ip4, 0xFF)
    ]
  end
end
