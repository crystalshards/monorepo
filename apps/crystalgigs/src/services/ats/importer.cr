require "./client"
require "./errors"
require "./registry"

module CrystalGigs
  module Ats
    # Pulls an employer's ATS board into `Job` rows.
    #
    # Three rules, and they are the whole contract:
    #
    # * Postings are keyed by `(Job#source, Job#external_id)`. A posting seen
    #   again updates its row, it never creates a second one.
    # * A posting that is no longer on the board is delisted: deactivated and
    #   stamped with `delisted_at`, never deleted, so links and applications
    #   already made still resolve.
    # * A delisted posting that reappears is relisted.
    class Importer
      struct Report
        getter provider : String
        getter board_token : String
        getter fetched : Int32
        getter created : Int32
        getter updated : Int32
        getter delisted : Int32
        getter relisted : Int32
        getter error : String?

        def initialize(
          @provider : String,
          @board_token : String,
          @fetched : Int32 = 0,
          @created : Int32 = 0,
          @updated : Int32 = 0,
          @delisted : Int32 = 0,
          @relisted : Int32 = 0,
          @error : String? = nil,
        )
        end

        def ok? : Bool
          error.nil?
        end

        def summary : String
          return "sync failed: #{error}" unless ok?

          "fetched #{fetched}, created #{created}, updated #{updated}, " \
          "relisted #{relisted}, delisted #{delisted}"
        end
      end

      def initialize(@client : Client = Ats.build_client)
      end

      # Sync every active connection. Failures are per connection: one broken
      # board does not stop the others.
      def sync_all : Array(Report)
        AtsConnectionQuery.new.active(true).map { |connection| sync(connection) }
      end

      def sync(connection : AtsConnection) : Report
        adapter = Registry.fetch(connection.provider)
        postings = adapter.fetch_postings(connection.board_token, @client)
        report = apply(connection, adapter, postings)
        record_success(connection, report)
        report
      rescue ex : Ats::Error
        message = ex.message || ex.class.name
        record_failure(connection, message)
        Report.new(
          provider: connection.provider,
          board_token: connection.board_token,
          error: message
        )
      end

      private def apply(connection : AtsConnection, adapter : Adapter, postings : Array(Posting)) : Report
        created = 0
        updated = 0
        relisted = 0
        seen = Set(String).new

        postings.each do |posting|
          seen << posting.external_id
          existing = JobQuery.new.for_import(connection, posting.external_id).first?

          if existing
            relisted += 1 if existing.delisted?
            SaveJob.update!(existing, **attributes(connection, adapter, posting))
            updated += 1
          else
            SaveJob.create!(**attributes(connection, adapter, posting))
            created += 1
          end
        end

        Report.new(
          provider: adapter.key,
          board_token: connection.board_token,
          fetched: postings.size,
          created: created,
          updated: updated,
          delisted: delist_missing(connection, seen),
          relisted: relisted
        )
      end

      # Anything still live for this connection that the board no longer lists.
      private def delist_missing(connection : AtsConnection, seen : Set(String)) : Int32
        delisted_at = Time.utc
        count = 0

        JobQuery.new.ats_connection_id(connection.id).each do |job|
          next if job.delisted?
          external_id = job.external_id
          next if external_id.nil? || seen.includes?(external_id)

          SaveJob.update!(job, active: false, delisted_at: delisted_at)
          count += 1
        end

        count
      end

      private def attributes(connection : AtsConnection, adapter : Adapter, posting : Posting)
        {
          title:             posting.title,
          description:       posting.description,
          company_name:      posting.company_name || connection.company_name,
          company_url:       posting.company_url || connection.company_url,
          location:          posting.location,
          remote:            posting.remote,
          job_type:          posting.job_type,
          salary_min:        posting.salary_min,
          salary_max:        posting.salary_max,
          salary_currency:   posting.salary_currency,
          apply_url:         posting.apply_url,
          apply_email:       posting.apply_email || connection.application_email,
          tags:              posting.tags,
          published_at:      posting.published_at || Time.utc,
          active:            true,
          source:            adapter.key,
          external_id:       posting.external_id,
          ats_connection_id: connection.id,
          delisted_at:       nil,
        }
      end

      private def record_success(connection : AtsConnection, report : Report) : Nil
        SaveAtsConnection.update!(
          connection,
          last_synced_at: Time.utc,
          last_sync_error: nil,
          last_sync_summary: report.summary
        )
      end

      private def record_failure(connection : AtsConnection, message : String) : Nil
        SaveAtsConnection.update!(
          connection,
          last_synced_at: Time.utc,
          last_sync_error: message,
          last_sync_summary: nil
        )
      end
    end
  end
end
