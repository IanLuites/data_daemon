defmodule DataDaemon.Plug do
  @moduledoc false

  @doc false
  @spec safe_in(any, [atom | String.t()]) :: any
  def safe_in(data, []), do: data
  def safe_in(data, [field | fields]), do: safe_in(Map.get(data, field), fields)

  @doc false
  @spec enable :: term
  def enable do
    quote location: :keep do
      @behaviour Plug
      import DataDaemon.Plug, only: [safe_in: 2]
      import Plug.Conn, only: [register_before_send: 2]

      @doc false
      @spec init(Keyword.t()) :: map
      @impl Plug
      def init(opts) do
        tags =
          Enum.map(opts[:tags] || [], fn
            conn = {:conn, field} when is_list(field) -> {:conn, field}
            {:conn, field} -> {:conn, [field]}
            env = {:system, _} -> env
            {k, {:conn, field}} when is_list(field) -> {to_string(k), {:conn, field}}
            {k, {:conn, field}} -> {to_string(k), {:conn, [field]}}
            {k, env = {:system, _}} -> {to_string(k), env}
            {k, v} -> {to_string(k), to_string(v)}
            v -> to_string(v)
          end)

        %{
          metric: opts[:metric] || raise("Need to set metric name."),
          tags: tags,
          exclude: opts[:exclude] || []
        }
      end

      @doc false
      @spec call(Plug.Conn.t(), map) :: Plug.Conn.t()
      @impl Plug
      def call(conn = %{request_path: path}, %{metric: metric, tags: tags, exclude: exclude}) do
        if path in exclude do
          conn
        else
          start_time = :erlang.monotonic_time(:milli_seconds)

          register_before_send(conn, fn conn ->
            time = :erlang.monotonic_time(:milli_seconds) - start_time

            tags =
              Enum.map(tags, fn
                {:conn, conn_tag} -> safe_in(conn, conn_tag)
                {:system, env} -> System.get_env(env)
                {k, {:system, env}} -> {k, System.get_env(env)}
                {k, {:conn, conn_tag}} -> {k, safe_in(conn, conn_tag)}
                tag -> tag
              end)

            timing(
              metric,
              time,
              tags: tags
            )

            conn
          end)
        end
      end
    end
  end
end
