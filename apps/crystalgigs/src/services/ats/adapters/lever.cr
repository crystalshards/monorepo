require "json"
require "../adapter"
require "../registry"
require "../html"

module CrystalGigs
  module Ats
    module Adapters
      # Lever job board.
      #
      # Inbound: `GET /v0/postings/<token>?mode=json` is public and
      # unauthenticated. Response shape verified against the live endpoint for
      # a real board (see spec/support/fixtures/ats/lever_postings.json,
      # recorded from that endpoint). The payload is a bare array:
      #
      #   [{"id":"33538a2f-...","text":"AbelsonTaylor Writer",
      #     "hostedUrl":"https://jobs.lever.co/<token>/<id>",
      #     "applyUrl":"https://jobs.lever.co/<token>/<id>/apply",
      #     "categories":{"commitment":"Regular Full Time (Salary)",
      #       "department":"Customer Success","location":"Arlington, TX",
      #       "team":"Professional Services","allLocations":["Arlington, TX"]},
      #     "createdAt":1553186035299,"workplaceType":"hybrid","country":"US",
      #     "descriptionPlain":"...","lists":[{"text":"Qualifications",
      #       "content":"<li>be smart</li>"}],"additionalPlain":"...",
      #     "salaryRange":{"min":10000,"max":125000,"currency":"USD",
      #       "interval":"per-year-salary"}}]
      #
      # `salaryRange` and `commitment` are present on some postings and absent
      # on others in the same board, both cases observed live.
      #
      # Outbound: `POST /v0/postings/<token>/<postingId>?key=<api key>` with a
      # multipart body. Built from Lever's documentation, not exercised
      # against a live board.
      class Lever < Adapter
        BASE_URL = "https://api.lever.co/v0/postings"

        def key : String
          "lever"
        end

        def display_name : String
          "Lever"
        end

        def board_url(board_token : String) : String
          "#{BASE_URL}/#{URI.encode_path_segment(board_token)}?mode=json"
        end

        def supports_application_api? : Bool
          true
        end

        def parse_postings(payload : String) : Array(Posting)
          document = parse_json(payload)
          postings = document.as_a?
          raise ParseError.new("Lever payload is not an array of postings") if postings.nil?

          postings.compact_map { |posting| build_posting(posting) }
        end

        def submit_application(
          board_token : String,
          external_id : String,
          payload : ApplicationPayload,
          client : Client,
        ) : Receipt
          body, content_type = Ats.encode_multipart(application_fields(payload))
          headers = HTTP::Headers{"Content-Type" => content_type}

          # Lever authenticates with a query parameter, so this URL is a
          # credential. It is built here, handed straight to the client, and
          # never put into a message except through `Ats.redact_url`.
          url = String.build do |io|
            io << BASE_URL << '/' << URI.encode_path_segment(board_token)
            io << '/' << URI.encode_path_segment(external_id)
            io << "?key=" << URI.encode_www_form(api_key)
          end

          response = client.post(url, headers, body)

          unless response.success?
            raise UpstreamError.new(
              "Lever rejected the application for posting #{external_id} " \
              "at #{Ats.redact_url(url)}: HTTP #{response.status}",
              response.status
            )
          end

          Receipt.new(response.status, reference_from(response.body))
        end

        private def application_fields(payload : ApplicationPayload) : Hash(String, String)
          fields = {
            "name"  => payload.full_name,
            "email" => payload.email,
          }

          if phone = payload.phone
            fields["phone"] = phone unless phone.blank?
          end

          if cover_letter = payload.cover_letter
            fields["comments"] = cover_letter unless cover_letter.blank?
          end

          # Lever carries links as named url fields rather than a text resume.
          if resume_url = payload.resume_url
            fields["urls[Resume]"] = resume_url unless resume_url.blank?
          end

          fields
        end

        private def reference_from(body : String) : String?
          document = JSON.parse(body)
          document["applicationId"]?.try(&.as_s?) || document["id"]?.try(&.as_s?)
        rescue JSON::ParseException
          nil
        end

        private def build_posting(posting : JSON::Any) : Posting?
          external_id = posting["id"]?.try(&.as_s?)
          title = posting["text"]?.try(&.as_s?)
          apply_url = posting["applyUrl"]?.try(&.as_s?) || posting["hostedUrl"]?.try(&.as_s?)
          return nil if external_id.nil? || title.nil? || apply_url.nil?

          categories = posting["categories"]?
          commitment = category(categories, "commitment")
          location = category(categories, "location")
          workplace = posting["workplaceType"]?.try(&.as_s?)
          salary = posting["salaryRange"]?

          Posting.new(
            external_id: external_id,
            title: title,
            description: description_for(posting),
            apply_url: apply_url,
            company_url: posting["hostedUrl"]?.try(&.as_s?),
            location: location,
            remote: remote?(workplace, location, commitment),
            job_type: JobTypes.normalize(commitment),
            salary_min: salary_bound(salary, "min"),
            salary_max: salary_bound(salary, "max"),
            salary_currency: salary.try(&.["currency"]?).try(&.as_s?) || "USD",
            tags: build_tags(categories, workplace, location, commitment),
            published_at: parse_time(posting["createdAt"]?),
          )
        end

        # Lever splits a description across the intro, a set of titled lists
        # and a trailing section. All three are joined so the stored posting
        # reads the way it does on the employer's own board.
        private def description_for(posting : JSON::Any) : String
          fragments = [] of String?
          fragments << (posting["descriptionPlain"]?.try(&.as_s?) || posting["description"]?.try(&.as_s?))

          if lists = posting["lists"]?.try(&.as_a?)
            lists.each do |list|
              heading = list["text"]?.try(&.as_s?)
              content = list["content"]?.try(&.as_s?)
              next if content.nil?

              fragments << heading unless heading.nil? || heading.blank?
              fragments << content
            end
          end

          fragments << (posting["additionalPlain"]?.try(&.as_s?) || posting["additional"]?.try(&.as_s?))
          Html.join_all(fragments)
        end

        private def category(categories : JSON::Any?, name : String) : String?
          value = categories.try(&.[name]?).try(&.as_s?)
          return nil if value.nil? || value.blank?
          value
        end

        private def salary_bound(salary : JSON::Any?, bound : String) : Int32?
          value = salary.try(&.[bound]?)
          return nil if value.nil?

          number = value.as_i64? || value.as_f?.try(&.round.to_i64)
          return nil if number.nil?
          return nil if number < Int32::MIN || number > Int32::MAX

          number.to_i32
        end

        private def remote?(workplace : String?, location : String?, commitment : String?) : Bool
          return true if workplace.try(&.downcase) == "remote"

          [location, commitment].compact.any?(&.downcase.includes?("remote"))
        end

        private def build_tags(
          categories : JSON::Any?,
          workplace : String?,
          location : String?,
          commitment : String?,
        ) : Array(String)
          tags = [] of String
          tags << category(categories, "department").to_s if category(categories, "department")
          tags << category(categories, "team").to_s if category(categories, "team")
          tags << "remote" if remote?(workplace, location, commitment)
          tags.map(&.downcase.strip).reject(&.empty?).uniq
        end

        private def parse_time(value : JSON::Any?) : Time?
          return nil if value.nil?

          # createdAt is epoch milliseconds.
          if millis = value.as_i64?
            return Time.unix_ms(millis)
          end

          text = value.as_s?
          return nil if text.nil? || text.blank?

          Time.parse_rfc3339(text)
        rescue Time::Format::Error
          nil
        end
      end
    end

    Registry.register(Adapters::Lever.new)
  end
end
