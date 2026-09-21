# frozen_string_literal: true

require_relative 'lib/sorbet_concerns/version'

Gem::Specification.new do |spec|
  spec.name = 'sorbet-concerns'
  spec.version = SorbetConcerns::VERSION
  spec.authors = ['ukier']
  spec.summary = 'Typed ActiveSupport::Concern building blocks for Sorbet + Rails'
  spec.description = 'Provides typed: strong concern helpers that eliminate T.bind/T.unsafe ' \
                     'boilerplate when using ActiveSupport::Concern with Sorbet-typed Rails models.'
  spec.homepage = 'https://github.com/kierr/sorbet-concerns'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.files = Dir.glob('{lib,sorbet}/**/*').reject { |f| File.directory?(f) } + %w[README.md LICENSE CHANGELOG.md]
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.add_dependency 'activerecord', '>= 7.0', '< 9'
  spec.add_dependency 'activesupport', '>= 7.0', '< 9'
  spec.add_dependency 'sorbet-runtime', '~> 0.5'

  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.91'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'sorbet-static', '~> 0.5'
  spec.add_development_dependency 'sqlite3', '~> 2.0'
end
