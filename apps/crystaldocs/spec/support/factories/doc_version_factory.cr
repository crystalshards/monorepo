class DocVersionFactory < Avram::Factory
  def initialize
    version "1.0.0"
    published_at Time.utc
    build_status "success"
    storage_path "sample-package/1.0.0"
  end
end
