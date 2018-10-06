defmodule DataDaemonTest do
  use ExUnit.Case

  test "child_spec/1" do
    assert DataDaemon.child_spec(Example)
  end
end
