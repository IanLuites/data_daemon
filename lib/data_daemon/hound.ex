defmodule DataDaemon.Hound do
  @moduledoc false

  @doc false
  @spec open(
          module :: module,
          host :: binary | charlist | {byte, byte, byte, byte},
          port :: binary | integer
        ) :: {:ok, port} | {:error, atom}
  def open(module, host, port) do
    true = Code.ensure_loaded?(:gen_udp)

    h = if(is_binary(host), do: String.to_charlist(host), else: host)
    p = if(is_binary(port), do: String.to_integer(port), else: port)

    with res = {:ok, _} <- get_socket(module) do
      Code.compiler_options(ignore_module_conflict: true)

      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            @moduledoc false

            @doc false
            @spec send(data :: iolist) :: :ok | {:error, atom}
            def send(metric) do
              Port.command(unquote(module), [unquote(build_header(h, p)), metric])

              receive do
                {:inet_reply, _, res} -> res
              after
                5_000 -> {:error, :timeout}
              end
            end
          end
        end
      )

      Code.compiler_options(ignore_module_conflict: false)

      res
    end
  end

  @spec get_socket(module) :: {:ok, port()} | {:error, atom}
  defp get_socket(module) do
    if s = Process.whereis(module) do
      {:ok, s}
    else
      with res = {:ok, socket} <- :gen_udp.open(0, active: false) do
        Process.register(socket, module)
        res
      end
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
