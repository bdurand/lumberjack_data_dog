# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::DataDog::ExceptionAttributeFormatter do
  let(:error) do
    err = nil
    begin
      raise "Test error"
    rescue => e
      err = e
    end
    err
  end

  it "extracts attributes from an exception" do
    formatter = Lumberjack::DataDog::ExceptionAttributeFormatter.new
    attributes = formatter.call(error)
    expect(attributes["kind"]).to eq("RuntimeError")
    expect(attributes["message"]).to eq("Test error")
    expect(attributes["stack"]).to be_an(Array)
  end

  it "applies a backtrace cleaner" do
    cleaner = double(:backtrace_cleaner)
    allow(cleaner).to receive(:clean).with(error.backtrace).and_return(["cleaned backtrace"])
    formatter = Lumberjack::DataDog::ExceptionAttributeFormatter.new(backtrace_cleaner: cleaner)
    attributes = formatter.call(error)
    expect(attributes["stack"]).to eq(["cleaned backtrace"])
  end

  it "does not error if there is no backtrace to clean" do
    cleaner = double(:backtrace_cleaner)
    error = RuntimeError.new("No backtrace")
    formatter = Lumberjack::DataDog::ExceptionAttributeFormatter.new(backtrace_cleaner: cleaner)
    attributes = formatter.call(error)
    expect(attributes["stack"]).to be_nil
  end

  it "can extract additional attributes from an exception" do
    def error.err_code
      42
    end

    formatter = Lumberjack::DataDog::ExceptionAttributeFormatter.new(additional_attributes: {code: :err_code})
    attributes = formatter.call(error)
    expect(attributes["code"]).to eq(42)
  end
end
