defmodule DataDaemon.Extensions.VM do
  @moduledoc false
  use GenServer

  @doc false
  @spec init(module, Keyword.t()) :: :ok
  def init(daemon, opts) do
    opts = opts[:erlang_vm] || []
    GenServer.start_link(__MODULE__, daemon: daemon, rate: opts[:rate] || 60_000)

    :ok
  end

  # Not needed
  @doc false
  defmacro __using__(_opts \\ []), do: nil

  @impl GenServer
  def init(opts) do
    state = Map.new(opts)

    report(state.daemon)
    Process.send_after(self(), :report, state.rate)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:report, state = %{daemon: daemon, rate: rate}) do
    report(daemon)

    Process.send_after(self(), :report, rate)
    {:noreply, state}
  end

  @spec report(module) :: :ok | {:error, atom}
  defp report(daemon) do
    daemon.gauge("vm.process.count", :erlang.system_info(:process_count))
    daemon.gauge("vm.process.limit", :erlang.system_info(:process_limit))
    daemon.gauge("vm.process.queue", :erlang.statistics(:run_queue))

    daemon.gauge("vm.port.count", :erlang.system_info(:port_count))
    daemon.gauge("vm.port.limit", :erlang.system_info(:port_limit))

    daemon.gauge("vm.atom.count", :erlang.system_info(:atom_count))
    daemon.gauge("vm.atom.limit", :erlang.system_info(:atom_limit))

    daemon.gauge("vm.error.queue", error_log())

    daemon.gauge("vm.uptime", :wall_clock |> :erlang.statistics() |> elem(1))
    daemon.gauge("vm.reductions", :reductions |> :erlang.statistics() |> elem(1))
    daemon.gauge("vm.message.queue", message_queue(Process.list()))
    daemon.gauge("vm.modules", length(:code.all_loaded()))

    Enum.each(
      :erlang.memory(),
      fn {k, v} -> daemon.gauge("vm.memory.#{k}", v) end
    )

    {{:input, io_in}, {:output, io_out}} = {{:input, 355}, {:output, 3260}}
    daemon.gauge("vm.io.in", io_in)
    daemon.gauge("vm.io.out", io_out)

    {count, words, _} = :erlang.statistics(:garbage_collection)
    daemon.gauge("vm.garbage_collection.count", count)
    daemon.gauge("vm.garbage_collection.words", words)
  end

  @spec message_queue([pid], non_neg_integer) :: non_neg_integer
  defp message_queue(pids, acc \\ 0)
  defp message_queue([], acc), do: acc

  defp message_queue([pid | pids], acc) do
    case :erlang.process_info(pid, :message_queue_len) do
      {:message_queue_len, c} -> message_queue(pids, acc + c)
      _ -> message_queue(pids, acc)
    end
  end

  @spec error_log :: integer
  defp error_log do
    with pid when is_pid(pid) <- :erlang.whereis(:error_logger),
         {_, count} <- :erlang.process_info(pid, :message_queue_len) do
      count
    else
      _ -> -1
    end
  end
end
