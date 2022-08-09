defmodule DataDaemon.Resolver do
  @moduledoc false
  use GenServer
  require Logger
  alias DataDaemon.Hound
  import DataDaemon.Util
  @day 24 * 60 * 60 * 1_000

  @doc false
  @spec refresh(module) :: :refresh
  def refresh(resolver), do: send(resolver, :refresh)

  @doc false
  @spec host(module) :: {tuple, pos_integer}
  def host(resolver), do: GenServer.call(resolver, :lookup)

  @doc false
  @spec child_spec(atom, opts :: Keyword.t()) :: Supervisor.child_spec()
  def child_spec(daemon, opts \\ []) do
    %{
      id: __MODULE__,
      start:
        {GenServer, :start_link,
         [__MODULE__, {daemon, opts}, [name: Module.concat(daemon, Resolver)]]}
    }
  end

  @impl GenServer
  def init({daemon, opts}) do
    otp = opts[:otp_app]

    {host, port} =
      if url = config(opts, otp, daemon, :url) do
        uri = URI.parse(url)
        {String.to_charlist(uri.host), uri.port || 8_125}
      else
        {String.to_charlist(config(opts, otp, daemon, :host, "localhost")),
         to_integer!(config(opts, otp, daemon, :port, 8_125))}
      end

    refresh =
      if dns_refresh = config(opts, otp, daemon, :dns_refresh) do
        cond do
          dns_refresh in ~w(ttl infinity)a -> dns_refresh
          dns_refresh in ~w(ttl infinity) -> String.to_existing_atom(dns_refresh)
          :millisecond -> to_integer!(dns_refresh)
        end
      else
        :ttl
      end

    minimum_ttl = to_integer!(config(opts, otp, daemon, :minimum_ttl, 1_000))

    Logger.debug(fn -> "[DataDaemon] DNS lookup #{inspect(host)}" end, host: host)

    case resolve(host, minimum_ttl) do
      {ip, ttl} ->
        refresh_callback(refresh, ttl)
        recompile(daemon, ip, port)

        {:ok,
         %{
           daemon: daemon,
           refresh: refresh,
           host: host,
           ip: ip,
           port: port,
           ttl: ttl,
           minimum_ttl: minimum_ttl
         }}

      _ ->
        {:error, :could_not_resolve_host}
    end
  end

  @impl GenServer
  def handle_call(:lookup, _, state = %{ip: ip, port: port}) do
    {:reply, {ip, port}, state}
  end

  @impl GenServer
  def handle_info(:refresh, state = %{host: host, minimum_ttl: minimum_ttl}) do
    async_lookup(host, minimum_ttl)

    {:noreply, state}
  end

  def handle_info({:ip, :failed}, state = %{refresh: refresh, ttl: ttl_old}) do
    refresh_callback(refresh, ttl_old)
    {:noreply, state}
  end

  def handle_info(
        {:ip, ip, ttl},
        state = %{
          daemon: daemon,
          ip: ip_old,
          port: port,
          refresh: refresh
        }
      ) do
    if ip == ip_old, do: recompile(daemon, ip, port)

    refresh_callback(refresh, ttl)
    {:noreply, %{state | ip: ip, ttl: ttl}}
  end

  @spec async_lookup(charlist, non_neg_integer) :: pid
  defp async_lookup(host, minimum_ttl) do
    resolver = self()

    spawn_link(fn ->
      Logger.debug(fn -> "[DataDaemon] DNS lookup #{inspect(host)}" end, host: host)

      case resolve(host, minimum_ttl) do
        {ip, ttl} -> send(resolver, {:ip, ip, ttl})
        _ -> send(resolver, {:ip, :failed})
      end
    end)
  end

  @spec recompile(module, tuple, non_neg_integer) :: :ok
  defp recompile(daemon, ip, port) do
    Hound.open(Module.concat(daemon, Sender), ip, port)

    :ok
  end

  @doc false
  @spec resolve(charlist, non_neg_integer) :: {tuple, integer} | nil
  def resolve(host, minimum_ttl) do
    if ip = maybe_ip(host, minimum_ttl) || find_ip_in_records(host, minimum_ttl) do
      ip
    else
      Logger.error(fn -> "[DataDaemon] Could not resolve: #{inspect(host)}" end, host: host)
      nil
    end
  end

  @spec maybe_ip(host :: charlist(), non_neg_integer) :: {tuple, integer} | false
  defp maybe_ip(host, minimum_ttl) do
    case :inet.parse_address(host) do
      {:ok, ip} -> {ip, max(minimum_ttl, @day)}
      _ -> false
    end
  end

  @spec find_ip_in_records(charlist, non_neg_integer) :: {tuple, integer} | false
  defp find_ip_in_records(host, minimum_ttl) do
    records =
      case :inet_res.resolve(host, :in, :a) do
        {:ok, {:dns_rec, _, _, records, _, _}} -> records
        _ -> []
      end

    case Enum.find_value(records, &match_resolve/1) do
      {ip, ttl} when ttl < minimum_ttl -> {ip, minimum_ttl}
      {ip, ttl} -> {ip, ttl}
      _ -> false
    end
  end

  @spec match_resolve(tuple) :: {tuple, integer} | nil
  defp match_resolve({:dns_rr, _, :a, :in, _, ttl, ip, _, _, _}), do: {ip, ttl * 1_000}
  defp match_resolve(_), do: nil

  @spec refresh_callback(:infinity | :ttl | integer, integer) :: :ok
  defp refresh_callback(:infinity, _), do: :ok

  defp refresh_callback(:ttl, ttl) do
    Process.send_after(self(), :refresh, ttl)
    :ok
  end

  defp refresh_callback(refresh, _) when is_integer(refresh) do
    Process.send_after(self(), :refresh, refresh)
    :ok
  end
end
