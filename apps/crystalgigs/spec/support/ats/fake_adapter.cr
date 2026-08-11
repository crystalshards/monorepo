# A third ATS, written the way a real one would be: subclass the adapter,
# implement the interface, register it. Nothing in the importer, the handoff
# service or the actions knows this exists, which is the property the registry
# spec checks.
class FakeAtsAdapter < CrystalGigs::Ats::Adapter
  def key : String
    "fake"
  end

  def display_name : String
    "Fake ATS"
  end

  def board_url(board_token : String) : String
    "https://fake-ats.example.com/boards/#{board_token}"
  end

  def supports_application_api? : Bool
    false
  end

  def parse_postings(payload : String) : Array(CrystalGigs::Ats::Posting)
    entries = JSON.parse(payload).as_a

    entries.map do |entry|
      external_id = entry["id"].as_s

      CrystalGigs::Ats::Posting.new(
        external_id: external_id,
        title: entry["title"].as_s,
        description: "A fake posting.",
        apply_url: "https://fake-ats.example.com/apply/#{external_id}"
      )
    end
  end

  def submit_application(
    board_token : String,
    external_id : String,
    payload : CrystalGigs::Ats::ApplicationPayload,
    client : CrystalGigs::Ats::Client,
  ) : CrystalGigs::Ats::Receipt
    raise CrystalGigs::Ats::Error.new("Fake ATS does not accept applications")
  end
end
