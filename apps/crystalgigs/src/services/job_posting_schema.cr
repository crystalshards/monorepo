require "json"

# Schema.org `JobPosting` JSON-LD for a single posting, per Google's own
# requirements for the Google Jobs search experience:
# https://developers.google.com/search/docs/appearance/structured-data/job-posting
#
# Everything here is read off the row. There is no "if we don't know, guess a
# plausible value" branch anywhere in this class, because a plausible-looking
# wrong value is worse than an absent one: Google's own misrepresentation
# policy calls out "providing false location data that does not match the
# actual location of the job" as a violation, and an incomplete-but-honest
# JobPosting can still be fixed by filling in the missing column later, while
# a wrong one has to be noticed first.
#
# Only ever construct this for a job that is currently open (`Job#open?`).
# The constructor enforces that rather than leaving it to callers to
# remember, because advertising a draft, expired, or delisted posting as a
# live opening is exactly the class of bug that gets a site removed from the
# feature - see `Jobs::Show`, which is the one place in the app that decides
# whether a job qualifies before ever reaching this class.
class JobPostingSchema
  # USPS state and territory codes. `location` on this board has only ever
  # been a single free-text "City, ST" string - see JobFactory, the seed data
  # in tasks/db/seed/sample_data.cr, and openapi.yml's own "San Francisco, CA"
  # example. There is no separate country column anywhere in this schema, so
  # a country is only ever asserted here when the trailing token is a code
  # from this fixed, external, never-changing list: that is reading a fact
  # the row's own text already encodes, not guessing one. Anything else (a
  # bare city, an unrecognised code, a non-US format, a blank location) gets
  # no jobLocation at all, because Google requires addressCountry on every
  # PostalAddress and there is nothing to honestly build one from.
  US_STATE_CODES = Set{
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    "DC", "PR", "GU", "VI", "AS", "MP",
  }

  # Google's closed employment-type vocabulary. `job_type` is already a
  # closed enum enforced by `SaveJob#validate_job_type`, so this is a total
  # mapping: every value the board accepts appears on the left.
  EMPLOYMENT_TYPES = {
    "full-time"  => "FULL_TIME",
    "part-time"  => "PART_TIME",
    "contract"   => "CONTRACTOR",
    "freelance"  => "CONTRACTOR",
    "internship" => "INTERN",
  }

  def initialize(@job : Job)
    unless @job.open?
      raise ArgumentError.new(
        "JobPostingSchema requires an open job (id=#{@job.id} is not open); " \
        "advertising a draft, expired, or delisted posting is what this class exists to prevent."
      )
    end
  end

  # Valid, parseable `JobPosting` JSON-LD. Kept separate from the
  # HTML-embedding form below so a spec can `JSON.parse` it directly.
  def to_json : String
    JSON.build do |json|
      json.object do
        json.field "@context", "https://schema.org/"
        json.field "@type", "JobPosting"
        json.field "title", @job.title
        json.field "description", @job.description_html
        json.field "datePosted", @job.published_at.not_nil!.to_rfc3339

        if valid_through = @job.expires_at
          json.field "validThrough", valid_through.to_rfc3339
        end

        json.field "employmentType", EMPLOYMENT_TYPES[@job.job_type]? || "OTHER"

        json.field "identifier" do
          json.object do
            json.field "@type", "PropertyValue"
            json.field "name", "CrystalGigs"
            json.field "value", @job.id.to_s
          end
        end

        json.field "hiringOrganization" do
          json.object do
            json.field "@type", "Organization"
            json.field "name", @job.company_name
            if site = @job.company_url
              json.field "sameAs", site
            end
          end
        end

        emit_location(json)
        emit_base_salary(json)

        # Truthful, not aspirational: a candidate who clicks through to an
        # external `apply_url` is handed off to a site this board knows
        # nothing about, which is exactly the "click apply, complete a form
        # on another site" experience Google's own definition of directApply
        # excludes. An `apply_email` with no external URL is the one path
        # Google's own docs credit as equivalent to a direct apply ("the job
        # posting lists the email address... where they can submit the
        # application").
        json.field "directApply", @job.apply_url.nil?
      end
    end
  end

  # The same JSON, safe to embed inside an HTML `<script>` element.
  #
  # `JSON.build` does not escape `<`, `>`, or `&`, because none of the three
  # mean anything to a JSON parser. But this JSON is not only read by a JSON
  # parser: it sits inside `<script type="application/ld+json">`, and every
  # field in it - title, company name, location - is text someone posting a
  # job chose, on this board's own $99 form or a stranger's ATS feed. A title
  # containing a literal `</script>` would close the element early and hand
  # the rest of the page to whatever HTML followed it, live and unescaped.
  # This is the standard "JSON inside HTML" defence: replace the three
  # characters that could form a tag with JSON's own `\uXXXX` escape, which
  # decodes back to the identical character for any real JSON consumer
  # (Google's parser included) while never being literal HTML to the browser
  # parsing the page around it.
  def to_html_safe_json : String
    to_json
      .gsub("<", "\\u003c")
      .gsub(">", "\\u003e")
      .gsub("&", "\\u0026")
  end

  private def emit_location(json : JSON::Builder)
    if @job.remote
      json.field "jobLocationType", "TELECOMMUTE"
      json.field "applicantLocationRequirements" do
        json.object do
          json.field "@type", "Country"
          json.field "name", "USA"
        end
      end
    elsif region = us_region(@job.location)
      json.field "jobLocation" do
        json.object do
          json.field "@type", "Place"
          json.field "address" do
            json.object do
              json.field "@type", "PostalAddress"
              json.field "addressLocality", region[:locality]
              json.field "addressRegion", region[:code]
              json.field "addressCountry", "US"
            end
          end
        end
      end
    end
  end

  # Splits "City, ST" into its two parts, only when the trailing token is a
  # real USPS code - see the class comment on US_STATE_CODES for why that is
  # the one place a country can honestly be read off this column.
  private def us_region(location : String?) : {locality: String, code: String}?
    return nil if location.nil?

    parts = location.split(",").map(&.strip).reject(&.empty?)
    return nil if parts.size < 2

    code = parts.last.upcase
    return nil unless US_STATE_CODES.includes?(code)

    {locality: parts.first, code: code}
  end

  private def emit_base_salary(json : JSON::Builder)
    min = @job.salary_min
    max = @job.salary_max
    return if min.nil? && max.nil?

    json.field "baseSalary" do
      json.object do
        json.field "@type", "MonetaryAmount"
        json.field "currency", @job.salary_currency
        json.field "value" do
          json.object do
            json.field "@type", "QuantitativeValue"
            json.field "minValue", min if min
            json.field "maxValue", max if max
            json.field "unitText", salary_unit
          end
        end
      end
    end
  end

  # Neither this schema nor the row it comes from records a pay period - the
  # form never asks, and no ATS payload observed so far (see
  # services/ats/adapters/lever.cr) survives past `salary_min`/`salary_max`
  # into the row. `job_type` is the one real, deliberate signal every row
  # does carry, and pay-period-by-engagement-type is an established enough
  # convention in software hiring that it matches every salaried and every
  # freelance example in this app's own seed data: full-time and part-time
  # roles are quoted annually, contract/freelance/internship work hourly.
  # This is a judgment call standing in for a column this schema does not
  # have, not a fact read off any specific posting; see the report on this
  # change for the same caveat.
  private def salary_unit : String
    case @job.job_type
    when "contract", "freelance", "internship" then "HOUR"
    else                                             "YEAR"
    end
  end
end
