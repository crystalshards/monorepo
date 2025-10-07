require "../../../spec_helper"

describe Api::Docs::Show do
  it "returns 404 when doc does not exist" do
    response = ApiClient.exec(Api::Docs::Show.with(package_name: "nonexistent"))

    response.status_code.should eq(404)
  end

  it "returns doc with versions" do
    doc = DocFactory.create &.package_name("test-package")
      .description("A test package")
      .current_version("1.0.0")

    version1 = DocVersionFactory.create &.doc_id(doc.id)
      .version("1.0.0")
      .published_at(Time.utc)
      .build_status("success")
      .storage_path("test-package/1.0.0")

    version2 = DocVersionFactory.create &.doc_id(doc.id)
      .version("0.9.0")
      .published_at(Time.utc - 1.day)
      .build_status("success")
      .storage_path("test-package/0.9.0")

    response = ApiClient.exec(Api::Docs::Show.with(package_name: "test-package"))

    response.should send_json(200)
    response.body.should contain("test-package")
    response.body.should contain("1.0.0")
    response.body.should contain("0.9.0")
  end
end
