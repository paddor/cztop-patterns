require "cztop"

# Some reusable patterns from the Zguide.
# @see http://zguide.zeromq.org/
module CZTop::Patterns
  require_relative "patterns/version"

  require_relative "patterns/bstar"
  require_relative "patterns/lazy_pirate" # bstar client

  # Clustered Hashmap Protocol.
  module CHP
    require_relative "patterns/chp_srv"
    require_relative "patterns/chp_cli"
  end
end
