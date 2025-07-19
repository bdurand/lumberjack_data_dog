# frozen_string_literal: true

require "lumberjack_json_device"

module Lumberjack::DataDog
  STANDARD_ATTRIBUTE_MAPPING = {
    time: "timestamp",
    severity: "status",
    progname: ["logger", "name"],
    pid: "pid"
  }.freeze

  class Config
    attr_accessor :max_message_length
    attr_accessor :backtrace_cleaner
    attr_accessor :thread_name
    attr_accessor :pid
    attr_accessor :allow_all_tags
    attr_reader :tag_mapping
    attr_accessor :pretty

    def initialize
      @max_message_length = nil
      @backtrace_cleaner = nil
      @thread_name = false
      @pid = true
      @allow_all_tags = true
      @tag_mapping = {}
      @pretty = false
    end

    def remap_tags(tag_mapping)
      @tag_mapping = @tag_mapping.merge(tag_mapping)
    end

    def validate!
      if !max_message_length.nil? && (!max_message_length.is_a?(Integer) || max_message_length <= 0)
        raise ArgumentError, "max_message_length must be a positive integer"
      end

      unless backtrace_cleaner.nil? || backtrace_cleaner.respond_to?(:clean)
        raise ArgumentError, "backtrace_cleaner must respond to #clean"
      end
    end
  end

  class << self
    def setup(stream = $stdout, options = {}, &block)
      config = Config.new
      yield(config) if block_given?
      config.validate!

      new_logger(stream, options, config)
    end

    private

    def new_logger(stream, options, config)
      logger = Lumberjack::Logger.new(json_device(stream, config), options)

      # Add the error to the error tag if an exception is logged as the message.
      logger.message_formatter.add(Exception, message_exception_formatter)

      # Split the error tag up into standard attributes if it is an exception.
      logger.tag_formatter.add(Exception, exception_tag_formatter(config))

      if config.thread_name
        if config.thread_name == :global
          logger.tag_globally("logger.thread_name" => -> { Lumberjack::Utils.global_thread_id })
        else
          logger.tag_globally("logger.thread_name" => -> { Lumberjack::Utils.thread_name })
        end
      end

      if config.pid == :global
        logger.tag_globally("pid" => -> { Lumberjack::Utils.global_pid })
      end

      logger
    end

    def json_device(stream, config)
      Lumberjack::JsonDevice.new(stream, mapping: json_mapping(config), pretty: config.pretty)
    end

    def json_mapping(config)
      mapping = config.tag_mapping.transform_keys(&:to_sym)
      mapping = mapping.merge(STANDARD_ATTRIBUTE_MAPPING)

      mapping.delete(:pid) if !config.pid || config.pid == :global

      mapping[:tags] = "*" if config.allow_all_tags

      mapping[:message] = if config.max_message_length
        truncate_message_transformer(config.max_message_length)
      else
        "message"
      end

      mapping[:duration] = duration_nanosecond_transformer(1_000_000_000)
      mapping[:duration_ms] = duration_nanosecond_transformer(1_000_000)
      mapping[:duration_micros] = duration_nanosecond_transformer(1_000)
      mapping[:duration_ns] = duration_nanosecond_transformer(1)

      mapping.transform_keys!(&:to_s)
    end

    def truncate_message_transformer(max_length)
      lambda do |msg|
        msg = msg.inspect unless msg.is_a?(String)
        msg = msg[0, max_length] if msg.is_a?(String) && msg.length > max_length
        {"message" => msg}
      end
    end

    def duration_nanosecond_transformer(multiplier)
      lambda do |duration|
        if duration.is_a?(Numeric)
          {"duration" => (duration * multiplier).round}
        else
          {"duration" => nil}
        end
      end
    end

    def message_exception_formatter
      lambda do |error|
        Lumberjack::Formatter::TaggedMessage.new(error.inspect, error: error)
      end
    end

    def exception_tag_formatter(config)
      lambda do |error|
        error_tags = {"kind" => error.class.name, "message" => error.message}
        trace = error.backtrace
        if trace
          trace = config.backtrace_cleaner.clean(trace) if config.backtrace_cleaner
          error_tags["stack"] = trace
        end
        error_tags
      end
    end
  end
end
