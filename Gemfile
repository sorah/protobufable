# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# The gems the optional integrations bind to. None of them is a dependency of protobufable —
# each is reached only through a `require` the host opts into — so they live here and the
# suite exercises them.
gem "alba", "~> 4.0"
gem "protovalidate", "~> 0.1.0.beta3"

# Not on RubyGems yet; tracked from the repository until it is released.
gem "problem", git: "https://github.com/sorah/problem.git", branch: "main"
