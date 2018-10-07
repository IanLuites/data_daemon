defmodule DataDaemon.UtilTest do
  use ExUnit.Case, async: false
  import DataDaemon.Util

  defp bin_package(key, value, type, opts \\ []),
    do: :erlang.iolist_to_binary(package(key, value, type, opts))

  describe "package/4" do
    test "handles empty or nil tags" do
      assert bin_package("key", 1, :counter, tags: nil) == "key:1|c"
      assert bin_package("key", 1, :counter, tags: []) == "key:1|c"
    end

    test "handles pure atom tags" do
      assert bin_package("key", 1, :counter, tags: [:dev]) == "key:1|c|#dev"
    end

    test "handles pure iodata tags" do
      assert bin_package("key", 1, :counter, tags: [data: [?y, ?e, ?s]]) == "key:1|c|#data:yes"
    end

    test "handles pure iodata value" do
      assert bin_package("key", [?y, ?e, ?s], :set) == "key:yes|s"
    end

    test "handles environment variable tags" do
      assert bin_package("key", 1, :counter, tags: [pwd: {:system, "PWD"}]) ==
               "key:1|c|#pwd:#{System.get_env("PWD")}"
    end

    test "handles config variable tags" do
      assert bin_package("key", 1, :counter, tags: [config: {:config, :data_daemon, :test_tag}]) ==
               "key:1|c|#config:tagged"
    end
  end
end
