class DocFactory < Avram::Factory
  def initialize
    package_name "sample-package"
    current_version "1.0.0"
    description "A sample Crystal package documentation"
    total_views 0
  end
end
