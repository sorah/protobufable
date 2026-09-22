# frozen_string_literal: true

require_relative "lib/protobufable/version"

Gem::Specification.new do |spec|
  spec.name = "protobufable"
  spec.version = Protobufable::VERSION
  spec.authors = ["Sorah Fukumori"]
  spec.email = ["sorah@ivry.jp"]
  spec.summary = "Protocol Buffers as the schema of record for a Rails API."
  spec.description = "Parses JSON request bodies into generated protobuf message classes, " \
    "stores messages in json and jsonb columns, catalogues RFC 9457 problems in a protobuf " \
    "enum, and binds Alba serializers to the messages they produce."
  spec.homepage = "https://github.com/sorah/protobufable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true",
  }

  # proto/ and its generated output are deliberately absent: the custom option number is
  # provisional until protobufable has an entry in protocolbuffers/protobuf docs/options.md,
  # and an importable annotation whose number can still move is worse than none. See DESIGN.md.
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "DESIGN.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 7.1"
  spec.add_dependency "activemodel", ">= 7.1"
  spec.add_dependency "activerecord", ">= 7.1"
  spec.add_dependency "activesupport", ">= 7.1"
  spec.add_dependency "google-protobuf", "~> 4.26"

  spec.add_development_dependency "railties", ">= 7.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rbs", "~> 4.0"
  spec.add_development_dependency "rbs-inline", "~> 0.14"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rubocop", "~> 1.82.0"
  spec.add_development_dependency "rubocop-shopify", "~> 2.18"
  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "steep", "~> 2.0"
  spec.add_development_dependency "yard", "~> 0.9"
  # The gems the optional integrations bind to are in the Gemfile instead: they are not
  # dependencies of this gem in any sense, and one of them is not on RubyGems yet.
end
