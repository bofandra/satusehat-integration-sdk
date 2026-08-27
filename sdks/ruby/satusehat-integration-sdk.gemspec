Gem::Specification.new do |spec|
    spec.name = "satusehat-integration-sdk"
    spec.version = "0.2.0"
    spec.summary = "SATUSEHAT Integration SDK reference implementation for Ruby"
    spec.description = "OAuth2, FHIR HTTP, SQLite queue, retry, and worker primitives for SATUSEHAT integrations."
    spec.authors = ["SATUSEHAT Integration SDK Contributors"]
    spec.license = "Apache-2.0"
    spec.homepage = "https://github.com/bofandra/satusehat-integration-sdk"
    spec.metadata = {
        "homepage_uri" => "https://github.com/bofandra/satusehat-integration-sdk",
        "source_code_uri" => "https://github.com/bofandra/satusehat-integration-sdk",
        "bug_tracker_uri" => "https://github.com/bofandra/satusehat-integration-sdk/issues",
        "changelog_uri" => "https://github.com/bofandra/satusehat-integration-sdk/blob/main/CHANGELOG.md"
    }

    spec.required_ruby_version = ">= 3.1"
    spec.files = Dir["lib/**/*.rb", "examples/**/*.rb", "README.md"]
    spec.require_paths = ["lib"]

    spec.add_dependency "sqlite3", ">= 1.6", "< 3.0"
    spec.add_development_dependency "minitest", "~> 5.0"
    spec.add_development_dependency "rake", "~> 13.0"
end
