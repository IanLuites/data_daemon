defmodule DataDaemon.ResolverTest do
  use ExUnit.Case, async: false
  alias DataDaemon.Resolver
  @minimum 10_000

  describe "resolve/2" do
    test "resolves ip" do
      assert Resolver.resolve('34.25.1.87', @minimum) == {{34, 25, 1, 87}, 86_400_000}
    end

    test "resolve host" do
      assert {_, _} = Resolver.resolve('example.com', @minimum)
    end

    test "nil on unresolvable" do
      assert Resolver.resolve('fake.null', @minimum) == nil
    end
  end
end
