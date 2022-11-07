defmodule DataDaemon.TestDaemonTest do
  use ExUnit.Case, async: false

  alias DataDaemon.TestDaemon

  @test_metric_name "test_metric"

  defmodule TestDaemonTestExample do
    use DataDaemon, otp_app: :data_daemon, extensions: [:datadog], mode: :test
  end

  alias TestDaemonTestExample, as: Example

  setup do
    Example.start_link()

    :ok
  end

  describe "reported/2" do
    test "returns reported metrics by name" do
      Example.count(@test_metric_name, 1)
      assert "test_metric:1" <> _ = TestDaemon.reported(Example, @test_metric_name)
    end

    test "doesn't return metric if none matches name" do
      Example.count(@test_metric_name <> "_fake", 1)
      refute TestDaemon.reported(Example, @test_metric_name)
    end
  end

  describe "all_reported/2" do
    test "returns reported metrics by name" do
      Example.count(@test_metric_name, 1)
      Example.count(@test_metric_name, 2, tags: [a_tag: "a_value"])

      assert ["test_metric:1|c", "test_metric:2|c|#a_tag:a_value"] =
               TestDaemon.all_reported(Example, @test_metric_name)
    end

    test "omits non-matching metrics" do
      Example.count(@test_metric_name, 1)
      Example.count(@test_metric_name <> "_fake", 2)

      assert ["test_metric:1|c"] = TestDaemon.all_reported(Example, @test_metric_name)
    end
  end
end
