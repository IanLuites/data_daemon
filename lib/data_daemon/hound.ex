defmodule DataDaemon.Hound do
  @moduledoc false

  @doc false
  @spec open(
          module :: module,
          host :: binary | charlist | {byte, byte, byte, byte},
          port :: binary | integer
        ) :: :ok | {:error, atom}
  def open(module, host, port) do
    true = Code.ensure_loaded?(:gen_udp)

    h = if(is_binary(host), do: String.to_charlist(host), else: host)
    p = if(is_binary(port), do: String.to_integer(port), else: port)
    pool_size = String.to_integer(System.get_env("DATADAEMON_POOL_SIZE", "1"))

    with {:ok, sockets} <- get_sockets(module, pool_size) do
      Code.compiler_options(ignore_module_conflict: true)

      if match?([_], sockets) do
        Code.compile_quoted(
          quote do
            defmodule unquote(module) do
              @moduledoc false

              @doc false
              @spec send(data :: iolist) :: :ok | {:error, atom}
              def send(metric) do
                Port.command(unquote(List.first(sockets)), [unquote(build_header(h, p)), metric])

                receive do
                  {:inet_reply, _, res} -> res
                after
                  5_000 -> {:error, :timeout}
                end
              end
            end
          end
        )
      else
        mods =
          sockets
          |> Enum.with_index()
          |> Enum.reduce(
            quote do
              @spec get_port(integer) :: module
              defp get_port(pool)
            end,
            fn {mod, index}, acc ->
              quote do
                unquote(acc)
                defp get_port(unquote(index)), do: unquote(mod)
              end
            end
          )

        Code.compile_quoted(
          quote do
            defmodule unquote(module) do
              @moduledoc false

              @doc false
              @spec send(data :: iolist) :: :ok | {:error, atom}
              def send(metric) do
                [:positive]
                |> :erlang.unique_integer()
                |> rem(unquote(Enum.count(sockets)))
                |> get_port()
                |> Port.command([unquote(build_header(h, p)), metric])

                receive do
                  {:inet_reply, _, res} -> res
                after
                  5_000 -> {:error, :timeout}
                end
              end

              unquote(mods)
            end
          end
        )
      end

      Code.compiler_options(ignore_module_conflict: false)

      :ok
    end
  end

  @spec get_sockets(module, pos_integer()) :: {:ok, [module]} | {:error, atom}
  defp get_sockets(module, size) do
    close_overflow_sockets(module, size + 1)

    Enum.reduce(1..size, {:ok, []}, fn
      mod, {:ok, mods} ->
        m = Module.concat(module, "S#{mod}")
        with {:ok, _} = get_socket(m), do: {:ok, [m | mods]}

      _, err ->
        err
    end)
  end

  @spec get_socket(module) :: {:ok, port()} | {:error, atom}
  defp get_socket(module) do
    if s = Process.whereis(module) do
      {:ok, s}
    else
      with res = {:ok, socket} <- :gen_udp.open(0, active: false) do
        Process.register(socket, module)
        IO.inspect(socket, label: inspect(module))
        res
      end
    end
  end

  @spec close_overflow_sockets(module, pos_integer) :: :ok
  defp close_overflow_sockets(module, mod) do
    if close_socket(Module.concat(module, "S#{mod}")) do
      close_overflow_sockets(module, mod + 1)
    else
      :ok
    end
  end

  @spec close_socket(module) :: boolean
  defp close_socket(module) do
    if Process.whereis(module) do
      Process.unregister(module)

      true
    else
      false
    end
  end

  ### UDP Building ###

  otp_release = :erlang.system_info(:otp_release)
  @addr_family if(otp_release >= '19', do: [1], else: [])

  defp build_header(host, port) do
    {ip1, ip2, ip3, ip4} =
      if is_tuple(host) do
        host
      else
        {:ok, ip} = :inet.getaddr(host, :inet)
        ip
      end

    anc_data_part =
      if function_exported?(:gen_udp, :send, 5) do
        [0, 0, 0, 0]
      else
        []
      end

    @addr_family ++
      [
        :erlang.band(:erlang.bsr(port, 8), 0xFF),
        :erlang.band(port, 0xFF),
        :erlang.band(ip1, 0xFF),
        :erlang.band(ip2, 0xFF),
        :erlang.band(ip3, 0xFF),
        :erlang.band(ip4, 0xFF)
      ] ++ anc_data_part
  end
end
