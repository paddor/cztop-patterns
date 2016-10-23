#!/usr/bin/env ruby
require 'optparse'
require_relative "lib/cztop/patterns"
$-v = true
$-d = true

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #$0 [options]"

  opts.on("-p", "--primary", "run as primary server") do |v|
    options[:role] = :primary
  end

  opts.on("-b", "--backup", "run as backup server") do |v|
    options[:role] = :backup
  end
end.parse!

unless options[:role]
  abort "Usage: #$0 { -p | -b }"
end

case options[:role]
when :primary
  puts "I: Primary master, waiting for backup"
  local = "tcp://*:5003"
  remote = "tcp://localhost:5004"
  front = "tcp://*:5001"
when :backup
  puts "I: Backup slave, waiting for primary"
  local = "tcp://*:5004"
  remote = "tcp://localhost:5003"
  front = "tcp://*:5002"
end

bstar = CZTop::Patterns::BStar.new(options[:role], local, remote)
frontend = CZTop::Socket::ROUTER.new(front)
bstar.frontend = frontend

#bstar.on_active do
#  warn "I've gone ACTIVE!"
#end
#
#bstar.on_passive do
#  warn "I've gone PASSIVE!"
#end

bstar.on_request do |req|
#  warn "Got request: #{req.inspect}"
  frontend << req
end

bstar.on_vote do
  warn "Got VOTE!"
end


EventMachine.run do
  bstar.start
end
