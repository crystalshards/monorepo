require "../spec_helper"

describe DocVersionQuery do
  describe "#for_doc" do
    it "finds versions for a specific doc" do
      doc1 = DocFactory.create
      doc2 = DocFactory.create

      version1 = DocVersionFactory.create &.doc_id(doc1.id)
      version2 = DocVersionFactory.create &.doc_id(doc2.id)

      results = DocVersionQuery.new.for_doc(doc1).results

      results.should contain(version1)
      results.should_not contain(version2)
    end
  end

  describe "#for_doc_id" do
    it "finds versions by doc_id" do
      doc = DocFactory.create
      version = DocVersionFactory.create &.doc_id(doc.id)

      results = DocVersionQuery.new.for_doc_id(doc.id).results

      results.should contain(version)
    end
  end

  describe "#latest_first" do
    it "orders versions by published_at descending" do
      doc = DocFactory.create

      old_version = DocVersionFactory.create &.doc_id(doc.id)
        .version("1.0.0")
        .published_at(Time.utc - 10.days)
      new_version = DocVersionFactory.create &.doc_id(doc.id)
        .version("2.0.0")
        .published_at(Time.utc)
      middle_version = DocVersionFactory.create &.doc_id(doc.id)
        .version("1.5.0")
        .published_at(Time.utc - 5.days)

      results = DocVersionQuery.new.latest_first.results

      results.first.should eq(new_version)
      results[1].should eq(middle_version)
      results.last.should eq(old_version)
    end
  end

  describe "#successful" do
    it "filters to only successful builds" do
      doc = DocFactory.create

      success = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("success")
      failed = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("failed")
      pending = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("pending")

      results = DocVersionQuery.new.successful.results

      results.should contain(success)
      results.should_not contain(failed)
      results.should_not contain(pending)
    end
  end

  describe "#failed" do
    it "filters to only failed builds" do
      doc = DocFactory.create

      success = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("success")
      failed = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("failed")

      results = DocVersionQuery.new.failed.results

      results.should contain(failed)
      results.should_not contain(success)
    end
  end

  describe "#pending" do
    it "filters to only pending builds" do
      doc = DocFactory.create

      success = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("success")
      pending = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("pending")

      results = DocVersionQuery.new.pending.results

      results.should contain(pending)
      results.should_not contain(success)
    end
  end

  describe "#version_number" do
    it "finds version by version string" do
      doc = DocFactory.create

      v1 = DocVersionFactory.create &.doc_id(doc.id).version("1.0.0")
      v2 = DocVersionFactory.create &.doc_id(doc.id).version("2.0.0")

      result = DocVersionQuery.new.version_number("1.0.0").first

      result.should eq(v1)
    end
  end

  describe "chaining queries" do
    it "allows chaining multiple query methods" do
      doc = DocFactory.create

      old_success = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("success")
        .published_at(Time.utc - 10.days)
      new_success = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("success")
        .published_at(Time.utc)
      new_failed = DocVersionFactory.create &.doc_id(doc.id)
        .build_status("failed")
        .published_at(Time.utc)

      results = DocVersionQuery.new
        .for_doc(doc)
        .successful
        .latest_first
        .results

      results.first.should eq(new_success)
      results.last.should eq(old_success)
      results.should_not contain(new_failed)
    end
  end
end
