require "eventmachine"

# A reusable implementation of the Binary Star Pattern, ready to be used in an
# EventMachine reactor.
# @see Binary Star Reactor on http://zguide.zeromq.org/page:all
class CZTop::Patterns::BStar

  # default interval between sending heartbeats, in seconds
  HEARTBEAT = 1 # second

  class NotActive < StandardError; end

  class SplitBrain < StandardError; end

  class DualPassives < StandardError; end

  # The states a BStar peer can be in.
  module States
    PRIMARY = :primary # peer is the designated primary peer

    BACKUP = :backup # peer is the designated backup peer

    # possible initial states
    INITIAL = [ PRIMARY, BACKUP ].freeze

    ACTIVE = :active # peer is currently active
    PASSIVE = :passive # peer is currently passive

    # an array of all possible states
    ALL = [ PRIMARY, BACKUP, ACTIVE, PASSIVE ].freeze
  end

  # The events a BStar peer can process.
  module Events
    PEER_PRIMARY = :peer_primary
    PEER_BACKUP = :peer_backup

    PEER_ACTIVE = :peer_active
    PEER_PASSIVE = :peer_passive

    CLIENT_REQUEST = :client_request

    ALL = [ PEER_ACTIVE, PEER_PASSIVE, CLIENT_REQUEST ].freeze

    # @param peer_state [Symbol] peer's current state
    # @return [Symbol] corresponding event for given peer state
    def self.event_for(peer_state)
      # NOTE: more likely ones come first
      case peer_state
      when States::PASSIVE then PEER_PASSIVE
      when States::ACTIVE then PEER_ACTIVE
      when States::PRIMARY then PEER_PRIMARY
      when States::BACKUP then PEER_BACKUP
      else fail ArgumentError, "invalid peer state: %p" % peer_state
      end
    end
  end

  # Used with {EventMachine.watch}.
  module FrontendReader
    def initialize(bstar)
      @bstar = bstar
    end
    def notify_readable
      @bstar.frontend_ready
    end
  end

  # Used with {EventMachine.watch}.
  module StateReader
    def initialize(bstar)
      @bstar = bstar
    end
    def notify_readable
      @bstar.read_state
    end
  end

  # @return [Symbol] the current state
  # @see States
  attr_reader :state

  # @return [Time] the time the peer's liveness will expire
  attr_reader :peer_expiry

  # @return [CZTop::Socket] the frontend socket (where votes and requests come
  #   from)
  # @note To take effect, this MUST be set before calling {#start}, or not at
  #   all.
  attr_accessor :frontend

  # Initializes the BStar instance. This won't touch EventMachine until
  # {#start} is called.
  #
  # @param state [Symbol] initial state
  # @param local [String] local endpoint for the PUB socket to bind to
  # @param remote [String] remote endpoint for the SUB socket to connect to
  # @param heartbeat [Integer] the interval between sending heartbeats
  # @see States::INITIAL
  # @raise [ArgumentError] if initial state is invalid
  def initialize(state, local, remote, heartbeat: HEARTBEAT)
    unless States::INITIAL.include?(state)
      fail ArgumentError, "invalid initial state: #{state.inspect}"
    end
    @state = state
    @statepub = CZTop::Socket::PUB.new(local)
    @statesub = CZTop::Socket::SUB.new(remote, "") # subscribe to everything
    @heartbeat = heartbeat
    @on_active = @on_passive = @on_vote = @on_request = nil
  end

  # Registers a callback to be executed when this peer becomes active.
  # @note This is not to process requests!
  # @see on_request
  # @return [void]
  def on_active(&blk)
    @on_active = blk
  end

  # Registers a callback to be executed when this peer becomes passive.
  # @return [void]
  def on_passive(&blk)
    @on_passive = blk
  end

  # Failover now. This makes the peer go active. The on_active callback, if
  # any, is called.
  # @return [void]
  def active!
    @state = States::ACTIVE
    @on_active.call if @on_active
  end
  private :active!

  # Go passive. This only happens during initialization of a BStar peer, if at
  # all.
  # @return [void]
  def passive!
    @state = States::PASSIVE
    @on_passive.call if @on_passive
  end
  private :passive!

  # Registers handler for requests (messages) coming on the frontend socket.
  # Only called when this peer is active. Otherwise, the received messages
  # count as votes.
  # @note This SHOULD be called, otherwise messages received on the frontend
  #   socket are just printed out for diagnosis.
  # @see #on_vote
  # @return [void]
  def on_request(&blk)
    @on_request = blk
  end

  # Registers a callback to be executed when the frontend socket receives
  # messages while peer is passive (so the messages count as votes).
  # @see #on_request
  # @return [void]
  def on_vote(&blk)
    @on_vote = blk
  end

  # Called when frontend socket seems ready.
  # @return [void]
  def frontend_ready
    fsm(Events::CLIENT_REQUEST) # could initiate failover
    process_requests
  rescue NotActive
    # not taking over yet
    @on_vote.call if @on_vote
    discard_votes
  end

  # Enters an external vote. Useful if the vote can't come from the frontend
  # itself.
  # @return [void]
  def vote!
    # this could initiate failover if peer unresponsive
    fsm(Events::CLIENT_REQUEST)
  rescue NotActive
    # not taking over yet
  end

  # Register into EventMachine.
  # @return [void]
  def start
    send_states
    watch_statesub
    watch_frontend if @frontend

    # expect first state from peer within 2 heartbeats
    @peer_expiry = Time.now + 2 * @heartbeat
  end

  # Unregister from EventMachine.
  # @return [void]
  def stop
    unwatch_frontend
    stop_sending_states
    unwatch_statesub
  end

  # Read all pending state messages from the other peer.
  # @return [void]
  def read_state
    while @statesub.readable?
      msg = @statesub.receive
      @peer_expiry = Time.now + 2 * @heartbeat
      case msg[0]
      when "BSTAR"
        peer_state = msg[1].to_sym

        # NOTE could only raise DualPassives and SplitBrain
        fsm(Events.event_for(peer_state))
      else
        # FIXME
        warn "weird state message: #{msg.inspect}"
      end
    end
  rescue IO::EAGAINWaitReadable
    # queue has been emptied
  end

  private

  # Start periodically sending current state to other peer.
  # @return [void]
  def send_states
    @state_timer = EventMachine.add_periodic_timer(@heartbeat) do
      @statepub << [ "BSTAR", @state.to_s ] # TODO: use ZMTP properties
    end
  end

  # Cancel periodic timer that sends current state.
  # @return [void]
  def stop_sending_states
    @state_timer.cancel
    @state_timer = nil
  end

  # Watch state SUB socket to start receiving current state from other peer.
  # @return [void]
  def watch_statesub
    @statesub_conn = EventMachine.watch(@statesub.options.fd, StateReader, self)
    @statesub_conn.notify_readable = true
  end

  # Stop watching state SUB.
  # @return [void]
  def unwatch_statesub
    @statesub_conn.detach
    @statesub_conn = nil
  end

  # Watch frontend socket for votes (while passive) and requests (while
  # active).
  # @return [void]
  def watch_frontend
    @frontend_conn = EventMachine.watch(@frontend.options.fd, FrontendReader, self)
    @frontend_conn.notify_readable = true
  end

  # Stop watching the frontend socket.
  # @return [void]
  def unwatch_frontend
    @frontend_conn.detach
    @frontend_conn = nil
  end

  # Reads and discards all messages from the frontend socket.
  # @return [void]
  def discard_votes
    while @frontend.readable?
      @frontend.receive
    end
  end

  # Process all pending client requests from the frontend using custom
  # handler.
  #
  # @return [void]
  def process_requests
    while @frontend.readable?
      # socket is readable
      request = @frontend.receive
      if @on_request
        @on_request.call(request)
      else
        warn "Received request via frontend: #{request.inspect}"
      end
    end
    nil
  end

  # @param event [Symbol] the event to process
  # @see Events
  # @return [void]
  # @raise [NotActive] if client request can't be processed because this
  #   peer either still in {States::PRIMARY}, {States::BACKUP} or is in
  #   {States::PASSIVE} and peer still seems alive
  # @raise [SplitBrain] if this peer is {States::ACTIVE} and the other peer
  #   reported {States::ACTIVE} as well
  # @raise [DualPassives] if this peer is {States::PASSIVE} and the other
  #   peer reported {States::PASSIVE} as well
  # @return [void]
  def fsm(event)
    warn "processing event #{event.inspect} ..."
    case @state
    when States::PRIMARY
      case event
      when Events::PEER_BACKUP
        warn "I: connected to backup (passive), ready active"
        active!
      when Events::PEER_ACTIVE
        warn "I: connected to backup (active), ready passive"
        passive!
      when Events::CLIENT_REQUEST
        # NOTE: Not going active immediately here because backup node could
        # currently be active.

        if peer_expired?
          # Backup peer seems offline, switch to the active state and
          # accept client connections
          warn "I: backup seems dead, going ready active"
          active!
        else
          # If peer is alive, reject connections
          fail NotActive
        end
      end

    when States::BACKUP
      case event
      when Events::PEER_ACTIVE
        warn "I: connected to primary (active), ready passive"
        passive!
      when Events::CLIENT_REQUEST
        # Reject client connections when acting as backup
        fail NotActive
      end

    when States::ACTIVE
      case event
      when Events::PEER_ACTIVE
        # Two actives would mean split-brain
        warn "E: fatal error - dual actives, aborting"
        fail SplitBrain
      end

    when States::PASSIVE
      case event
      when Events::PEER_PRIMARY
        # Peer is restarting - become active, peer will go passive
        warn "I: primary (passive) is restarting, ready active"
        active!

      when Events::PEER_BACKUP
        # Peer is restarting - become active, peer will go passive
        warn "I: backup (passive) is restarting, ready active"
        active!

      when Events::PEER_PASSIVE
        # Two passives would mean cluster would be non-responsive
        warn "E: fatal error - dual passives, aborting"
        fail DualPassives

      when Events::CLIENT_REQUEST
        # Peer becomes active if timeout has passed
        # It's the client request that triggers the failover
        if peer_expired?
          # If peer is dead, switch to the active state
          warn "I: failover successful, ready active"
          active!
        else
          # If peer is alive, reject connections
          fail NotActive
        end
      end
    end
  end

  # @return [Boolean] whether peer looks dead
  def peer_expired?
    Time.now >= @peer_expiry
  end
end
