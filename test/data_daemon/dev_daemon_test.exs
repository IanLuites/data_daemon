defmodule DataDaemon.DevDaemonTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  defmodule Example do
    use DataDaemon,
      otp_app: :data_daemon,
      extensions: :datadog,
      error_handler: :debug,
      mode: :log
  end

  setup do
    Example.start_link()
    Process.sleep(1)

    :ok
  end

  test "writes metrics to the console" do
    assert capture_io(fn -> Example.gauge("example", 10) end) =~ " [metric] example:10|g"
  end
end
