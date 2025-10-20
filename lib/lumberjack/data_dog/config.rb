# frozen_string_literal: true

##
# Configuration for Datadog logging
# @!parse
#   class Lumberjack::DataDog::Config; end
module Lumberjack::DataDog
  # Configuration options for Datadog logger setup.
  #
  # This class provides a configuration object for customizing the behavior
  # of Datadog loggers when using the {Lumberjack::DataDog.setup} method.
  #
  # @!attribute [rw] max_message_length
  #   @return [Integer, nil] Maximum length for log messages. Messages longer than this
  #     will be truncated with an ellipsis. Default is nil (no truncation).
  # @!attribute [rw] backtrace_cleaner
  #   @return [Object, nil] Optional backtrace cleaner that responds to #clean method.
  #     Used for cleaning exception stack traces. Default is nil.
  # @!attribute [rw] pid
  #   @return [Boolean, Symbol] Process ID inclusion option. Can be true (include current PID),
  #     false (exclude PID), or :global (use globally unique PID). Default is true.
  # @!attribute [rw] allow_all_attributes
  #   @return [Boolean] Whether to include all log entry attributes at the root level
  #     of the JSON output. Default is true.
  # @!attribute [r] attribute_mapping
  #   @return [Hash] Custom mapping of attribute names. Use {#remap_attributes} to modify.
  # @!attribute [rw] pretty
  #   @return [Boolean] Whether to pretty-print JSON output. Useful for development.
  #     Default is false.
  class Config
    attr_accessor :max_message_length
    attr_accessor :backtrace_cleaner
    attr_accessor :pid
    attr_accessor :allow_all_attributes
    attr_reader :attribute_mapping
    attr_accessor :pretty

    def initialize
      @max_message_length = nil
      @backtrace_cleaner = nil
      @thread_name = false
      @pid = true
      @allow_all_attributes = true
      @attribute_mapping = {}
      @pretty = false
    end

    # Add the thread name to the `logger.thread_name` attribute. This setting is deprecated.
    # Call logger.tag!("logger.thread_name" => -> { Lumberjack::Utils.global_thread_id }) instead.
    #
    # @param value [Boolean, Symbol] Thread name option. Pass :global to use the global thread ID.
    # @return [void]
    # @deprecated
    def thread_name=(value)
      message = "Setting @logger.thread_name through the logger setup is deprecated and will be removed in version 2.1.; call logger.tag!(\"logger.thread_name\" => -> { Lumberjack::Utils.global_thread_id }) instead."
      Lumberjack::Utils.deprecated(:thread_name=, message) do
        @thread_name = value
      end
    end

    # @deprecated
    attr_reader :thread_name

    # Remap log attributes by merging additional attribute mappings.
    #
    # @param attribute_mapping [Hash] Additional attribute mappings to merge.
    #   Keys are the original attribute names (symbols), values are the target
    #   field names (strings, arrays for nested fields, or procs for custom formatting).
    # @return [Hash] The updated attribute mapping hash
    # @example Simple attribute remapping
    #   config.remap_attributes(request_id: "trace_id", user_id: "usr.id")
    def remap_attributes(attribute_mapping)
      @attribute_mapping = @attribute_mapping.merge(attribute_mapping)
    end

    # Validate configuration options to ensure they are properly set.
    #
    # Checks that:
    # - max_message_length is nil or a positive integer
    # - backtrace_cleaner is nil or responds to #clean method
    #
    # @raise [ArgumentError] if max_message_length is not nil or a positive integer
    # @raise [ArgumentError] if backtrace_cleaner doesn't respond to #clean
    # @return [void]
    def validate!
      if !max_message_length.nil? && (!max_message_length.is_a?(Integer) || max_message_length <= 0)
        raise ArgumentError, "max_message_length must be a positive integer"
      end

      unless backtrace_cleaner.nil? || backtrace_cleaner.respond_to?(:clean)
        raise ArgumentError, "backtrace_cleaner must respond to #clean"
      end
    end
  end
end
