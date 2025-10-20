# Lumberjack Datadog

[![Continuous Integration](https://github.com/bdurand/lumberjack_datadog/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_datadog/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_datadog.svg)](https://badge.fury.io/rb/lumberjack_datadog)

This gem provides a logging setup for using the [lumberjack](https://github.com/bdurand/lumberjack) gem with Datadog. It sets up JSON logging and maps values to Datadog's [standard attributes](https://docs.datadoghq.com/logs/processing/attributes_naming_convention/).

## Features

- **Datadog Standard Attribute Mapping**: Automatically maps Lumberjack log fields to Datadog's standard attributes:
  - `time` → `timestamp`
  - `severity` → `status`
  - `progname` → `logger.name`
  - `pid` → `pid`
- **Exception Handling**: Structured exception logging with `kind`, `message`, and `stack` fields
- **Duration Logging**: Automatic conversion of duration values to nanoseconds for Datadog
- **Configurable Message Truncation**: Limit message length to prevent oversized logs
- **Attribute Remapping**: Flexible attribute transformation and remapping

## Usage

### Basic Setup

```ruby
# Create a logger that outputs to STDOUT
logger = Lumberjack::Logger.new(:datadog)

# Create a logger that outputs to a file
logger = Lumberjack::Logger.new(:datadog, output: "/var/log/app.log")
```

### Advanced Configuration

You can pass options to the logger during initialization to further customize how entries are formatted:

```ruby
logger = Lumberjack::Logger.new(:datadog,
  output: "/var/log/app.log",
  max_message_length: 1000,         # Truncate messages longer than 1000 characters
  allow_all_attributes: false,      # Only include explicitly mapped attributes
  attribute_mapping: {              # Custom attribute mapping
    request_id: "trace_id",         # Map request_id to trace_id
    user_id: "usr.id"               # Map user_id to nested usr.id
  }
)
```

#### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_message_length` | Integer or nil | `nil` | Maximum length for log messages. Messages longer than this will be truncated with an ellipsis. |
| `allow_all_attributes` | Boolean | `true` | Whether to include all log entry attributes at the root level of the JSON output. When false, only explicitly mapped attributes are included. |
| `attribute_mapping` | Hash | `{}` | Custom mapping of attribute names. Keys are original names (symbols), values can be strings, arrays (for nested attributes), or procs for custom formatting. |
| `pid` | Boolean or Symbol | `true` | Process ID handling: `true` (include current PID), `false` (exclude PID), or `:global` (globally unique PID with hostname). |
| `backtrace_cleaner` | Object or nil | `nil` | Optional backtrace cleaner that responds to `#clean` method for cleaning exception stack traces. |

> [!TIP]
> You can also pass `pretty: true` in development mode to have more human readable logs if you aren't sending them to Datadog.

#### Configuration Block

Alternatively, you can use the `setup` method with a configuration block for complex setups. Note that this approach is maintained for compatibility, but the direct constructor approach shown above is generally preferred for new code.

```ruby
logger = Lumberjack::DataDog.setup($stdout, level: :info) do |config|
  # Message truncation
  config.max_message_length = 500

  # Process ID options
  config.pid = true           # Include current process ID (default)
  config.pid = false          # Don't include process ID
  config.pid = :global        # Use a globally unique process ID (includes hostname)

  # Attribute handling
  config.allow_all_attributes = true  # Include all log attributes at root level (default)
  config.allow_all_attributes = false # Only include explicitly mapped attributes

  # Custom attribute mapping and formatting
  config.remap_attributes(
    request_id: "trace_id",  # Simple remapping
    user_id: "usr.id"        # Nested attribute mapping
  )

  # Pretty print JSON (useful for development)
  config.pretty = true

  # Custom backtrace cleaner for exceptions
  config.backtrace_cleaner = MyCustomBacktraceCleaner.new
end
```

### Entry Formatter

The Datadog device automatically includes the entry formatter to add helpers for logging exceptions and durations. You don't need to specify it explicitly.

### Exception Logging

Exceptions are automatically structured with Datadog's standard error attributes.

```ruby
begin
  do_something
rescue => e
  # Results in logging `e.inspect` as the log message along with @error.kind, @error.message, and @error.stack
  logger.error(e)

  # You can also log a different message and put the error in the attributes. The standard attributes
  # will still be parsed out of the error object.
  logger.error("Something went wrong", error: e)
end
```

You can pass in a custom backtrace cleaner for exceptions. This can be any object that responds to the `clean` method that takes an array of strings and returns an array of strings. If you are in a Rails environment, you can pass in `Rails.backtrace_cleaner`.

```ruby
logger = Lumberjack::Logger.new(:datadog, backtrace_cleaner: Rails.backtrace_cleaner)
```

### Duration Logging

Duration values are automatically converted to nanoseconds in the Datadog standard `duration` attribute from the `duration` attribute. This keeps the Ruby code clean since Ruby measures time in seconds. There are helpers for logging durations in milliseconds, microseconds, and nanoseconds.

```ruby
duration = Benchmark.realtime do
  do_something
end

# duration is automatically converted to nanoseconds in the logs.
logger.info("Operation completed", duration: duration)

# You can also use specific duration units.
logger.info("DB query", duration_ms: 150.5)      # milliseconds
logger.info("API call", duration_micros: 1500)   # microseconds
logger.info("Function", duration_ns: 1500000)    # nanoseconds
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem "lumberjack_datadog"
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install lumberjack_datadog
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
