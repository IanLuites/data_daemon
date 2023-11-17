defmodule DataDaemonTest do
  use ExUnit.Case, async: false

  defmodule Example2 do
    use DataDaemon, otp_app: :data_daemon, mode: :send
  end

  test "metric/5" do
    Supervisor.start_link([Example2], strategy: :one_for_one)
    DataDaemon.Hound.open(Example2, ~c"127.0.0.1", 8125)
    assert DataDaemon.metric(Example2, "example", 5, :counter) == :ok
  end

  defmodule Example3 do
    use DataDaemon, otp_app: :data_daemon, mode: :send
  end

  test "errors when not started" do
    assert Example3.count("example", 5) == {:error, :not_started}
  end
end
