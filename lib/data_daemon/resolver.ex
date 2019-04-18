defmodule DataDaemon.Resolver do
  @moduledoc false
  use GenServer
  require Logger
  import DataDaemon.Util

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
        {String.to_charlist(uri.host), uri.port}
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

    Logger.debug(fn -> "DataDaemon: DNS lookup \"#{host}\"" end)

    case resolve(host) do
      {ip, ttl} ->
        refresh_callback(refresh, ttl)
        {:ok, %{daemon: daemon, refresh: refresh, host: host, ip: ip, port: port, ttl: ttl}}

      _ ->
        {:error, :could_not_resolve_host}
    end
  end

  @impl GenServer
  def handle_call(:lookup, _, state = %{ip: ip, port: port}) do
    {:reply, {ip, port}, state}
  end

  @impl GenServer
  def handle_info(
        :refresh,
        state = %{
          daemon: daemon,
          host: host,
          ip: ip_old,
          port: port,
          refresh: refresh,
          ttl: ttl_old
        }
      ) do
    Logger.debug(fn -> "DataDaemon: DNS lookup \"#{host}\"" end)

    case resolve(host) do
      {ip, ttl} ->
        if ip == ip_old, do: notify_hounds(daemon, ip, port)

        refresh_callback(refresh, ttl)
        {:noreply, %{state | ip: ip, ttl: ttl}}

      _ ->
        Logger.warn(fn ->
          "DataDaemon: DNS resolve failed, re-using previous result (\"#{host}\")"
        end)

        refresh_callback(refresh, ttl_old)
        {:noreply, state}
    end
  end

  @spec notify_hounds(module, tuple, non_neg_integer) :: :ok
  defp notify_hounds(daemon, ip, port) do
    Enum.each(
      :gen_server.call(daemon, :get_all_workers),
      fn {_, pid, _, _} -> send(pid, {:refresh_header, ip, port}) end
    )
  end

  @spec resolve(charlist) :: {tuple, integer} | nil
  defp resolve(host) do
    case :inet_res.resolve(host, :in, :a) do
      {:ok, {:dns_rec, _, _, records, _, _}} ->
        if result = Enum.find_value(records, &match_resolve/1) do
          result
        else
          Logger.error(fn ->
            "DataDaemon: Missing resolve record: #{inspect(records)} (\"#{host}\")"
          end)

          nil
        end

      invalid ->
        Logger.error(fn -> "DataDaemon: Resolve failed: #{inspect(invalid)} (\"#{host}\")" end)
        nil
    end
  end

  @spec resolve(tuple) :: {tuple, integer} | nil
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
