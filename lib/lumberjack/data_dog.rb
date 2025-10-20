# frozen_string_literal: true

require "lumberjack_json_device"

# Datadog integration for Lumberjack logging.
#
# This module provides JSON logging functionality specifically designed for Datadog,
# automatically mapping standard log attributes to Datadog's naming conventions
# and providing structured exception and duration logging.
#
# @example Basic usage
#   logger = Lumberjack::Logger.new(:datadog)
#   logger.info("Application started")
#
# @example Advanced configuration
#   logger = Lumberjack::Logger.new(:datadog,
#     max_message_length: 1000,
#     allow_all_attributes: false,
#     attribute_mapping: { request_id: "trace_id" }
#   )
#
# @see Device
# @see Config
module Lumberjack::DataDog
  # Version of the lumberjack_datadog gem
  # @return [String] The current version string
  VERSION = ::File.read(::File.join(__dir__, "..", "..", "VERSION")).strip.freeze

  # Standard mapping of log attributes to Datadog fields.
  #
  # This constant defines the default attribute mapping used to transform
  # Lumberjack log entries into Datadog-compatible format.
  #
  # @return [Hash] Mapping hash with the following transformations:
  #   - :time → "timestamp"
  #   - :severity → "status"
  #   - :progname → ["logger", "name"] (nested attribute)
  #   - :pid → "pid"
  STANDARD_ATTRIBUTE_MAPPING = {
    time: "timestamp",
    severity: "status",
    progname: ["logger", "name"],
    pid: "pid"
  }.freeze

  class << self
    # Returns a mapping of log attributes to JSON fields for Datadog.
    #
    # This method creates the attribute mapping configuration used by the JSON device
    # to transform log entries into Datadog-compatible format.
    #
    # @param pid [Boolean, Symbol] Include process ID in logs. Options:
    #   - true: Include current process ID (default)
    #   - false: Exclude process ID
    #   - :global: Use globally unique process ID
    # @param attribute_mapping [Hash] Custom attribute name mapping. Keys are original
    #   attribute names (symbols), values can be strings, arrays (for nested attributes),
    #   or procs for custom formatting.
    # @param allow_all_attributes [Boolean] Whether to include all log entry attributes
    #   at the root level of JSON output. Default is true.
    # @param max_message_length [Integer, nil] Maximum message length. Messages longer
    #   than this will be truncated. Default is nil (no truncation).
    # @return [Hash] Complete mapping configuration for the JSON device
    def json_mapping(pid: true, attribute_mapping: {}, allow_all_attributes: true, max_message_length: nil)
      mapping = STANDARD_ATTRIBUTE_MAPPING.dup

      if pid == :global
        mapping[:pid] = ->(pid) { {"pid" => Lumberjack::Utils.global_pid(pid)} }
      else
        mapping.delete(:pid) unless pid
      end

      mapping.merge!(attribute_mapping.transform_keys(&:to_sym))

      mapping[:attributes] = "*" if allow_all_attributes

      mapping[:message] = if max_message_length
        truncate_message_transformer(max_message_length)
      else
        true
      end

      mapping.transform_keys!(&:to_s)
    end

    def entry_formatter(backtrace_cleaner: nil)
      Lumberjack::EntryFormatter.build do |formatter|
        formatter.format_class(Exception) do |error|
          Lumberjack::MessageAttributes.new(error.inspect, error: error)
        end

        formatter.format_attributes(Exception, Lumberjack::DataDog::ExceptionAttributeFormatter.new(backtrace_cleaner: backtrace_cleaner))

        formatter.format_attribute_name(:duration) do |seconds|
          (seconds.to_f * 1_000_000_000).round
        end

        formatter.format_attribute_name(:duration_ms) do |millis|
          nanoseconds = (millis.to_f * 1_000_000).round
          Lumberjack::RemapAttribute.new("duration" => nanoseconds)
        end

        formatter.format_attribute_name(:duration_micros) do |micros|
          nanoseconds = (micros.to_f * 1_000).round
          Lumberjack::RemapAttribute.new("duration" => nanoseconds)
        end

        formatter.format_attribute_name(:duration_ns) do |ns|
          Lumberjack::RemapAttribute.new("duration" => ns.to_i)
        end
      end
    end

    # Convenience method for setting up a Datadog logger with a block configuration.
    #
    # This method provides a block-based configuration approach that was more useful
    # in earlier versions of Lumberjack. With Lumberjack 2+, you can achieve the same
    # results more directly using {Lumberjack::Logger.new} with the :datadog device.
    #
    # @param stream [IO, String, Pathname] Output stream or path for log output.
    #   Default is $stdout.
    # @param options [Hash] Additional logger options passed to Lumberjack::Logger.new
    # @yield [Lumberjack::DataDog::Config] Block for configuring the logger behavior
    # @return [Lumberjack::Logger] Configured logger instance
    #
    # @example Block configuration
    #   logger = Lumberjack::DataDog.setup($stdout, level: :info) do |config|
    #     config.max_message_length = 500
    #     config.pretty = true
    #   end
    #
    # @see Config
    # @see Device
    def setup(stream = $stdout, options = {}, &block)
      config = Config.new
      yield(config) if block_given?
      config.validate!

      new_logger(stream, options, config)
    end

    private

    # Creates a transformer lambda that truncates messages to a maximum length.
    #
    # @param max_length [Integer] Maximum message length
    # @return [Proc] Message truncation transformer
    def truncate_message_transformer(max_length)
      lambda do |msg|
        msg = msg.inspect unless msg.is_a?(String)
        msg = "#{msg[0, max_length - 1]}…" if msg.length > max_length
        {"message" => msg}
      end
    end

    # Creates a new logger instance with the provided configuration.
    #
    # @param stream [IO, String, Pathname] Output stream or path
    # @param options [Hash] Logger options to pass to Lumberjack::Logger.new
    # @param config [Lumberjack::DataDog::Config] Configuration object with settings
    # @return [Lumberjack::Logger] Configured logger instance
    def new_logger(stream, options, config)
      mapping = json_mapping(
        pid: config.pid,
        attribute_mapping: config.attribute_mapping,
        allow_all_attributes: config.allow_all_attributes,
        max_message_length: config.max_message_length
      )

      options = options.merge(output: stream, mapping: mapping, pretty: config.pretty)
      logger = Lumberjack::Logger.new(:datadog, **options)

      # Deprecated behavior
      if config.thread_name
        if config.thread_name == :global
          logger.tag!("logger.thread_name" => -> { Lumberjack::Utils.global_thread_id })
        else
          logger.tag!("logger.thread_name" => -> { Lumberjack::Utils.thread_name })
        end
      end

      logger
    end
  end
end

require_relative "data_dog/config"
require_relative "data_dog/device"
require_relative "data_dog/exception_attribute_formatter"