defmodule DataDaemonTest do
  use ExUnit.Case, async: false

  defmodule Example2 do
    use DataDaemon, otp_app: :data_daemon, mode: :send
  end

  test "metric/5" do
    Supervisor.start_link([Example2], strategy: :one_for_one)
    DataDaemon.Hound.open(Example2, '127.0.0.1', 8125)
    assert DataDaemon.metric(Example2, "example", 5, :counter) == :ok
  end
end
