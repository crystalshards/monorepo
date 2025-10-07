require "mosquito"

module CrystalShards::Workers
  # Base class for all background jobs
  abstract class BaseJob < Mosquito::QueuedJob
    # Log helper
    protected def log_info(message : String)
      Log.info { "#{self.class.name}: #{message}" }
    end

    protected def log_error(message : String, exception : Exception? = nil)
      if exception
        Log.error(exception: exception) { "#{self.class.name}: #{message}" }
      else
        Log.error { "#{self.class.name}: #{message}" }
      end
    end
  end
end
