require "./adapter"
require "./errors"

module CrystalGigs
  module Ats
    # The one lookup table from provider key to adapter. Adapters register
    # themselves at the bottom of their own file.
    module Registry
      @@adapters = {} of String => Adapter

      def self.register(adapter : Adapter) : Adapter
        @@adapters[adapter.key] = adapter
        adapter
      end

      def self.unregister(key : String) : Adapter?
        @@adapters.delete(key.strip.downcase)
      end

      def self.[]?(key : String?) : Adapter?
        return nil if key.nil?
        @@adapters[key.strip.downcase]?
      end

      def self.fetch(key : String?) : Adapter
        self[key]? || raise UnknownProviderError.new(
          "Unknown ATS provider '#{key}'. Registered providers: #{keys.join(", ")}."
        )
      end

      def self.registered?(key : String?) : Bool
        !self[key]?.nil?
      end

      def self.keys : Array(String)
        @@adapters.keys.sort
      end

      def self.adapters : Array(Adapter)
        keys.map { |key| @@adapters[key] }
      end
    end
  end
end
