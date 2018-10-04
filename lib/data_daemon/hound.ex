defmodule DataDaemon.Hound do
  @moduledoc false
  use GenServer
  require Logger

  @header_size 7
  @delimiter "\n"
  @delimiter_size 1

  @doc false
  @spec child_spec(atom, non_neg_integer, non_neg_integer) :: Supervisor.child_spec()
  def child_spec(pool, size \\ 1, overflow \\ 5) do
    :poolboy.child_spec(
      pool,
      [
        name: {:local, pool},
        worker_module: __MODULE__,
        size: size,
        max_overlow: overflow
      ],
      pool
    )
  end

  ## Client API

  @doc false
  @spec start_link(module) :: GenServer.on_start()
  def start_link(daemon) do
    otp = daemon.otp()

    {host, port} =
      if url = Application.fetch_env!(otp, daemon)[:url] do
        uri = URI.parse(url)
        {uri.host, uri.port}
      else
        {Application.fetch_env!(otp, daemon)[:host], resolve_config(otp, daemon, :port, -1)}
      end

    GenServer.start_link(
      __MODULE__,
      %{
        socket: nil,
        otp: otp,
        daemon: daemon,
        udp_wait: resolve_config(otp, daemon, :udp_wait, 5_000),
        udp_size: resolve_config(otp, daemon, :udp_size, 1_472),
        host: host,
        port: port
      },
      []
    )
  end

  @spec resolve_config(atom, module, atom, integer) :: integer | no_return
  defp resolve_config(otp, daemon, option, default) do
    case Application.fetch_env!(otp, daemon)[option] || default do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      {:system, value} -> String.to_integer(System.get_env(value) || to_string(default))
    end
  end

  ## Server API

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)
    header = build_header("localhost", 8125)

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

  @spec open :: Port.t()
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

  @spec send_buffer(Port.t(), iodata) :: boolean
  defp send_buffer(socket, buffer), do: Port.command(socket, buffer)

  @spec build_header(String.t(), pos_integer) :: iodata
  defp build_header(host, port) do
    with {:ok, {n1, n2, n3, n4}} <- :inet.getaddr(String.to_charlist(host), :inet) do
      [
        1,
        :erlang.band(:erlang.bsr(port, 8), 0xFF),
        :erlang.band(port, 0xFF),
        :erlang.band(n1, 0xFF),
        :erlang.band(n2, 0xFF),
        :erlang.band(n3, 0xFF),
        :erlang.band(n4, 0xFF)
      ]
    end
  end
end
