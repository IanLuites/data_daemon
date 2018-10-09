defmodule DataDaemonTest do
  use ExUnit.Case, async: false

  defmodule Example do
    use DataDaemon,
      otp_app: :data_daemon
  end

  test "child_spec/1" do
    assert DataDaemon.child_spec(Example)
  end

  test "start_link/1" do
    :meck.new(DataDaemon.Hound)
    :meck.expect(DataDaemon.Hound, :child_spec, & &1)

    :meck.new(Supervisor)
    :meck.expect(Supervisor, :start_link, fn _, _ -> :ok end)
    on_exit(&:meck.unload/0)

    assert DataDaemon.start_link(Example)
  end

  test "metric/5" do
    :meck.new(:poolboy)
    :meck.expect(:poolboy, :transaction, fn _, c, _ -> c end)
    on_exit(&:meck.unload/0)

    c = DataDaemon.metric(Example, "example", 5, :counter)

    assert c.(self()) == :ok
  end
end
