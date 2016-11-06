# This class implements the Lazy Pirate of the Reliable-Request-Reply (RRR)
# patterns. It can also be used as a client in a Binary Star setup.
#
# @see http://zguide.zeromq.org/page:all#toc89
class CZTop::Patterns::LazyPirate

  # raised when giving up getting a valid reply
  class NoValidReply < SocketError
  end

  # default maximum number of retries
  RETRIES = 3

  # default timeout in seconds
  TIMEOUT = 1000

  # default settle delay before failing over to next endpoint
  SETTLE_DELAY = 2000

  # @return [CZTop::Socket] the socket currently used to send requests and
  #   receive replies
  attr_reader :socket

  # By giving two endpoints, it's effectively a Binary Star client.
  # @param endpoints [String, Array<String>] one or more endpoints
  # @param retries [Integer, nil] maximum number of retries
  # @param timeout [Integer, nil] timeout in seconds
  # @param settle_delay [Integer, nil] delay in seconds before failing over to
  #   next endpoint
  def initialize(endpoints, retries: nil, timeout: nil, settle_delay: nil)
    @endpoints = Array(endpoints).cycle
    @retries = (retries || RETRIES).to_i
    @timeout = (timeout || TIMEOUT).to_i
    @settle_delay = (settle_delay || SETTLE_DELAY).to_i
    @poller = CZTop::Poller.new
    reinit_sock
    p self
  end

  # Tries sending a message and receiving a valid reply up to the specified
  # amount of retries times. The passed block will get any received replies
  # and its return value determines whether it was a valid reply or not. If it
  # was a valid reply, it's over. Otherwise it'll retrying by sending the
  # message again and waiting for replies (if retries left).
  #
  # @param msg [CZTop::Message, String, ...] the message to send
  # @yieldparam reply [CZTop::Message] any reply received
  # @yieldreturn [Boolean] whether the reply was valid or not
  def send(msg)
    @retries.times do
      @socket << msg
      while true
        if @poller.simple_wait(@timeout)
          reply = @socket.receive
          return if yield(reply) # reply valid or not?
          # ... reply was invalid, let's read next reply right away
        else
          # retry by sending message again over fresh socket (possibly to
          # other endpoint)
          reinit_sock
          break
        end
      end
    end
    raise NoValidReply
  end

  private

  # (Re-) Initializes the socket and connects to the next endpoint (cycling
  # through them).
  def reinit_sock
    if @socket
      @poller.remove_reader(@socket)
      @socket.close
      sleep @settle_delay / 1000.0
    end

    @socket = CZTop::Socket::REQ.new
    @socket.options.linger = 0
    endpoint = @endpoints.next
    puts "trying to connect to endpoint #{endpoint.inspect}"
    @socket.connect(endpoint)
    @poller.add_reader(@socket)
  end
end

if $0 == __FILE__
  puts "ARGV[0] = #{ARGV[0].inspect}"
  puts "ARGV[1] = #{ARGV[1].inspect}"
#  lp = CZTop::Patterns::LazyPirate.new(ARGV[0] || "tcp://127.0.0.1:55555", retries: ARGV[1], timeout: ARGV[2])
  lp = CZTop::Patterns::LazyPirate.new(%w[tcp://127.0.0.1:5801 tcp://127.0.0.1:5802], retries: ARGV[1], timeout: ARGV[2])
    count = 0
    loop do
      request = "#{count}"
      count += 1
      lp.send(request) do |reply|
        p reply
        reply = reply.pop
        if reply == request
          puts("I: server replied OK (#{reply})")
        else
          puts("E: malformed reply from server: #{reply.inspect}")
        end
        true
      end
    end
    puts 'success'
end
