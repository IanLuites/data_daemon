defmodule DataDaemonTest do
  use ExUnit.Case, async: false

  defmodule Example2 do
    use DataDaemon, otp_app: :data_daemon, mode: :send
  end

  alias NameSpaceExample, as: Example

  defmodule NameSpaceExample do
    use DataDaemon,
      otp_app: :data_daemon,
      extensions: [:datadog],
      mode: :test,
      namespace: "hello.world"
  end

  test "metric/5" do
    Supervisor.start_link([Example2], strategy: :one_for_one)
    DataDaemon.Hound.open(Example2, '127.0.0.1', 8125)
    assert DataDaemon.metric(Example2, "example", 5, :counter) == :ok
  end

  describe "namspacing" do
    setup do
      NameSpaceExample.start_link()
      %{metric: "a.metric"}
    end

    test "metric contains namespace", %{metric: metric} do
      NameSpaceExample.count(metric, 1)
      assert DataDaemon.TestDaemon.reported(NameSpaceExample) == "hello.world.#{metric}:1|c"
    end

    test "can override namespace", %{metric: metric} do
      namespace = "goodbye.world."
      NameSpaceExample.count(metric, 1, namespace: namespace)
      assert DataDaemon.TestDaemon.reported(NameSpaceExample) == "#{namespace}#{metric}:1|c"
    end

    test "can override namespace to empty", %{metric: metric} do
      NameSpaceExample.count(metric, 1, namespace: "")
      assert DataDaemon.TestDaemon.reported(NameSpaceExample) == "#{metric}:1|c"
    end
  end
end
