defmodule DataDaemon.Extensions.VMTest do
  use ExUnit.Case, async: false
  alias DataDaemon.TestDaemon

  defmodule Example do
    use DataDaemon,
      otp_app: :data_daemon,
      extensions: :erlang_vm,
      mode: :test,
      erlang_vm: [rate: 120_000]
  end

  setup do
    Example.start_link()

    :ok
  end

  defp reported,
    do:
      Example |> TestDaemon.all_reported() |> Enum.map(&(&1 |> String.split(":") |> List.first()))

  defp is_reported?(metric, limit \\ 10)

  defp is_reported?(_, limit) when limit < 0, do: false

  defp is_reported?(metric, limit) do
    if metric in reported() do
      true
    else
      :timer.sleep(10)
      is_reported?(metric, limit - 1)
    end
  end

  describe "reports metrics" do
    test "reported" do
      assert is_reported?("vm.process.count")
      assert is_reported?("vm.process.limit")
      assert is_reported?("vm.process.queue")
      assert is_reported?("vm.port.count")
      assert is_reported?("vm.port.limit")
      assert is_reported?("vm.atom.count")
      assert is_reported?("vm.atom.limit")
      assert is_reported?("vm.error.queue")
      assert is_reported?("vm.uptime")
      assert is_reported?("vm.reductions")
      assert is_reported?("vm.message.queue")
      assert is_reported?("vm.modules")
      assert is_reported?("vm.memory.total")
      assert is_reported?("vm.memory.processes")
      assert is_reported?("vm.memory.processes_used")
      assert is_reported?("vm.memory.system")
      assert is_reported?("vm.memory.atom")
      assert is_reported?("vm.memory.atom_used")
      assert is_reported?("vm.memory.binary")
      assert is_reported?("vm.memory.code")
      assert is_reported?("vm.memory.ets")
      assert is_reported?("vm.io.in")
      assert is_reported?("vm.io.out")
      assert is_reported?("vm.garbage_collection.count")
      assert is_reported?("vm.garbage_collection.words")
    end
  end
end
