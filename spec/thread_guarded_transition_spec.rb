# typed: strict
# frozen_string_literal: true

require_relative "spec_helper"

# Dummy model for testing ThreadGuardedTransition
class GuardedOrder < ActiveRecord::Base
  self.table_name = "orders"

  include SorbetConcerns::ThreadGuardedTransition

  guard_transition_on :status, error_message: "must be changed through an authorized service"
end

RSpec.describe SorbetConcerns::ThreadGuardedTransition do
  let(:order) { GuardedOrder.create!(status: "draft") }

  describe "guard callback" do
    it "blocks direct mutation of guarded field" do
      expect(order.update(status: "submitted")).to be false
      expect(order.errors[:status]).to include("must be changed through an authorized service")
    end

    it "allows updating non-guarded fields" do
      expect(order.update(entity_id: "E1")).to be true
    end

    it "aborts the save (throw :abort)" do
      # The callback uses Kernel.throw(:abort), so the update returns false
      # and the in-memory value should NOT be changed
      order.update(status: "submitted")
      expect(order.reload.status).to eq("draft")
    end
  end

  describe "class-level authorization: allow_transition_on!" do
    it "allows transition within the authorized block" do
      GuardedOrder.allow_transition_on!(:status) do
        expect(order.update(status: "submitted")).to be true
      end
      expect(order.reload.status).to eq("submitted")
    end

    it "restores authorization state after the block" do
      GuardedOrder.allow_transition_on!(:status) do
        # authorized
      end
      # After the block, direct mutation should be blocked again
      expect(order.update(status: "submitted")).to be false
    end

    it "preserves outer authorization in nested blocks" do
      GuardedOrder.allow_transition_on!(:status) do
        GuardedOrder.allow_transition_on!(:status) do
          # inner block
        end
        # Still authorized — inner ensure restored outer value (true)
        expect(order.update(status: "submitted")).to be true
      end
    end
  end

  describe "instance-level authorization: with_transition_allowed" do
    it "allows transition within the instance-scoped block" do
      order.with_transition_allowed(:status) do
        expect(order.update(status: "submitted")).to be true
      end
      expect(order.reload.status).to eq("submitted")
    end

    it "does not authorize other instances" do
      other = GuardedOrder.create!(status: "draft")
      order.with_transition_allowed(:status) do
        # order is authorized, other is not
        expect(other.update(status: "submitted")).to be false
      end
    end

    it "restores authorization state after the block" do
      order.with_transition_allowed(:status) do
        # authorized
      end
      expect(order.update(status: "submitted")).to be false
    end
  end

  describe "transition_allowed? predicate (instance)" do
    it "returns false outside an authorized block" do
      expect(order.transition_allowed?(:status)).to be false
    end

    it "returns true inside an authorized block" do
      order.with_transition_allowed(:status) do
        expect(order.transition_allowed?(:status)).to be true
      end
    end
  end

  describe "transition_allowed_on? predicate (class)" do
    it "returns false outside an authorized block" do
      expect(GuardedOrder.transition_allowed_on?(:status)).to be false
    end

    it "returns true inside an authorized block" do
      GuardedOrder.allow_transition_on!(:status) do
        expect(GuardedOrder.transition_allowed_on?(:status)).to be true
      end
    end
  end

  describe "thread safety" do
    it "class-level authorization is thread-local" do
      # Main thread authorizes, then checks from another thread
      GuardedOrder.allow_transition_on!(:status) do
        authorized_in_main = GuardedOrder.transition_allowed_on?(:status)
        expect(authorized_in_main).to be true

        # Another thread should NOT see the authorization
        other_thread_result = nil
        Thread.new { other_thread_result = GuardedOrder.transition_allowed_on?(:status) }.join
        expect(other_thread_result).to be false
      end
    end
  end
end
