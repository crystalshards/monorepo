require "../../spec_helper"

describe CrystalGigs::Ats::Registry do
  it "has both shipped adapters registered under their provider keys" do
    CrystalGigs::Ats::Registry.keys.should eq(["greenhouse", "lever"])
  end

  it "looks an adapter up by key, case and padding insensitively" do
    CrystalGigs::Ats::Registry.fetch(" Greenhouse ").should be_a(CrystalGigs::Ats::Adapters::Greenhouse)
  end

  it "raises a listing error for a provider with no adapter" do
    expect_raises(CrystalGigs::Ats::UnknownProviderError, /greenhouse, lever/) do
      CrystalGigs::Ats::Registry.fetch("workday")
    end
  end

  it "answers registered? without raising" do
    CrystalGigs::Ats::Registry.registered?("lever").should be_true
    CrystalGigs::Ats::Registry.registered?("workday").should be_false
    CrystalGigs::Ats::Registry.registered?(nil).should be_false
  end

  # A third ATS is a new subclass plus one register call, nothing else.
  it "accepts a new adapter without any change to the importer or the actions" do
    CrystalGigs::Ats::Registry.register(FakeAtsAdapter.new)

    begin
      CrystalGigs::Ats::Registry.fetch("fake").display_name.should eq("Fake ATS")

      connection = AtsConnectionFactory.create &.provider("fake").board_token("acme")
      client = RecordedAtsClient.new
      client.stub_get("fake-ats.example.com", %([{"id": "f1", "title": "Fake Job"}]))

      report = CrystalGigs::Ats::Importer.new(client).sync(connection)

      report.ok?.should be_true
      report.created.should eq(1)
      JobQuery.new.for_import(connection, "f1").first.title.should eq("Fake Job")
    ensure
      CrystalGigs::Ats::Registry.unregister("fake")
    end
  end
end
