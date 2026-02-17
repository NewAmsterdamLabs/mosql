require 'rubygems'
require 'bundler/setup'

require 'simplecov'
SimpleCov.start do
  # _qqq.rb are arbitrary files e.g test files created by anyone that should not be included
  add_filter '/**/*_qqq.rb'
  add_filter '/test/'
  add_filter '/lib/mosql/change_stream_streamer.rb'
  add_filter '/lib/mosql/change_stream_tailer.rb'
end

require 'minitest/autorun'
require 'minitest/spec'
require 'mocha'

$:.unshift(File.expand_path(File.join(File.dirname(__FILE__), '../lib')))

require 'mosql'
require 'mocha/minitest'

module MoSQL
  class Test < ::Minitest::Spec
    include MoSQL::Logging
    def setup
      # Put any stubs here that you want to apply globally
    end
  end
end
