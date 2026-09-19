# typed: strict
# frozen_string_literal: true

require_relative "spec_helper"

# Dummy model with state transitions
class Order < ActiveRecord::Base
  include SorbetConcerns::StateTransitionValidatable

  VALID_TRANSITIONS = {
    "draft"     => %w[submitted cancelled],
    "submitted" => %w[approved cancelled],
    "approved"  => %w[shipped],
    "shipped"   => %w[delivered],
    "cancelled" => %w[],
    "delivered" => %w[]
  }.freeze

  validate_state_transitions_on :status
end

# Dummy model with custom transitions constant and unknown_state_handler: :allow
class Document < ActiveRecord::Base
  include SorbetConcerns::StateTransitionValidatable

  PHASE_MAP = {
    "draft"     => %w[reviewed],
    "reviewed"  => %w[published]
  }.freeze

  validate_state_transitions_on :phase, transitions_constant: :PHASE_MAP, unknown_state_handler: :allow
end

RSpec.describe SorbetConcerns::StateTransitionValidatable do
  let(:order) { Order.create!(status: :draft) }

  describe "valid transitions" do
    it "allows draft -> submitted" do
      expect(order.update(status: :submitted)).to be true
      expect(order.reload.status).to eq("submitted")
    end

    it "allows submitted -> approved" do
      order.update!(status: :submitted)
      expect(order.update(status: :approved)).to be true
    end

    it "allows draft -> cancelled" do
      expect(order.update(status: :cancelled)).to be true
    end
  end

  describe "invalid transitions" do
    it "rejects draft -> approved (skipping submitted)" do
      expect(order.update(status: :approved)).to be false
      expect(order.errors[:status]).to include("cannot transition from draft to approved")
    end

    it "rejects draft -> delivered (two steps away)" do
      expect(order.update(status: :delivered)).to be false
      expect(order.errors[:status]).to include("cannot transition from draft to delivered")
    end

    it "rejects transition from terminal state" do
      order.update!(status: :cancelled)
      expect(order.update(status: :draft)).to be false
      expect(order.errors[:status]).to include("cannot transition from cancelled to draft")
    end
  end

  describe "unchanged field short-circuit" do
    it "skips validation when status is not changed" do
      order.update!(status: :submitted)
      # Updating a different field should not trigger transition validation
      expect(order.update(created_at: 1.day.ago)).to be true
    end
  end

  describe "new record short-circuit" do
    it "does not validate transitions on unsaved records" do
      fresh = Order.new(status: :approved)
      expect(fresh).to be_valid
    end
  end

  describe "generated validation method" do
    it "defines a status_transition_valid method" do
      expect(Order.instance_methods(true)).to include(:status_transition_valid)
    end

    it "registers the method as a validate callback" do
      callback_names = Order._validate_callbacks.map(&:filter).map(&:inspect)
      expect(callback_names.any? { |n| n.include?("status_transition_valid") }).to be true
    end
  end

  describe "custom transitions_constant" do
    it "uses the custom constant name" do
      doc = Document.create!(phase: :draft)
      expect(doc.update(phase: :reviewed)).to be true
    end

    it "generates the method with the correct field name" do
      expect(Document.instance_methods(true)).to include(:phase_transition_valid)
    end
  end

  describe "unknown_state_handler: :allow" do
    it "allows any transition from an unknown previous state" do
      doc = Document.create!(phase: :draft)
      doc.update!(phase: :reviewed)
      # Corrupt the stored value to one not in PHASE_MAP keys
      doc.update_columns(phase: "unknown_state")
      # With :allow, this should pass (previous state "unknown_state" has no entry)
      expect(doc.update(phase: :draft)).to be true
    end
  end

  describe "unknown_state_handler: :error (default)" do
    it "reports unknown previous state" do
      order.update!(status: :submitted)
      # Corrupt to a value not in VALID_TRANSITIONS keys
      order.update_columns(status: 999)
      # With :error (default), unknown state blocks the transition
      expect(order.update(status: :draft)).to be false
      expect(order.errors[:status].any? { |e| e.include?("unknown previous state") }).to be true
    end
  end
end
