# Data Daemon

[![Hex.pm](https://img.shields.io/hexpm/v/data_daemon.svg "Hex")](https://hex.pm/packages/data_daemon)
[![Build Status](https://travis-ci.org/IanLuites/data_daemon.svg?branch=master)](https://travis-ci.org/IanLuites/data_daemon)
[![Hex.pm](https://img.shields.io/hexpm/l/data_daemon.svg "License")](LICENSE)

An Elixir StatsD client made for DataDog.

## Quick Setup

```elixir
# In your config/config.exs file
config :my_app, Sample.DataDog,
  url: "statsd+udp://localhost:8125"

# In your application code
defmodule Sample.DataDog do
  @moduledoc ~S"My DataDog reporter."
  use DataDaemon, otp_app: :my_app
end

defmodule Sample.App do
  alias Sample.DataDog

  def send_metrics do
    tags = [zone: "us-east-1a"]

    DataDog.gauge("request.queue_depth", 12, tags: tags)

    DataDog.distribution("connections", 123, tags: tags)
    DataDog.histogram("request.file_size", 1034, tags: tags)

    DataDog.timing("request.duration", 34, tags: tags)

    DataDog.increment("request.count_total", tags: tags)
    DataDog.decrement("request.count_total", tags: tags)
    DataDog.count("request.count_total", 2, tags: tags)
  end
end
```

## Installation

The package can be installed
by adding `data_daemon` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:data_daemon, "~> 0.0.1"}
  ]
end
```

The docs can
be found at [https://hexdocs.pm/data_daemon](https://hexdocs.pm/data_daemon).
