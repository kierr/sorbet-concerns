# typed: strict
# frozen_string_literal: true

require "active_record"
require "sorbet-runtime"
require "sorbet-concerns"

# In-memory SQLite database for testing
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# Suppress migration output during tests
ActiveRecord::Migration.verbose = false

# Create the schema for dummy models
ActiveRecord::Schema.define do
  create_table :orders, force: true do |t|
    t.string :status, null: false, default: "draft"
    t.string :entity_id
    t.string :country_id
    t.string :kind
    t.string :source_id
    t.string :source_record_id
    t.integer :lifecycle_state, null: false, default: 0
    t.timestamps null: false
  end

  create_table :documents, force: true do |t|
    t.string :phase, null: false, default: "draft"
    t.timestamps null: false
  end
end

RSpec.configure do |config|
  config.order = :random
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Wrap each test in a transaction and roll back
  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
