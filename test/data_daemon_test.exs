defmodule DataDaemonTest do
  use ExUnit.Case, async: false

  defmodule Example do
    use DataDaemon,
      otp_app: :data_daemon,
      hound: [
        size: 2,
        overflow: "10"
      ]
  end

  test "child_spec/1" do
    assert DataDaemon.child_spec(Example)
  end

  describe "start_link/1" do
    setup do
      :meck.new(Supervisor)
      :meck.expect(Supervisor, :start_link, fn [child], _opts -> child end)
      on_exit(&:meck.unload/0)
    end

    test "starts child spec" do
      assert Example.start_link()
    end

    test "parses configured pool (hound) size" do
      {_, {:poolboy, :start_link, [opts | _]}, _, _, _, _} = Example.start_link()

      assert opts[:size] == 2
    end

    test "parses configured pool (hound) overflow" do
      {_, {:poolboy, :start_link, [opts | _]}, _, _, _, _} = Example.start_link()

      assert opts[:max_overlow] == 10
    end
  end

  test "metric/5" do
    :meck.new(:poolboy)
    :meck.expect(:poolboy, :transaction, fn _, c, _ -> c end)
    on_exit(&:meck.unload/0)

    c = DataDaemon.metric(Example, "example", 5, :counter)

    assert c.(self()) == :ok
  end
end
