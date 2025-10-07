require "../../../spec_helper"

describe Api::Docs::Index do
  it "returns empty array when no docs exist" do
    response = ApiClient.exec(Api::Docs::Index)

    response.should send_json(200, {docs: [] of String, meta: {page: 1, per_page: 20, total: 0}})
  end

  it "returns list of docs" do
    doc = DocFactory.create &.package_name("test-package")
      .description("A test package documentation")
      .current_version("1.0.0")

    response = ApiClient.exec(Api::Docs::Index)

    response.should send_json(200)
    response.body.should contain("test-package")
    response.body.should contain("A test package documentation")
  end

  it "supports pagination" do
    25.times do |i|
      DocFactory.create &.package_name("package-#{i}")
        .current_version("1.0.0")
    end

    response = ApiClient.exec(Api::Docs::Index.with(page: 2, per_page: 10))

    response.should send_json(200)
    json = JSON.parse(response.body)
    json["docs"].as_a.size.should eq(10)
    json["meta"]["page"].should eq(2)
  end

  it "supports search by package name" do
    DocFactory.create &.package_name("awesome-lib").current_version("1.0.0")
    DocFactory.create &.package_name("cool-tool").current_version("2.0.0")

    response = ApiClient.exec(Api::Docs::Index.with(query: "awesome"))

    response.should send_json(200)
    response.body.should contain("awesome-lib")
    response.body.should_not contain("cool-tool")
  end
end
