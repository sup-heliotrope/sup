#!/usr/bin/ruby
# encoding: utf-8

require 'test/unit'
require 'iconv'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'thread'
require 'eventmachine'
require 'sup'
require 'sup/server'

Thread.abort_on_exception = true

module EM
  def self.spawn_reactor_thread
    fail if EM.reactor_running?
    q = ::Queue.new
    Thread.new { EM.run { q << nil } }
    q.pop
    fail unless EM.reactor_running?
    fail if EM.reactor_thread?
  end

  def self.kill_reactor_thread
    fail unless EM.reactor_running?
    fail if EM.reactor_thread?
    EM.stop
    EM.reactor_thread.join
    fail if EM.reactor_running?
  end
end

class QueueingClient < EM::P::RedwoodClient
  def initialize
    super
    @q = Queue.new
    @readyq = Queue.new
  end

  def receive_message type, tag, params
    @q << [type, params]
  end

  def connection_established
    @readyq << nil
  end

  def wait_until_ready
    @readyq.pop
  end

  def read
    @q.pop
  end

  alias write send_message
end

class TestServer < Test::Unit::TestCase
  def setup
    port = rand(1000) + 30000
    EM.spawn_reactor_thread
    @path = Dir.mktmpdir
    socket_path = File.join(@path, 'socket')
    Redwood::SourceManager.init
    Redwood::SourceManager.load_sources File.join(@path, 'sources.yaml')
    Redwood::Index.init @path
    Redwood::SearchManager.init File.join(@path, 'searches')
    Redwood::Index.load
    @server = EM.start_server socket_path,
              Redwood::Server, Redwood::Index.instance
    @client = EM.connect socket_path, QueueingClient
    @client.wait_until_ready
  end

  def teardown
    FileUtils.rm_r @path if passed?
    puts "not cleaning up #{@path}" unless passed?
    %w(Index SearchManager SourceManager).each do |x|
      Redwood.const_get(x.to_sym).deinstantiate!
    end
    EM.kill_reactor_thread
  end

  def test_invalid_request
    @client.write 'foo', {}
    check @client.read, 'error'
  end

  def check resp, type, args={}
    assert_equal type.to_s, resp[0]
    args.each do |k,v|
      assert_equal v, resp[1][k.to_s]
    end
  end
end
