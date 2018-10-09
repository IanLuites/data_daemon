defmodule DataDaemon.Extensions.DataDogErrorHandlerTest do
  use ExUnit.Case, async: false
  alias DataDaemon.Extensions.DataDog.ErrorHandler
  alias DataDaemon.TestDaemon
  require Logger

  defmodule Example do
    use DataDaemon,
      otp_app: :data_daemon,
      extensions: :datadog,
      error_handler: :debug,
      test_mode: true
  end

  setup do
    Example.start_link()
    Process.sleep(1)

    :ok
  end

  describe "hooks into Elixir Logger" do
    test "catches `info`" do
      Logger.info("Captured")

      TestDaemon.assert_reported(Example, fn event ->
        assert event =~ ~r/^_e\{[0-9]+,[0-9]+\}:Captured\|/
        assert event =~ ~r/\|t:info/
      end)
    end

    test "catches `debug` as info" do
      Logger.debug("Captured")

      TestDaemon.assert_reported(Example, fn event ->
        assert event =~ ~r/^_e\{[0-9]+,[0-9]+\}:Captured\|/
        assert event =~ ~r/\|t:info/
      end)
    end

    test "catches `error`" do
      Logger.error("Captured")

      TestDaemon.assert_reported(Example, fn event ->
        assert event =~ ~r/^_e\{[0-9]+,[0-9]+\}:Captured\|/
        assert event =~ ~r/\|t:error/
      end)
    end

    test "catches `warn`" do
      Logger.warn("Captured")

      TestDaemon.assert_reported(Example, fn event ->
        assert event =~ ~r/^_e\{[0-9]+,[0-9]+\}:Captured\|/
        assert event =~ ~r/\|t:warning/
      end)
    end

    test "handles multiline events" do
      Logger.info("Captured\nI go over multiple\n...lines")

      TestDaemon.assert_reported(Example, fn event ->
        assert event =~ ~r/^_e\{[0-9]+,[0-9]+\}:Captured\|/
        assert event =~ ~r/\|I go over multiple\\n...lines\\n\\n/
        assert event =~ ~r/\|t:info/
      end)
    end
  end

  describe "general handler" do
    test "exits out of unknown requests" do
      catch_exit(ErrorHandler.handle_call(:fake, :state))
    end
  end
end
