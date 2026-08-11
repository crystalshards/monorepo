require "./client"
require "./errors"
require "./registry"
require "./application_payload"

module CrystalGigs
  module Ats
    # Gets a candidate's application into the employer's system, and records
    # honestly what happened.
    #
    # The chain, in order:
    #
    #   1. **ATS API** when the posting came from a connection whose adapter
    #      submits applications and whose credential is configured. Success is
    #      `delivered`. A rejection or transport failure is `failed` and the
    #      chain stops: the employer's ATS is the system of record, and
    #      quietly emailing instead would hide a lost application.
    #   2. **Application email** when there is no API path. The address comes
    #      from the connection or the posting. A send is `delivered`.
    #   3. **Apply URL** when neither of the above applies. This is `referred`,
    #      not `delivered`: nothing was submitted and the candidate is told so.
    #   4. Nothing available at all is `failed`.
    #
    # Every skipped or failed link is written to `handoff_error`, including a
    # missing credential, so an operator can see why a handoff took the path
    # it did.
    class ApplicationHandoff
      struct Outcome
        getter status : String
        getter method : String?
        getter reference : String?
        getter notes : Array(String)

        def initialize(
          @status : String,
          @method : String? = nil,
          @reference : String? = nil,
          @notes : Array(String) = [] of String,
        )
        end

        def delivered? : Bool
          status == JobApplication::STATUS_DELIVERED
        end

        def error_text : String?
          return nil if notes.empty?
          notes.join("; ")
        end
      end

      def initialize(@client : Client = Ats.build_client)
      end

      # Runs the chain and persists the result. Returns the reloaded record so
      # callers read the stored status rather than a hopeful in-memory guess.
      def deliver(application : JobApplication, job : Job) : JobApplication
        outcome = attempt(job, application)
        persist(application, outcome)
      end

      private def attempt(job : Job, application : JobApplication) : Outcome
        notes = [] of String
        connection = connection_for(job)
        adapter = connection ? Registry[connection.provider]? : nil

        if connection && adapter && adapter.supports_application_api?
          external_id = job.external_id

          if external_id.nil?
            notes << "#{adapter.display_name} API skipped: posting has no external id"
          elsif !CrystalGigs::AtsConfig.credential_configured?(adapter.key)
            notes << "#{adapter.display_name} API skipped: #{adapter.credential_env_key} is not set"
          else
            begin
              receipt = adapter.submit_application(
                connection.board_token,
                external_id,
                ApplicationPayload.from(application),
                @client
              )
              return Outcome.new(
                status: JobApplication::STATUS_DELIVERED,
                method: JobApplication::METHOD_ATS_API,
                reference: receipt.reference || "HTTP #{receipt.status}",
                notes: notes
              )
            rescue ex : Ats::Error
              notes << "#{adapter.display_name} API failed: #{ex.message}"
              # Terminal on purpose. See the class comment.
              return Outcome.new(
                status: JobApplication::STATUS_FAILED,
                method: JobApplication::METHOD_ATS_API,
                notes: notes
              )
            end
          end
        end

        if address = application_email(job, connection)
          case sender = CrystalGigs::AtsConfig.from_address?
          when Nil
            notes << "Email handoff skipped: #{CrystalGigs::AtsConfig::FROM_ADDRESS_ENV_KEY} is not set"
          else
            begin
              JobApplicationEmail.new(
                job: job,
                application: application,
                recipient: address,
                sender: sender
              ).deliver
              return Outcome.new(
                status: JobApplication::STATUS_DELIVERED,
                method: JobApplication::METHOD_EMAIL,
                reference: address,
                notes: notes
              )
            rescue ex
              notes << "Email to #{address} failed: #{ex.message}"
            end
          end
        end

        apply_url = job.apply_url
        unless apply_url.blank?
          return Outcome.new(
            status: JobApplication::STATUS_REFERRED,
            method: JobApplication::METHOD_APPLY_URL,
            reference: apply_url,
            notes: notes
          )
        end

        notes << "No handoff route: the posting has no application email and no apply URL"
        Outcome.new(status: JobApplication::STATUS_FAILED, notes: notes)
      end

      private def connection_for(job : Job) : AtsConnection?
        connection_id = job.ats_connection_id
        return nil if connection_id.nil?

        AtsConnectionQuery.new.id(connection_id).first?
      end

      private def application_email(job : Job, connection : AtsConnection?) : String?
        [connection.try(&.application_email), job.apply_email]
          .compact
          .find { |address| !address.blank? }
      end

      private def persist(application : JobApplication, outcome : Outcome) : JobApplication
        SaveJobApplication.update!(
          application,
          handoff_status: outcome.status,
          handoff_method: outcome.method,
          handoff_reference: outcome.reference,
          handoff_error: outcome.error_text,
          handed_off_at: Time.utc
        )
      end
    end
  end
end
