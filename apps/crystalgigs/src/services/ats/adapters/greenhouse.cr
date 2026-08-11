require "json"
require "base64"
require "../adapter"
require "../registry"
require "../html"

module CrystalGigs
  module Ats
    module Adapters
      # Greenhouse job board.
      #
      # Inbound: `GET /v1/boards/<token>/jobs?content=true` is public and
      # unauthenticated. Response shape verified against the live endpoint for
      # a real board (see spec/support/fixtures/ats/greenhouse_board.json,
      # recorded from that endpoint):
      #
      #   {"jobs":[{"id":6136160004,"internal_job_id":...,"title":"...",
      #     "absolute_url":"...","updated_at":"2026-08-06T13:47:17-04:00",
      #     "first_published":"...","location":{"name":"Hybrid - London"},
      #     "company_name":"Vercel","departments":[{"name":"..."}],
      #     "offices":[{"name":"...","location":"..."}],
      #     "metadata":[{"name":"...","value":"...","value_type":"..."}],
      #     "requisition_id":"1311","content":"&lt;div&gt;..."}]}
      #
      # `content` is HTML that has itself been entity-escaped inside the JSON
      # string, so it is unescaped and flattened to text before storage.
      #
      # Outbound: `POST /v1/boards/<token>/jobs/<id>` with HTTP Basic auth,
      # the Job Board API key as the username and an empty password. Built
      # from Greenhouse's documentation, not exercised against a live board.
      class Greenhouse < Adapter
        BASE_URL = "https://boards-api.greenhouse.io/v1/boards"

        # Metadata field names an employer may use for employment type. The
        # board API has no first-class field for it.
        EMPLOYMENT_TYPE_FIELDS = /employment\s*type|job\s*type|commitment|contract\s*type/i

        def key : String
          "greenhouse"
        end

        def display_name : String
          "Greenhouse"
        end

        def board_url(board_token : String) : String
          "#{BASE_URL}/#{URI.encode_path_segment(board_token)}/jobs?content=true"
        end

        def supports_application_api? : Bool
          true
        end

        def parse_postings(payload : String) : Array(Posting)
          document = parse_json(payload)
          jobs = document["jobs"]?.try(&.as_a?)
          raise ParseError.new("Greenhouse payload has no 'jobs' array") if jobs.nil?

          jobs.compact_map { |job| build_posting(job) }
        end

        def submit_application(
          board_token : String,
          external_id : String,
          payload : ApplicationPayload,
          client : Client,
        ) : Receipt
          headers = HTTP::Headers{
            "Authorization" => "Basic #{Base64.strict_encode("#{api_key}:")}",
            "Content-Type"  => "application/x-www-form-urlencoded",
          }

          url = "#{BASE_URL}/#{URI.encode_path_segment(board_token)}/jobs/#{URI.encode_path_segment(external_id)}"
          response = client.post(url, headers, Ats.encode_form(application_fields(payload)))

          unless response.success?
            raise UpstreamError.new(
              "Greenhouse rejected the application for job #{external_id}: HTTP #{response.status}",
              response.status
            )
          end

          Receipt.new(response.status, reference_from(response.body))
        end

        # The board API takes a resume as an uploaded file or as
        # `resume_text`. We hold a link rather than a file, so the link is
        # carried in `resume_text` where a recruiter will see it.
        private def application_fields(payload : ApplicationPayload) : Hash(String, String)
          fields = {
            "first_name" => payload.first_name,
            "last_name"  => payload.last_name,
            "email"      => payload.email,
          }

          if phone = payload.phone
            fields["phone"] = phone unless phone.blank?
          end

          if cover_letter = payload.cover_letter
            fields["cover_letter_text"] = cover_letter unless cover_letter.blank?
          end

          if resume_url = payload.resume_url
            fields["resume_text"] = "Resume: #{resume_url}" unless resume_url.blank?
          end

          fields
        end

        private def reference_from(body : String) : String?
          document = JSON.parse(body)
          document["id"]?.try { |id| id.as_i64?.try(&.to_s) || id.as_s? }
        rescue JSON::ParseException
          nil
        end

        private def build_posting(job : JSON::Any) : Posting?
          external_id = job["id"]?.try { |id| id.as_i64?.try(&.to_s) || id.as_s? }
          title = job["title"]?.try(&.as_s?)
          apply_url = job["absolute_url"]?.try(&.as_s?)
          return nil if external_id.nil? || title.nil? || apply_url.nil?

          location = job["location"]?.try(&.["name"]?).try(&.as_s?)
          departments = names_in(job["departments"]?)
          offices = names_in(job["offices"]?)

          Posting.new(
            external_id: external_id,
            title: title,
            description: Html.to_text(job["content"]?.try(&.as_s?)),
            apply_url: apply_url,
            company_name: job["company_name"]?.try(&.as_s?),
            location: location,
            remote: remote?(location, offices),
            job_type: JobTypes.normalize(employment_type(job)),
            tags: build_tags(departments, offices, location),
            published_at: parse_time(job["first_published"]?) || parse_time(job["updated_at"]?),
          )
        end

        private def names_in(collection : JSON::Any?) : Array(String)
          return [] of String if collection.nil?
          entries = collection.as_a?
          return [] of String if entries.nil?

          entries.compact_map { |entry| entry["name"]?.try(&.as_s?) }
        end

        private def employment_type(job : JSON::Any) : String?
          entries = job["metadata"]?.try(&.as_a?)
          return nil if entries.nil?

          entries.each do |entry|
            name = entry["name"]?.try(&.as_s?)
            next if name.nil? || !name.matches?(EMPLOYMENT_TYPE_FIELDS)

            value = entry["value"]?
            next if value.nil?

            if text = value.as_s?
              return text unless text.blank?
            elsif values = value.as_a?
              first = values.compact_map(&.as_s?).first?
              return first if first
            end
          end

          nil
        end

        private def remote?(location : String?, offices : Array(String)) : Bool
          haystack = ([location] + offices).compact
          haystack.any?(&.downcase.includes?("remote"))
        end

        private def build_tags(departments : Array(String), offices : Array(String), location : String?) : Array(String)
          tags = departments.map(&.downcase.strip)
          tags << "remote" if remote?(location, offices)
          tags.reject(&.empty?).uniq
        end

        private def parse_time(value : JSON::Any?) : Time?
          text = value.try(&.as_s?)
          return nil if text.nil? || text.blank?

          Time.parse_rfc3339(text)
        rescue Time::Format::Error
          nil
        end
      end
    end

    Registry.register(Adapters::Greenhouse.new)
  end
end
