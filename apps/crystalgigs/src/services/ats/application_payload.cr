module CrystalGigs
  module Ats
    # A candidate application, normalised for submission to any provider.
    struct ApplicationPayload
      getter full_name : String
      getter email : String
      getter phone : String?
      getter resume_url : String?
      getter cover_letter : String?

      def initialize(
        @full_name : String,
        @email : String,
        @phone : String? = nil,
        @resume_url : String? = nil,
        @cover_letter : String? = nil,
      )
      end

      def self.from(application : JobApplication) : ApplicationPayload
        new(
          full_name: application.candidate_name,
          email: application.candidate_email,
          phone: application.candidate_phone,
          resume_url: application.resume_url,
          cover_letter: application.cover_letter,
        )
      end

      # Providers that want the name split take the first word as the given
      # name and everything after it as the family name. Single-word names
      # repeat, because Greenhouse rejects a blank last_name.
      def first_name : String
        parts = name_parts
        parts.first
      end

      def last_name : String
        parts = name_parts
        parts.size > 1 ? parts[1..].join(" ") : parts.first
      end

      private def name_parts : Array(String)
        parts = full_name.strip.split(/\s+/).reject(&.empty?)
        parts.empty? ? [full_name.strip] : parts
      end
    end
  end
end
