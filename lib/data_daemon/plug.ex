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
      alias Plug.Conn

      @doc false
      @spec init(Keyword.t()) ::
              atom()
              | binary()
              | [atom() | binary() | [any()] | number() | tuple() | map()]
              | number()
              | tuple()
              | %{
                  (atom()
                   | binary()
                   | [any()]
                   | number()
                   | tuple()
                   | map()) => atom() | binary() | [any()] | number() | tuple() | map()
                }
      @impl Plug
      def init(opts) do
        tags =
          opts
          |> Keyword.get(:tags, [])
          |> Enum.map(fn
            conn = {:conn, field} when is_list(field) -> {:conn, field}
            {:conn, field} -> {:conn, [field]}
            env = {:system, _} -> env
            {k, {:conn, field}} when is_list(field) -> {to_string(k), {:conn, field}}
            {k, {:conn, field}} -> {to_string(k), {:conn, [field]}}
            {k, env = {:system, _}} -> {to_string(k), env}
            {k, v} -> {to_string(k), to_string(v)}
            v -> to_string(v)
          end)
          |> Enum.group_by(fn
            {:conn, _} -> :conn_tags
            {_, {:conn, _}} -> :conn_tags
            _ -> :tags
          end)

        %{
          metric: opts[:metric] || raise("Need to set metric name."),
          tags: Map.get(tags, :tags, []),
          conn_tags: Map.get(tags, :conn_tags, []),
          exclude: opts[:exclude] || []
        }
      end

      @doc false
      @spec call(Plug.Conn.t(), map) :: Plug.Conn.t()
      @impl Plug
      def call(conn = %{request_path: path}, %{
            metric: metric,
            tags: tags,
            conn_tags: conn_tags,
            exclude: exclude
          }) do
        if path in exclude do
          conn
        else
          start_time = :erlang.monotonic_time(:milli_seconds)

          Conn.register_before_send(conn, fn conn ->
            time = :erlang.monotonic_time(:milli_seconds) - start_time

            conn_tags =
              Enum.map(conn_tags, fn
                {:conn, conn_tag} -> unquote(__MODULE__).safe_in(conn, conn_tag)
                {k, {:conn, conn_tag}} -> {k, unquote(__MODULE__).safe_in(conn, conn_tag)}
              end)

            spawn(fn ->
              timing(
                metric,
                time,
                tags: tags ++ conn_tags
              )
            end)

            conn
          end)
        end
      end
    end
  end
end
