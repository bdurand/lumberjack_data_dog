# frozen_string_literal: true

##
# Datadog integration for exception attribute formatting
# @!parse
#   module Lumberjack::DataDog; end
module Lumberjack::DataDog
  # Formats exception attributes for Datadog logs.
  #
  # This formatter converts Exception objects into structured attributes
  # that follow Datadog's error tracking conventions.
  class ExceptionAttributeFormatter
    # Initialize the exception attribute formatter.
    #
    # @param backtrace_cleaner [Object, nil] Optional backtrace cleaner that responds to #clean
    # @param additional_attributes [Hash] Additional attributes to extract from exception
    def initialize(backtrace_cleaner: nil, additional_attributes: {})
      @backtrace_cleaner = backtrace_cleaner
      @additional_attributes = additional_attributes
    end

    # Format exception attributes for logging.
    #
    # Converts an Exception object into a hash of attributes suitable for Datadog
    # error tracking, including the exception class name, message, and stack trace.
    #
    # @param error [Exception] The exception to format
    # @return [Hash] Formatted exception attributes with the following keys:
    #   - 'kind': Exception class name
    #   - 'message': Exception message
    #   - 'stack': Array of stack trace strings (if backtrace available)
    #   - Additional keys from @additional_attributes if specified
    def call(error)
      error_attributes = {"kind" => error.class.name, "message" => error.message}

      backtrace = error.backtrace
      if backtrace
        backtrace = @backtrace_cleaner.clean(backtrace) if @backtrace_cleaner
        error_attributes["stack"] = backtrace
      end

      @additional_attributes.each do |key, method|
        next unless error.respond_to?(method)

        error_attributes[key.to_s] = error.public_send(method)
      end

      error_attributes
    end
  end
end
