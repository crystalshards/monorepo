module CrystalGigs
  module Ats
    class Error < Exception
    end

    # No adapter is registered under the requested provider key.
    class UnknownProviderError < Error
    end

    # The request never completed: DNS, TLS, timeout, connection reset.
    class TransportError < Error
    end

    # The request completed but the provider refused it or answered with a
    # status we cannot treat as success.
    class UpstreamError < Error
      getter status : Int32?

      def initialize(message : String, @status : Int32? = nil)
        super(message)
      end
    end

    # The payload arrived but is not the shape the adapter expects.
    class ParseError < Error
    end
  end
end
