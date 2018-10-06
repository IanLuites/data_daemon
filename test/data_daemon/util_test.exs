defmodule DataDaemon.UtilTest do
  use ExUnit.Case, async: false
  import DataDaemon.Util

  defp bin_package(key, value, type, opts),
    do: :erlang.iolist_to_binary(package(key, value, type, opts))

  describe "package/4" do
    test "handles empty or nil tags" do
      assert bin_package("key", 1, :counter, tags: nil) == "key:1|c"
      assert bin_package("key", 1, :counter, tags: []) == "key:1|c"
    end

    test "handles pure atom tags" do
      assert bin_package("key", 1, :counter, tags: [:dev]) == "key:1|c|#dev"
    end

    test "handles environment variable tags" do
      assert bin_package("key", 1, :counter, tags: [pwd: {:system, "PWD"}]) ==
               "key:1|c|#pwd:#{System.get_env("PWD")}"
    end
  end
end
