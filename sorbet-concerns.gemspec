# frozen_string_literal: true

require_relative "lib/sorbet_concerns/version"

Gem::Specification.new do |spec|
  spec.name = "sorbet-concerns"
  spec.version = SorbetConcerns::VERSION
  spec.authors = ["ukier"]
  spec.summary = "Typed ActiveSupport::Concern building blocks for Sorbet + Rails"
  spec.description = "Provides typed: strong concern helpers that eliminate T.bind/T.unsafe " \
                     "boilerplate when using ActiveSupport::Concern with Sorbet-typed Rails models."
  spec.homepage = "https://github.com/kierr/sorbet-concerns"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.glob("{lib,sorbet}/**/*").reject { |f| File.directory?(f) } + %w[README.md LICENSE CHANGELOG.md]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "sorbet-runtime"

  spec.add_development_dependency "activerecord", ">= 7.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "sorbet-static"
  spec.add_development_dependency "sqlite3", "~> 2.0"
end
