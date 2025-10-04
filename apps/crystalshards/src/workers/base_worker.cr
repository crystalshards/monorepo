require "joobq"

module CrystalShards::Workers
  abstract class BaseWorker
    include Joobq::Worker

    # Override to set worker-specific options
    def self.queue : String
      "default"
    end

    def self.retries : Int32
      3
    end

    def self.timeout : Time::Span
      5.minutes
    end

    # Log helper
    private def log_info(message : String)
      Log.info { "#{self.class.name}: #{message}" }
    end

    private def log_error(message : String, exception : Exception? = nil)
      if exception
        Log.error(exception: exception) { "#{self.class.name}: #{message}" }
      else
        Log.error { "#{self.class.name}: #{message}" }
      end
    end
  end
end
