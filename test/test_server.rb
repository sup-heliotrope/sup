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
  # Run the reactor in a new thread. This is useful for using EventMachine
  # alongside synchronous code. It is recommended to use EM.error_handler to
  # detect when an exception terminates the reactor thread.
  def self.spawn_reactor_thread
    fail "reactor already started" if EM.reactor_running?
    q = ::Queue.new
    Thread.new { EM.run { q << nil } }
    q.pop
  end

  # Stop the reactor and wait for it to finish. This is the counterpart to #spawn_reactor_thread.
  def self.kill_reactor_thread
    fail "reactor is not running" unless EM.reactor_running?
    fail "current thread is running the reactor" if EM.reactor_thread?
    EM.stop
    EM.reactor_thread.join
  end
end

class QueueingClient < EM::P::RedwoodClient
  def initialize
    super
    @q = Queue.new
    @readyq = Queue.new
  end

  def receive_message type, tag, params
    @q << [type, tag, params]
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
    @client.write 'foo', '1'
    check @client.read, 'error', '1'
  end

  def test_query
    @client.write 'query', '1', 'query' => 'type:mail'
    check @client.read, 'done', '1'
  end

  def check resp, type, tag, args={}
    assert_equal type.to_s, resp[0]
    assert_equal tag.to_s, resp[1]
    args.each do |k,v|
      assert_equal v, resp[2][k.to_s]
    end
  end
end
