ATS_FIXTURE_DIR = File.join(__DIR__, "..", "fixtures", "ats")

# Payloads recorded from the providers' real public endpoints.
def ats_fixture(name : String) : String
  File.read(File.join(ATS_FIXTURE_DIR, name))
end

# Runs the block with the recorded client installed everywhere the importer
# and the handoff service build one, then restores the real factory.
def with_ats_client(client : CrystalGigs::Ats::Client, &)
  previous = CrystalGigs::Ats.client_factory
  CrystalGigs::Ats.client_factory = -> { client.as(CrystalGigs::Ats::Client) }
  begin
    yield
  ensure
    CrystalGigs::Ats.client_factory = previous
  end
end

# Sets environment configuration for the duration of a block. A nil value
# unsets the variable, which is how the "credential missing" paths are
# exercised without depending on the developer's own environment.
def with_ats_env(values : Hash(String, String?), &)
  previous = {} of String => String?

  values.each do |key, value|
    previous[key] = ENV[key]?
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
    end
  end

  begin
    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
