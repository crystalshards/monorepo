module CrystalGigs
  module Ats
    # A posting from any ATS, normalised to what a `Job` needs.
    #
    # `company_name` is nilable because not every provider ships one. Lever's
    # public postings feed has no company field at all, so the importer falls
    # back to the name on the connection.
    struct Posting
      getter external_id : String
      getter title : String
      getter description : String
      getter company_name : String?
      getter company_url : String?
      getter location : String?
      getter remote : Bool
      getter job_type : String
      getter salary_min : Int32?
      getter salary_max : Int32?
      getter salary_currency : String
      getter apply_url : String
      getter apply_email : String?
      getter tags : Array(String)
      getter published_at : Time?

      def initialize(
        @external_id : String,
        @title : String,
        @description : String,
        @apply_url : String,
        @company_name : String? = nil,
        @company_url : String? = nil,
        @location : String? = nil,
        @remote : Bool = false,
        @job_type : String = JobTypes::FULL_TIME,
        @salary_min : Int32? = nil,
        @salary_max : Int32? = nil,
        @salary_currency : String = "USD",
        @apply_email : String? = nil,
        @tags : Array(String) = [] of String,
        @published_at : Time? = nil,
      )
      end
    end

    # `SaveJob` accepts a fixed set of job types. Provider vocabularies are
    # mapped onto it here so every adapter agrees.
    module JobTypes
      FULL_TIME  = "full-time"
      PART_TIME  = "part-time"
      CONTRACT   = "contract"
      FREELANCE  = "freelance"
      INTERNSHIP = "internship"

      ALL = [FULL_TIME, PART_TIME, CONTRACT, FREELANCE, INTERNSHIP]

      # Best effort mapping of a provider's free-text employment type.
      # Unrecognised values become full-time, which is what a job board
      # defaults to when the employer says nothing.
      def self.normalize(raw : String?) : String
        return FULL_TIME if raw.nil?

        value = raw.downcase
        case
        when value.includes?("intern")    then INTERNSHIP
        when value.includes?("freelance") then FREELANCE
        when value.includes?("part")      then PART_TIME
        when value.includes?("contract") ||
          value.includes?("temporary") ||
          value.includes?("hourly") ||
          value.includes?("consultant") then CONTRACT
        else FULL_TIME
        end
      end
    end
  end
end
