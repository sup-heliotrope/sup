require 'fileutils'
require 'json'
require 'open3'
require 'optparse'
require 'shellwords'
require 'tmpdir'
require 'yaml'

SIZE = "120x28"  # terminal grid dimensions
IDLE = 0.3       # settling time in seconds for the terminal

class Session
  def initialize command, env
    ht_command = ["ht", "--size", SIZE,
                  "--subscribe", "init,output,snapshot",
                  "--", Shellwords.join(command)]
    @stdin, @stdout, @process = Open3.popen2 env, *ht_command
    @stdin.sync = true
    raise "ht did not send init event" unless read_event["type"] == "init"
  end

  def write command
    @stdin.puts JSON.generate(command)
  end

  def read_event
    line = @stdout.gets or return nil
    JSON.parse line
  end

  def send_keys keys
    write :type => "sendKeys", :keys => keys
  end

  ## Wait until at least IDLE seconds has passed with no more events.
  def settle
    loop do
      return unless IO.select([@stdout], nil, nil, IDLE)
      return unless read_event
    end
  end

  def snapshot
    write :type => "takeSnapshot"
    loop do
      event = read_event
      return event["data"] if event["type"] == "snapshot"
    end
  end

  def expect pattern
    settle
    screen = snapshot
    raise "/#{pattern.source}/ not found" unless screen["text"] =~ pattern
    screen
  end

  def dump_screen
    $stderr.puts "--- screen was ---"
    $stderr.puts snapshot["text"]
    $stderr.puts "------------------"
  rescue
    $stderr.puts "--- no screen  ---"
  end

  def close
    @stdin.close unless @stdin.closed?
    @stdout.read
    @stdout.close
  end
end

options = {}
OptionParser.new do |parser|
  parser.on "--sup-base PATH"
  parser.on "--sup PATH"
  parser.on "--scenes-yaml PATH"
  parser.on "--out PATH"
end.parse! into: options

FileUtils.mkdir_p options[:out]

scenes = YAML.load_file options[:"scenes-yaml"]
scenes.each do |scene|
  name = scene["name"]
  steps = scene["steps"] || []

  ## Make a fresh copy of SUP_BASE for this run of sup.
  base = Dir.mktmpdir "sup-screenshots-#{name}-"
  FileUtils.cp_r Dir.glob(File.join(options[:"sup-base"], "*")), base
  FileUtils.chmod_R "u+w", base

  puts "[#{name}] starting sup"
  session = nil
  begin
    session = Session.new(
      ["ruby", options[:sup], "--no-threads", "--no-initial-poll"],
      {"SUP_BASE" => base, "SUP_LOG_LEVEL" => "debug"})

    screen = session.expect /\[inbox-mode\]/

    steps.each do |step|
      keys = step["keys"]
      puts "[#{name}] send #{keys.inspect}"
      session.send_keys keys

      screen = if step["wait"].nil?
        session.settle
        session.snapshot
      else
        session.expect Regexp.new(step["wait"])
      end
    end

    ansi = screen["seq"]
    ansi = ansi.gsub "\u009b", "\e["  # map CSI emitted by ht to ESC [
    path = File.join options[:out], "#{name}.ansi"
    File.write path, ansi
    puts "[#{name}] wrote #{path}"
  rescue RuntimeError => e
    $stderr.puts "[#{name}] #{e.message}"
    session.dump_screen if session
    raise
  ensure
    session.close if session
  end
end
