defmodule DataDaemon.Hound do
  @moduledoc false
  use GenServer
  require Logger
  alias DataDaemon.Resolver

  @header_size 7
  @delimiter "\n"
  @delimiter_size 1

  @doc false
  @spec child_spec(atom, opts :: Keyword.t()) :: :supervisor.child_spec()
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
      [{pool, opts}]
    )
  end

  ## Client API

  @doc false
  @spec start_link([{module, opts :: Keyword.t()}]) :: GenServer.on_start()
  def start_link([{daemon, opts}]) do
    GenServer.start_link(
      __MODULE__,
      %{
        socket: nil,
        opts: opts,
        daemon: daemon,
        resolver: Module.concat(daemon, "Resolver"),
        udp_wait: resolve_config(opts, :udp_wait, 5_000),
        udp_size: resolve_config(opts, :udp_size, 1_472) - @header_size
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
    state =
      Map.merge(state, %{
        buffer: [],
        size: 0,
        target: Resolver.host(resolver),
        timer: nil
      })

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:metric, data}, state = %{target: target, socket: nil}) do
    {:noreply, send_or_buffer(data, %{state | socket: open(target)})}
  end

  def handle_cast({:metric, data}, state) do
    {:noreply, send_or_buffer(data, state)}
  end

  @impl GenServer
  def handle_info({:refresh_header, ip, port}, state) do
    {:noreply, %{state | socket: open({ip, port})}}
  end

  def handle_info(:force_send, state = %{socket: socket, buffer: buffer}) do
    send_buffer(socket, buffer)
    {:noreply, %{state | buffer: [], size: 0, timer: nil}}
  end

  def handle_info({:inet_reply, _, :ok}, state), do: {:noreply, state}

  # Network issues, let's resolve and try to _reconnect_
  def handle_info({:inet_reply, _, {:error, :einval}}, state = %{resolver: r, socket: socket}) do
    close(socket)

    target = Resolver.host(r)
    {:noreply, %{state | target: target, socket: open(target)}}
  end

  def handle_info({:inet_reply, _, {:error, reason}}, state) do
    Logger.error(fn -> ": Reporter Error: #{reason}" end)
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{socket: socket}) do
    close(socket)

    :ok
  end

  @spec send_or_buffer(iodata, map) :: map
  defp send_or_buffer(
         data,
         state = %{
           timer: timer,
           socket: socket,
           buffer: buffer,
           size: size,
           udp_size: udp_size,
           udp_wait: udp_wait
         }
       ) do
    data_size = :erlang.iolist_size(data) + @delimiter_size
    new_size = size + data_size

    cond do
      buffer == [] ->
        %{state | buffer: data, size: new_size, timer: start_timer(timer, udp_wait)}

      new_size < udp_size ->
        %{
          state
          | buffer: [buffer, @delimiter, data],
            size: new_size,
            timer: start_timer(timer, udp_wait)
        }

      new_size == udp_size ->
        send_buffer(socket, buffer)
        %{state | buffer: [], size: 0, timer: clear_timer(timer)}

      :send_and_create ->
        send_buffer(socket, buffer)
        new_timer = start_timer(clear_timer(timer), udp_wait)

        %{state | buffer: data, size: data_size, timer: new_timer}
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

  ### Socket Interactions ###

  version = :erlang.system_info(:version)
  version = "#{version}#{String.duplicate(".0", 2 - Enum.count(version, &(&1 == ?.)))}"

  if Version.match?(version, ">= 10.5.0") do
    @spec open(tuple) :: :socket.socket()
    defp open({ip, port}) do
      {:ok, socket} = :socket.open(:inet, :dgram, :udp)
      :ok = :socket.connect(socket, %{family: :inet, addr: ip, port: port})

      socket
    end

    @spec send_buffer(:socket.socket(), iodata) :: boolean
    defp send_buffer(socket, buffer), do: :socket.send(socket, buffer) == :ok

    @spec close(:socket.socket() | nil) :: :ok
    defp close(nil), do: :ok
    defp close(socket), do: :socket.close(socket)
  else
    @spec open(tuple) :: tuple
    defp open({ip, port}) do
      {:ok, socket} = :gen_udp.open(0, active: false)

      {socket, build_header(ip, port)}
    end

    @spec send_buffer(tuple, iodata) :: boolean
    defp send_buffer({socket, header}, buffer), do: Port.command(socket, [header, buffer])

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

    @spec close(tuple | nil) :: :ok
    defp close(nil), do: :ok
    defp close({socket, _}), do: :gen_udp.close(socket)
  end
end
