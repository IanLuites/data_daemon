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

  describe "config/5" do
    test "from passed options" do
      assert config([setting: "opts"], :data_daemon, TestExample, :setting, "default") == "opts"
    end

    test "from app config options" do
      assert config([], :data_daemon, TestExample, :setting, "default") == "config"
    end

    test "from default" do
      assert config([], :data_daemon, TestExample, :settings, "default") == "default"
    end

    test "from env var" do
      :meck.new(System, [:passthrough])
      :meck.expect(System, :get_env, fn "SETTING" -> "ENV_VAR" end)
      on_exit(&:meck.unload/0)

      assert config(
               [setting: {:system, "SETTING"}],
               :data_daemon,
               TestExample,
               :setting,
               "default"
             ) == "ENV_VAR"
    end
  end

  describe "to_integer!/1" do
    test "keeps int as int" do
      assert to_integer!(5) == 5
    end

    test "converts string int to int" do
      assert to_integer!("5") == 5
    end

    test "{:system, <var>} into an integer" do
      :meck.new(System, [:passthrough])
      :meck.expect(System, :get_env, fn "INTEGER" -> "5" end)
      on_exit(&:meck.unload/0)
      assert to_integer!({:system, "INTEGER"}) == 5
    end
  end
end
