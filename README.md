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
    extensions: [:datadog, :erlang_vm]
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
    {:data_daemon, "~> 0.3"}
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

### Erlang VM

An Erlang VM extension is available logging Erlang VM stats/metrics every minute.

The reporting interval can be configured with the `:rate` (in millisecond) inside the `:erlang_vm` config.

Example: `config :my_app, MyDaemon, erlang_vm: [rate: 1_000]` for updates every second.

The following metrics are tracked:

 * `vm.process.count`, the current process count.
 * `vm.process.limit`, the current process limit.
 * `vm.process.queue`, the current amount of processes queued for running.
 * `vm.port.count`, the current port count.
 * `vm.port.limit`, the current port limit.
 * `vm.atom.count`, the current atom count.
 * `vm.atom.limit`, the current atom limit.
 * `vm.error.queue`, the amount of process messages queued for the error logger.
 * `vm.uptime`, erlang uptime.
 * `vm.refresh`, the amount of time (ms) since last stat check.
 * `vm.reductions`, amount of reductions.
 * `vm.message.queue`, total queued messages over all processes.
 * `vm.modules`, current amount of loaded modules.
 * `vm.memory.total`, total memory use in Kb.
 * `vm.memory.processes`, total process memory chunk use in Kb.
 * `vm.memory.processes_used`, total process memory use in Kb.
 * `vm.memory.system`, total system memory use in Kb.
 * `vm.memory.atom`, total atom memory chunk use in Kb.
 * `vm.memory.atom_used`, total atom memory use in Kb.
 * `vm.memory.binary`, total binary memory use in Kb.
 * `vm.memory.code`, total code memory use in Kb.
 * `vm.memory.ets`, total ets memory use in Kb.
 * `vm.io.in`, total IO input in Kb.
 * `vm.io.out`, total IO output in Kb.
 * `vm.garbage_collection.count`, number of garbage collections.
 * `vm.garbage_collection.words`, number of words garbage.

## Changelog

### 0.3.1 (2020-01-31)

Changes:

* Custom metric type passing. (binary)
* Extended module based config options.

Bug fixes:

* DataDog specs. (Dialyzer)

### 0.3.0 (2020-01-30)

Changes:

* New socket logic for Erlang OTP 22 and up.

Bug fixes:

* Hound spec. (Dialyzer)
* DataDaemon spec. (Dialyzer)

### 0.2.4 (2020-01-29)

Bug fixes:

* Make hound resolve and open a new socket on some errors.

### 0.2.3 (2019-04-30)

Bug fixes:

* Make hound update async to prevent pool-resolver deadlock.

### 0.2.2 (2019-04-29)

New features:

* `vm.refresh` erlang vm metric that tracks time (ms) since last stat check.

Bug fixes:

* Fixes issue where the `vm.uptime` metric wouldn't actually track uptime, but time since last vm check.

### 0.2.1 (2019-04-27)

New features:

* `:minimum_ttl` option to set a minimum TTL to prevent excessive refreshing. (Default: `1_000`)

Optimizations:

* `:erlang_vm` extension runs as additional child to restart during crashes.
* Perform actual resolve in async process to prevent deadlock during excessive DNS refresh.
* DNS resolves in separate process removing use of `:timer` and only sending an update to workers if `IP` changes.

Bug fixes:

* Fixes issue where the `:erlang_vm` would link its process not to the DataDaemon, but the calling process.

### 0.2.0 (2019-04-17)

New features:

* `:erlang_vm` extension. Logs Erlang VM stats/metrics every minute. (Can be configured)

Optimizations:

* Make config more dynamic.
* DNS resolves in separate process removing use of `:timer` and only sending an update to workers if `IP` changes.

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
