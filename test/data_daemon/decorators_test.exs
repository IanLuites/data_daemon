defmodule DataDaemon.DecoratorsTest do
  use ExUnit.Case, async: false
  alias DataDaemon.TestDaemon

  defmodule Example do
    use DataDaemon, otp_app: :data_daemon, extensions: [:datadog], mode: :test
  end

  defmodule Profiled do
    use Example

    @metric timing("profiled.duration", tags: [extra: "bob"])
    def sleep, do: Process.sleep(1)

    @metric count("profiled.count", tags: [extra: "bob"])
    def do_something, do: :ok

    @factor 2
    @metric count("profiled.guarded.count", tags: [extra: "bob"])
    def do_guarded(x) when is_integer(x), do: x * @factor
  end

  setup do
    Example.start_link()

    :ok
  end

  defp reported, do: TestDaemon.reported(Example)

  describe "timing/2" do
    test "report event" do
      assert Profiled.sleep() == :ok

      assert reported() =~ ~r/^profile.duration:[0-9]+|ms|.*$/
    end

    test "tags function" do
      assert Profiled.sleep() == :ok

      assert reported() =~ ~r/|#.*function:sleep\/0/
    end

    test "tags module" do
      assert Profiled.sleep() == :ok

      assert reported() =~ ~r/|#.*module:DataDaemon.DecoratorsTest.Profiled/
    end

    test "adds additional tags" do
      assert Profiled.sleep() == :ok

      assert reported() =~ ~r/|#.*extra:bob/
    end
  end

  describe "count/2" do
    test "report event" do
      assert Profiled.do_something() == :ok

      assert reported() =~ ~r/^profile.count:1|c|.*$/
    end

    test "reports multiple" do
      assert Profiled.do_something() == :ok
      assert Profiled.do_something() == :ok

      assert TestDaemon.all_reported(Example) == [
               "profiled.count:1|c|#function:do_something/0,module:DataDaemon.DecoratorsTest.Profiled,extra:bob",
               "profiled.count:1|c|#function:do_something/0,module:DataDaemon.DecoratorsTest.Profiled,extra:bob"
             ]
    end

    test "tags function" do
      assert Profiled.do_something() == :ok

      assert reported() =~ ~r/|#.*function:do_something\/0/
    end

    test "tags module" do
      assert Profiled.do_something() == :ok

      assert reported() =~ ~r/|#.*module:DataDaemon.DecoratorsTest.Profiled/
    end

    test "adds additional tags" do
      assert Profiled.do_something() == :ok

      assert reported() =~ ~r/|#.*extra:bob/
    end
  end

  test "respects guards and attributes" do
    assert Profiled.do_guarded(5) == 10
  end
end
