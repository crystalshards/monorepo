class Api::Ats::Connections::Index < ApiAction
  get "/api/ats/connections" do
    connections = AtsConnectionQuery.new.for_user(current_user).recent

    json({
      connections: AtsConnectionSerializer.for_collection(connections),
      providers:   CrystalGigs::Ats::Registry.adapters.map { |adapter|
        {
          key:                    adapter.key,
          name:                   adapter.display_name,
          submits_applications:   adapter.supports_application_api?,
          credential_configured:  adapter.application_api_available?,
          credential_environment: adapter.credential_env_key,
        }
      },
    })
  end
end
