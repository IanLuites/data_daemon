defmodule DataDaemon.Decorators do
  @moduledoc ~S"""
  Decorators.
  """

  @doc false
  @spec enable :: term
  def enable do
    quote do
      @doc unquote(@moduledoc)
      defmacro __using__(opts \\ []) do
        tags = Keyword.put(opts[:tags] || [], :module, inspect(__CALLER__.module))

        quote location: :keep do
          @data_daemon unquote(__MODULE__)
          @base_tags unquote(tags)
          Module.register_attribute(__MODULE__, :metric, accumulate: true)
          Module.register_attribute(__MODULE__, :instrumented, accumulate: true)

          import DataDaemon.Decorators,
            only: [timing: 1, timing: 2, count: 1, count: 2, duration: 1, duration: 2]

          @on_definition {DataDaemon.Decorators, :on_definition}
          @before_compile {DataDaemon.Decorators, :before_compile}
        end
      end
    end
  end

  @doc ~S"""
  Measure function time.
  """
  @spec timing(String.t(), Keyword.t()) :: tuple
  def timing(metric, opts \\ []), do: {:timing, metric, opts}

  @doc ~S"""
  Alias for timing.

  See `timing/2`.
  """
  @spec duration(String.t(), Keyword.t()) :: tuple
  def duration(metric, opts \\ []), do: {:timing, metric, opts}

  @doc ~S"""
  Count function executions.
  """
  @spec count(String.t(), Keyword.t()) :: tuple
  def count(metric, opts \\ []), do: {:count, metric, opts}

  @doc false
  @spec on_definition(Macro.Env.t(), atom, atom, term, term, term) :: term
  def on_definition(env, kind, fun, args, guards, body) do
    instruments = Module.get_attribute(env.module, :metric)

    if instruments != [] do
      base_tags =
        env.module
        |> Module.get_attribute(:base_tags)
        |> Keyword.put(:function, "#{fun}/#{Enum.count(args)}")

      # Make sure timings are always last
      instruments =
        instruments
        |> Enum.map(fn {type, metric, opts} ->
          {type, metric, Keyword.update(opts, :tags, base_tags, &Keyword.merge(base_tags, &1))}
        end)
        |> Enum.sort_by(&if(elem(&1, 0) == :timing, do: 1, else: 0))

      body = if Keyword.keyword?(body), do: Keyword.get(body, :do), else: body

      attrs = extract_attributes(env.module, body)
      instrumented = {kind, fun, args, guards, body, attrs, instruments}
      Module.put_attribute(env.module, :instrumented, instrumented)
      Module.delete_attribute(env.module, :metric)
    end

    :ok
  end

  @doc false
  defmacro before_compile(env) do
    decorated = env.module |> Module.get_attribute(:instrumented) |> Enum.reverse()
    Module.delete_attribute(env.module, :instrumented)

    overrides =
      Enum.flat_map(decorated, fn {_, fun, args, _, _, _, _} ->
        args
        |> Enum.count(&(elem(&1, 0) != :\\))
        |> (&(&1..Enum.count(args))).()
        |> Enum.map(&{fun, &1})
      end)

    Enum.reduce(
      decorated,
      quote do
        defoverridable unquote(overrides)
      end,
      fn {kind, fun, args, guards, body, attrs, instruments}, acc ->
        body = [do: Enum.reduce(instruments, body, &instrument/2)]

        attrs =
          Enum.map(attrs, fn {attr, value} ->
            {:@, [], [{attr, [], [Macro.escape(value)]}]}
          end)

        func =
          if guards == [] do
            quote do: Kernel.unquote(kind)(unquote(fun)(unquote_splicing(args)), unquote(body))
          else
            quote do
              Kernel.unquote(kind)(
                unquote(fun)(unquote_splicing(args)) when unquote_splicing(guards),
                unquote(body)
              )
            end
          end

        quote do
          unquote(acc)
          unquote(attrs)
          unquote(func)
        end
      end
    )
  end

  @doc false
  defp instrument({:timing, metric, opts}, acc) do
    quote do
      start_time = :erlang.monotonic_time(:milli_seconds)
      result = unquote(acc)

      @data_daemon.timing(
        unquote(metric),
        :erlang.monotonic_time(:milli_seconds) - start_time,
        unquote(opts)
      )

      result
    end
  end

  defp instrument({:count, metric, opts}, acc) do
    quote do
      @data_daemon.increment(unquote(metric), unquote(opts))
      unquote(acc)
    end
  end

  @doc false
  defp extract_attributes(module, body) do
    body
    |> Macro.postwalk(%{}, fn
      {:@, _, [{attr, _, nil}]} = n, attrs ->
        attrs = Map.put(attrs, attr, Module.get_attribute(module, attr))
        {n, attrs}

      n, acc ->
        {n, acc}
    end)
    |> elem(1)
  end
end
