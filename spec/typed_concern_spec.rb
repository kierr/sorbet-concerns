# typed: strict
# frozen_string_literal: true

require_relative "spec_helper"

# Dummy model that includes TypedConcern directly
class TypedOrder < ActiveRecord::Base
  self.table_name = "orders"

  include SorbetConcerns::TypedConcern

  # typed_class is available as a class method after including
  typed_class.validates :status, presence: true
  typed_class.enum :status, %w[draft submitted approved], prefix: true

  def active?
    typed_instance.status == "approved"
  end
end

# Dummy concern that uses typed_class (requires models to include TypedConcern first)
module StatusDefaults
  extend ActiveSupport::Concern

  included do
    # typed_class is available because the model includes TypedConcern
    typed_class.validates :kind, presence: true
  end

  class_methods do
    def build_default_status
      new(status: :draft, kind: "standard")
    end
  end
end

# Model that includes both TypedConcern and a concern that uses typed_class
class ConcernedOrder < ActiveRecord::Base
  self.table_name = "orders"

  include SorbetConcerns::TypedConcern
  include StatusDefaults
end

RSpec.describe SorbetConcerns::TypedConcern do
  describe "direct include in model" do
    it "makes typed_class available as a class method" do
      order = TypedOrder.new(status: nil)
      expect(order).not_to be_valid
      expect(order.errors[:status]).to include("can't be blank")
    end

    it "provides enum methods via typed_class.enum" do
      expect(TypedOrder.statuses.keys).to include("draft", "submitted", "approved")
    end

    it "makes typed_instance available in instance methods" do
      order = TypedOrder.new(status: :approved)
      expect(order).to be_active
    end
  end

  describe "concern using typed_class" do
    it "makes typed_class available in the concern's included block" do
      order = ConcernedOrder.new(status: :draft, kind: nil)
      expect(order).not_to be_valid
      expect(order.errors[:kind]).to include("can't be blank")
    end

    it "makes class_methods blocks work in the concern" do
      expect(ConcernedOrder).to respond_to(:build_default_status)
      order = ConcernedOrder.build_default_status
      expect(order.status).to eq("draft")
      expect(order.kind).to eq("standard")
    end

    it "typed_instance is available in the including model" do
      order = ConcernedOrder.new(status: :draft)
      expect(order).to respond_to(:typed_instance)
    end
  end
end
