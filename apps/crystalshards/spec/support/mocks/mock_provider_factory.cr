require "../../../src/providers/provider_factory"
require "./mock_provider"

# Override ProviderFactory.create to return MockProvider in tests
module TestProviderFactory
  @@mock_provider : MockProvider?

  def self.set_mock(provider : MockProvider)
    @@mock_provider = provider
  end

  def self.reset
    @@mock_provider = nil
  end

  def self.get_mock : MockProvider?
    @@mock_provider
  end
end

# Monkey patch ProviderFactory for testing
class ProviderFactory
  def self.create(repository_url : String) : BaseProvider
    if mock = TestProviderFactory.get_mock
      mock
    else
      detect_and_create(repository_url)
    end
  end
end
