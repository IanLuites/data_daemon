# Data Daemon

[![Hex.pm](https://img.shields.io/hexpm/v/data_daemon.svg "Hex")](https://hex.pm/packages/data_daemon)
[![Build Status](https://travis-ci.org/IanLuites/data_daemon.svg?branch=master)](https://travis-ci.org/IanLuites/data_daemon)
[![Coverage Status](https://coveralls.io/repos/github/IanLuites/data_daemon/badge.svg?branch=master)](https://coveralls.io/github/IanLuites/data_daemon?branch=master)
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
  use DataDaemon,
    otp_app: :my_app,
    extensions: [:datadog]
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

## Extensions

### DataDog

A DataDog extension is available offering the following functionality:

 * `distribution/3` metric.
 * `event/3` event sending over UDP.
 * `error_handler` is available as option and
    can be used to send errors as events.

#### Events

Create an event for the DataDog event stream by passing a `title` and `message`
to `event/3`.

The following options are also supported:

| **Option**                     | **Description**                                                                           |
|--------------------------------|-------------------------------------------------------------------------------------------|
| `:timestamp` (optional)        | Add a timestamp to the event. Default is the current timestamp.                           |
| `:hostname` (optional)         | Add a hostname to the event. No default.                                                  |
| `:aggregation_key` (optional)  | Add an aggregation key to group the event with others that have the same key. No default. |
| `:priority` (optional)         | Set to `:normal` or `:low`. Default `:normal`.                                            |
| `:source_type_name` (optional) | Add a source type to the event. No default.                                               |
| `:alert_type` (optional)       | Set to `:error`, `:warning`, `:info` or `:success`. Default `:info`.                      |

#### Example

```elixir
defmodule Sample.DataDog do
  @moduledoc ~S"My DataDog reporter."
  use DataDaemon,
    otp_app: :my_app,
    extensions: [:datadog],
    error_handler: true
end

defmodule Sample.App do
  alias Sample.DataDog

  def send_events do
    tags = [zone: "us-east-1a"]

    DataDog.event("Event Title", "Event body.\nMore details", tags: tags)
  end
end
```

All event options are support, for more details see: []

## Changelog

### 0.1.4 (2019-03-25)

New features:

* Allow config overwrite by passing keyword settings to the child spec or start link.

Optimizations:

* Keep using old IP in case DNS refresh fails.
* Added extra logging around DNS failures.

### 0.1.3 (2018-11-03)

New features:

* The `:hound` setting now allows you to set the pool settings.

Optimizations:

* DNS lookup only updates header on change.

Fixes:

* Functions with default arguments are now properly overwritten.

### 0.1.2 (2018-10-09)

New features:

* Test mode now supported as configuration.
* The `:error_handler` setting now allows you to set a minimum level.
  (Default: `:info`, possible: `:debug`, `:info`, `:warn`, and `:error`)
* Add `:dsn_refresh` config for refreshing the host name.
  (Default: `:ttl`, possible: `:ttl` and `<integer>`. (seconds))

Optimizations:

* DNS lookup only updates header on change.

Fixes:

* Functions with default arguments are now properly overwritten.

### 0.1.0 (2018-10-07)

New features:

* Extension system to allow for different `StatsD` extensions.
* Add new tag and value formats:
  * `iodata` now supported for tags and values.
  * `{:config, app, key}` now supported for tags.
* DataDog Events are now supported with `event/3`.
* DataDog can now be used as error handler by setting `error_handler: true`
  in module.

Optimizations:

* Plug reported optimized for detached user response and
  compile time optimizations.
