# typed: strict
# frozen_string_literal: true

require_relative 'spec_helper'

# Dummy model for testing ImmutableFields
class ImmutableOrder < ActiveRecord::Base
  self.table_name = 'orders'

  include SorbetConcerns::ImmutableFields

  immutable_fields :entity_id, :country_id, :kind
  write_once_fields :source_id, :source_record_id
end

RSpec.describe SorbetConcerns::ImmutableFields do
  let(:order) { ImmutableOrder.create!(entity_id: 'E1', country_id: 'US', kind: 'standard') }

  describe 'immutable fields' do
    it 'allows setting immutable fields on creation' do
      expect(order).to be_valid
      expect(order.entity_id).to eq('E1')
    end

    it 'blocks changing an immutable field after creation' do
      expect(order.update(entity_id: 'E2')).to be false
      expect(order.errors[:entity_id]).to include(/cannot be changed after creation/)
    end

    it 'blocks changing multiple immutable fields' do
      order.country_id = 'CA'
      order.kind = 'premium'
      expect(order).not_to be_valid
      expect(order.errors[:country_id]).not_to be_empty
      expect(order.errors[:kind]).not_to be_empty
    end

    it 'allows saving other fields when immutable fields are unchanged' do
      expect(order.update(source_id: 'S1')).to be true
    end

    it 'allows nil immutable fields on creation that are later set' do
      # Create without the immutable field — nil in DB
      bare = ImmutableOrder.create!(kind: 'standard')
      # Setting it later is allowed because attribute_in_database was nil
      expect(bare.update(entity_id: 'E1')).to be true
    end
  end

  describe 'write-once fields' do
    it 'allows setting a write-once field from nil on creation' do
      doc = ImmutableOrder.create!(source_id: 'S1')
      expect(doc.source_id).to eq('S1')
    end

    it 'allows setting a write-once field from nil after creation' do
      # Created without source_id
      expect(order.update(source_id: 'S1')).to be true
    end

    it 'blocks changing a write-once field once set' do
      order.update!(source_id: 'S1')
      expect(order.update(source_id: 'S2')).to be false
      expect(order.errors[:source_id]).to include(/cannot be changed once set/)
    end

    it 'allows multiple write-once fields to be set independently' do
      order.update!(source_id: 'S1')
      expect(order.update(source_record_id: 'R1')).to be true
    end
  end

  describe 'new record short-circuit' do
    it 'does not validate immutability on unsaved records' do
      fresh = ImmutableOrder.new(entity_id: 'E1')
      fresh.entity_id = 'E2'
      expect(fresh).to be_valid
    end
  end
end
