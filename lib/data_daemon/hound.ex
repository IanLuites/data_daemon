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
      if url = Application.get_env(otp, daemon, [])[:url] do
        uri = URI.parse(url)
        {uri.host, uri.port}
      else
        {Application.get_env(otp, daemon, [])[:host] || "localhost",
         resolve_config(otp, daemon, :port, 8_125)}
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
        port: port,
        dns_refresh: resolve_config(otp, daemon, :dns_refresh, :ttl)
      },
      []
    )
  end

  @spec resolve_config(atom, module, atom, integer | atom) :: integer | no_return
  defp resolve_config(otp, daemon, option, default) do
    case Application.get_env(otp, daemon, [])[option] || default do
      nil -> default
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      value when is_atom(value) -> value
      {:system, value} -> String.to_integer(System.get_env(value) || to_string(default))
    end
  end

  ## Server API

  @impl GenServer
  def init(state) do
    Process.flag(:trap_exit, true)
    header = generate_header!(state)

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
  def handle_info({:refresh_header, header}, state) do
    {:noreply, %{state | header: header}}
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

  @spec generate_header!(map) :: iodata | no_return
  defp generate_header!(%{host: host, port: port, dns_refresh: refresh}) do
    host = String.to_charlist(host)

    if resolved = resolve(host) do
      {ip, ttl} = resolved
      set_refresh(host, port, ip, refresh, ttl)
      build_header(ip, port)
    else
      raise "DataDog: Hound: Start failed, couldn't resolve host."
    end
  end

  @doc false
  @spec host_check!(pid, charlist, integer, tuple, integer | atom) :: :ok | no_return
  def host_check!(hound, host, port, previous_ip, refresh) do
    {ip, ttl} =
      if r = resolve(host) do
        r
      else
        Logger.warn(fn -> "Hound: DNS resolve failed, re-using previous result" end)
        {previous_ip, refresh}
      end

    set_refresh(host, port, ip, refresh, ttl)

    if ip != previous_ip do
      send(
        hound,
        {:refresh_header, build_header(ip, port)}
      )
    end

    :ok
  end

  @spec set_refresh(charlist, integer, tuple, integer | atom, integer) :: :ok
  defp set_refresh(host, port, ip, refresh, ttl) do
    next_check =
      cond do
        refresh == :infinity -> -1
        is_integer(refresh) -> refresh * 1_000
        is_integer(ttl) -> ttl * 1_000
        :no_refresh -> -1
      end

    if next_check > 0,
      do:
        :timer.apply_after(next_check, __MODULE__, :host_check!, [self(), host, port, ip, refresh])

    :ok
  end

  @spec resolve(charlist) :: {tuple, integer} | nil
  defp resolve(host) do
    case :inet_res.resolve(host, :in, :a) do
      {:ok, {:dns_rec, _, _, records, _, _}} ->
        if result = Enum.find_value(records, &match_resolve/1) do
          result
        else
          Logger.error(fn -> "Hound: Missing resolve record: #{inspect(records)}" end)
          nil
        end

      invalid ->
        Logger.error(fn -> "Hound: Resolve failed: #{inspect(invalid)}" end)
        nil
    end
  end

  @spec resolve(tuple) :: {tuple, integer} | nil
  defp match_resolve({:dns_rr, _, :a, :in, _, ttl, ip, _, _, _}), do: {ip, ttl}
  defp match_resolve(_), do: nil

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
