defmodule DataDaemon.Extensions.DataDogTest do
  use ExUnit.Case, async: false
  alias DataDaemon.TestDaemon

  defmodule Example do
    use DataDaemon, otp_app: :data_daemon, extensions: :datadog, test_mode: true
  end

  setup do
    Example.start_link()

    :ok
  end

  defp reported, do: String.split(TestDaemon.reported(Example), "|")

  describe "event/3" do
    test "report event" do
      assert Example.event("title", "body") == :ok

      event = reported()
      assert Enum.at(event, 0) == "_e{5,4}:title"
      assert Enum.at(event, 1) == "body"
    end

    test "defaults to priority: :normal" do
      assert Example.event("title", "body") == :ok

      assert "p:normal" in reported()
    end

    test "set priority to priority: <:normal | :low>" do
      assert Example.event("title", "body", priority: :low) == :ok

      assert "p:low" in reported()
    end

    test "defaults to alert_type: :info" do
      assert Example.event("title", "body") == :ok

      assert "t:info" in reported()
    end

    test "set alert_type to alert_type: <:error | :warning | :info | :success>" do
      assert Example.event("title", "body", alert_type: :error) == :ok

      assert "t:error" in reported()
    end

    test "encodes new lines in body" do
      assert Example.event("title", "body\nnewline") == :ok

      event = reported()
      assert Enum.at(event, 0) == "_e{5,13}:title"
      assert Enum.at(event, 1) == "body\\nnewline"
    end

    test "sets timestamp with timestamp: <Integer>" do
      assert Example.event("title", "body", timestamp: 1_538_905_853_149) == :ok

      assert "d:2018-10-07T09:50:53Z" in reported()
    end

    test "sets timestamp with timestamp: <DateTime>" do
      time = DateTime.utc_now()
      assert Example.event("title", "body", timestamp: time) == :ok

      assert "d:#{DateTime.to_iso8601(time)}" in reported()
    end

    test "sets timestamp with timestamp: <NaiveDateTime>" do
      time = NaiveDateTime.utc_now()
      assert Example.event("title", "body", timestamp: time) == :ok

      assert "d:#{NaiveDateTime.to_iso8601(time)}Z" in reported()
    end

    test "sets hostname with hostname: <String>" do
      assert Example.event("title", "body", hostname: "bob") == :ok

      assert "h:bob" in reported()
    end

    test "sets hostname with hostname: {:system, <String>}" do
      assert Example.event("title", "body", hostname: {:system, "PWD"}) == :ok

      assert "h:#{System.get_env("PWD")}" in reported()
    end

    test "sets aggregation_key with aggregation_key: <String>" do
      assert Example.event("title", "body", aggregation_key: "key") == :ok

      assert "k:key" in reported()
    end

    test "sets source_type_name with source_type_name: <String>" do
      assert Example.event("title", "body", source_type_name: "stype") == :ok

      assert "s:stype" in reported()
    end
  end
end
