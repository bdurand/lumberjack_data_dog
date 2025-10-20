# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::DataDog do
  let(:stream) { StringIO.new }
  let(:last_entry) { JSON.parse(stream.string.split("\n").last) }

  describe "VERSION" do
    it "has a version number" do
      expect(Lumberjack::DataDog::VERSION).not_to be nil
    end
  end

  describe "json_mapping" do
    it "logs the time as timestamp by default" do
      mapping = Lumberjack::DataDog.json_mapping
      expect(mapping["time"]).to eq("timestamp")
    end

    it "logs the severity as status" do
      mapping = Lumberjack::DataDog.json_mapping
      expect(mapping["severity"]).to eq("status")
    end

    it "logs the message as message" do
      mapping = Lumberjack::DataDog.json_mapping
      expect(mapping["message"]).to be(true)
    end

    it "can truncate long messages" do
      mapping = Lumberjack::DataDog.json_mapping(max_message_length: 10)
      expect(mapping["message"]).to respond_to(:call)
      expect(mapping["message"].call("012345678901234567890")).to eq({"message" => "012345678…"})
    end

    it "logs the progname as logger.name" do
      mapping = Lumberjack::DataDog.json_mapping
      expect(mapping["progname"]).to eq(["logger", "name"])
    end

    it "logs the pid as pid" do
      mapping = Lumberjack::DataDog.json_mapping
      expect(mapping["pid"]).to eq("pid")
    end

    it "can suppress the pid" do
      mapping = Lumberjack::DataDog.json_mapping(pid: false)
      expect(mapping).to_not include("pid")
    end

    it "can log a global pid" do
      mapping = Lumberjack::DataDog.json_mapping(pid: :global)
      expect(mapping["pid"]).to respond_to(:call)
      expect(mapping["pid"].call(123)).to eq({"pid" => Lumberjack::Utils.global_pid(123)})
    end

    it "logs attributes at the root level" do
      mapping = Lumberjack::DataDog.json_mapping
      expect(mapping["attributes"]).to eq("*")
    end

    it "can suppress including all attributes at the root level" do
      mapping = Lumberjack::DataDog.json_mapping(allow_all_attributes: false)
      expect(mapping).to_not include("attributes")
    end

    it "can specify attributes to include" do
      mapping = Lumberjack::DataDog.json_mapping(attribute_mapping: {foo: true})
      expect(mapping["foo"]).to be(true)
      expect(mapping["attributes"]).to eq("*")
    end
  end

  describe "logger json_mapping options" do
    let(:options) { {} }
    let(:logger) { Lumberjack::Logger.new(:datadog, output: stream, **options) }

    it "logs the time as timestamp by default" do
      logger.info("Test message")
      expect(Time.iso8601(last_entry["timestamp"])).to be_a(Time)
    end

    it "logs the severity as status" do
      logger.info("Test message")
      expect(last_entry["status"]).to eq("INFO")
    end

    it "logs the message to message" do
      logger.info("Testing")
      expect(last_entry["message"]).to eq("Testing")
    end

    it "can truncate long messages" do
      options[:max_message_length] = 10
      logger.info("012345678901234567890")
      expect(last_entry["message"]).to eq("012345678…")
    end

    it "logs the progname as logger.name" do
      logger.progname = "TestLogger"
      logger.info("Test message")
      expect(last_entry["logger"]["name"]).to eq("TestLogger")
    end

    it "logs the pid as pid" do
      logger.info("Test message")
      expect(last_entry["pid"]).to eq(Process.pid)
    end

    it "can suppress the pid" do
      options[:pid] = false
      logger.info("Test message")
      expect(last_entry).to_not include("pid")
    end

    it "can log a global pid" do
      options[:pid] = :global
      logger.info("Test message")
      expect(last_entry["pid"]).to eq(Lumberjack::Utils.global_pid)
    end

    it "logs attributes at the root level by default" do
      logger.info("Test message", test: "value")
      expect(last_entry["test"]).to eq("value")
    end

    it "can suppress including all attributes at the root level" do
      options[:allow_all_attributes] = false
      logger.info("Test message", test: "value")
      expect(last_entry["attributes"]).to be_nil
      expect(last_entry["test"]).to be_nil
    end

    it "can specify attributes to include" do
      options[:attribute_mapping] = {foo: :qux}
      logger.info("Test message", test: "value", foo: "bar")
      expect(last_entry["test"]).to eq("value")
      expect(last_entry["qux"]).to eq("bar")
      expect(last_entry).to_not include("foo")
    end
  end

  describe ".entry_formatter" do
    describe "duration" do
      it "transforms duration to nanoseconds" do
        logger = Lumberjack::DataDog.setup(stream)
        logger.info("Test message", duration: 1.1)
        expect(last_entry["duration"]).to eq(1_100_000_000)
      end

      it "transforms duration to milliseconds" do
        logger = Lumberjack::DataDog.setup(stream)
        logger.info("Test message", duration_ms: 1.1)
        expect(last_entry["duration"]).to eq(1_100_000)
      end

      it "transforms duration to microseconds" do
        logger = Lumberjack::DataDog.setup(stream)
        logger.info("Test message", duration_micros: 1.1)
        expect(last_entry["duration"]).to eq(1_100)
      end

      it "transforms duration to nanoseconds" do
        logger = Lumberjack::DataDog.setup(stream)
        logger.info("Test message", duration_ns: 1.1)
        expect(last_entry["duration"]).to eq(1)
      end
    end

    describe "exceptions" do
      it "logs exceptions under the error attribute" do
        logger = Lumberjack::DataDog.setup(stream)
        begin
          raise "Test exception"
        rescue => e
          logger.error("An error occurred", error: e)
        end
        expect(last_entry["error"]["kind"]).to eq("RuntimeError")
        expect(last_entry["error"]["message"]).to eq("Test exception")
        expect(last_entry["error"]["stack"]).to eq(e.backtrace)
      end

      it "formats exceptions in the attributes in to kind, message, and stack subfields" do
        logger = Lumberjack::DataDog.setup(stream)
        begin
          raise "Test exception"
        rescue => e
          logger.error("An error occurred", exception: e)
        end
        expect(last_entry["exception"]["kind"]).to eq("RuntimeError")
        expect(last_entry["exception"]["message"]).to eq("Test exception")
        expect(last_entry["exception"]["stack"]).to eq(e.backtrace)
      end
    end
  end

  describe ".setup" do
    it "passes options through to Lumberjack::Logger" do
      logger = Lumberjack::DataDog.setup(stream, level: :warn)
      expect(logger.level).to eq(Logger::WARN)
    end

    it "can log the pid with a global value" do
      logger = Lumberjack::DataDog.setup(stream) do |config|
        config.pid = :global
      end
      logger.info("Test message")
      expect(last_entry["pid"]).to eq(Lumberjack::Utils.global_pid)
    end

    it "does not log thread name by default" do
      logger = Lumberjack::DataDog.setup(stream)
      logger.info("Test message")
      expect(last_entry).not_to include("logger.thread_name")
    end

    it "can log a thread name" do
      logger = nil
      Lumberjack::Utils.with_deprecation_mode(:silent) do
        logger = Lumberjack::DataDog.setup(stream) do |config|
          config.thread_name = true
        end
      end
      logger.info("Test message")
      expect(last_entry["logger"]["thread_name"]).to eq(Lumberjack::Utils.thread_name)
    end

    it "can log a global thread name" do
      logger = nil
      Lumberjack::Utils.with_deprecation_mode(:silent) do
        logger = Lumberjack::DataDog.setup(stream) do |config|
          config.thread_name = :global
        end
      end
      logger.info("Test message")
      expect(last_entry["logger"]["thread_name"]).to eq(Lumberjack::Utils.global_thread_id)
    end

    it "can remap attributes" do
      logger = Lumberjack::DataDog.setup(stream) do |config|
        config.remap_attributes(test: "foo")
      end
      logger.info("Test message", test: "value")
      expect(last_entry["foo"]).to eq("value")
    end

    it "can remap attributes with a formatter" do
      logger = Lumberjack::DataDog.setup(stream) do |config|
        config.remap_attributes(test: ->(value) { {"test" => "formatted_#{value}"} })
      end
      logger.info("Test message", test: "value")
      expect(last_entry["test"]).to eq("formatted_value")
    end

    it "can truncate long messages" do
      logger = Lumberjack::DataDog.setup(stream) do |config|
        config.max_message_length = 10
      end
      logger.info("012345678901234567890")
      expect(last_entry["message"]).to eq("012345678…")
    end

    it "can log pretty JSON" do
      logger = Lumberjack::DataDog.setup(stream) do |config|
        config.pretty = true
      end
      logger.info("Test message")
      expect(stream.string.split("\n").length).to be > 3
    end
  end

  describe "error formatting" do
    let(:error) do
      err = nil
      begin
        raise "An error occurred"
      rescue => e
        err = e
      end
      err
    end

    let(:logger) { Lumberjack::Logger.new(:datadog, output: stream) }

    it "expands exceptions logged in the message" do
      logger.error(error)
      expect(last_entry["message"]).to eq(error.inspect)
      expect(last_entry["error"]).to eq({
        "kind" => "RuntimeError",
        "message" => "An error occurred",
        "stack" => error.backtrace
      })
    end

    it "expands exceptions logged in attributes" do
      logger.error("An error occurred", error: error)
      expect(last_entry["error"]).to eq({
        "kind" => "RuntimeError",
        "message" => "An error occurred",
        "stack" => error.backtrace
      })
    end

    it "can pass a backtrace cleaner option" do
      cleaner = double(:backtrace_cleaner)
      allow(cleaner).to receive(:clean).with(error.backtrace).and_return(["cleaned backtrace"])
      logger = Lumberjack::Logger.new(:datadog, output: stream, backtrace_cleaner: cleaner)
      logger.error("An error occurred", error: error)
      expect(last_entry.dig("error", "stack")).to eq(["cleaned backtrace"])
    end
  end

  describe "duration formatting" do
    let(:logger) { Lumberjack::Logger.new(:datadog, output: stream) }

    it "converts duration from seconds to nanoseconds" do
      logger.info("Test message", duration: 1.5)
      expect(last_entry["duration"]).to eq(1_500_000_000)
    end

    it "converts duration_ms from milliseconds to nanoseconds" do
      logger.info("Test message", duration_ms: 1500)
      expect(last_entry["duration"]).to eq(1_500_000_000)
    end

    it "converts duration_micros from microseconds to nanoseconds" do
      logger.info("Test message", duration_micros: 1500)
      expect(last_entry["duration"]).to eq(1_500_000)
    end

    it "copies duration_ns from nanoseconds to duration" do
      logger.info("Test message", duration_ns: 1_500_000_000)
      expect(last_entry["duration"]).to eq(1_500_000_000)
    end
  end
end
