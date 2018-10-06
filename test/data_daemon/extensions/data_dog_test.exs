defmodule DataDaemon.Extensions.DataDogTest do
  use ExUnit.Case, async: false

  defmodule Example do
    use DataDaemon, otp_app: :data_daemon, extensions: :datadog
  end

  setup do
    Example.start_link()

    :ok
  end

  defp reported, do: String.split(DataDaemon.reported(Example), "|")

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
      assert Enum.at(event, 0) == "_e{5,14}:title"
      assert Enum.at(event, 1) == "body\\\\nnewline"
    end

    test "sets timestamp with timestamp: <Integer>" do
      assert Example.event("title", "body", timestamp: 5) == :ok

      assert "d:5" in reported()
    end

    test "sets timestamp with timestamp: <DateTime>" do
      time = DateTime.utc_now()
      assert Example.event("title", "body", timestamp: time) == :ok

      assert "d:#{DateTime.to_unix(time)}" in reported()
    end

    test "sets timestamp with timestamp: <NaiveDateTime>" do
      time = NaiveDateTime.utc_now()
      assert Example.event("title", "body", timestamp: time) == :ok

      assert "d:#{NaiveDateTime.diff(time, ~N[1970-01-01 00:00:00], :milliseconds)}" in reported()
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
