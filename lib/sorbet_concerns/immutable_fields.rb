# typed: strong
# frozen_string_literal: true

require "active_support/concern"

module SorbetConcerns
  # Validates that specified fields cannot change after creation (immutable)
  # or can only be set once (write-once / provenance pattern).
  #
  # Immutable fields: cannot change from any value to any other value after
  # the record is persisted. To change identity, create a new record.
  #
  # Write-once fields: nil → value is allowed, but value → different_value
  # is blocked. Useful for provenance/audit fields that record the origin
  # of a record once and must not be altered.
  #
  # Usage:
  #   class Document < ActiveRecord::Base
  #     include SorbetConcerns::ImmutableFields
  #
  #     immutable_fields :entity_id, :country_id, :kind
  #     write_once_fields :source_id, :source_record_id
  #   end
  #
  #   doc = Document.create!(entity_id: 1, country_id: 'US', source_id: 42)
  #   doc.update(entity_id: 2)     # => false, errors[:entity_id]
  #   doc.update(source_id: 99)    # => false, errors[:source_id] — already set
  #   doc.update(country_id: 'CA') # => false, errors[:country_id]
  #
  # RATIONALE: Extracted from repeated immutable-core-field and provenance-write-once
  # validation patterns. The validation logic is identical across models; only the
  # field lists differ. Would need model-specific immutability rules (conditional,
  # state-dependent) to reconsider.
  module ImmutableFields
    extend ActiveSupport::Concern
    extend T::Sig

    class_methods do
      extend T::Sig

      # Declares fields that cannot change after creation.
      # Adds a validation that blocks any change to listed fields on persisted records.
      sig { params(fields: Symbol).void }
      def immutable_fields(*fields)
        # RATIONALE: define_method — metaprogramming in AS::Concern class_methods block.
        # Would need AS::Concern typed RBI to reconsider.
        T.bind(self, T.class_of(ActiveRecord::Base)).define_method(:validate_immutable_fields) do
          validate_fields_immutable(fields)
        end

        T.bind(self, T.class_of(ActiveRecord::Base)).validate(:validate_immutable_fields)
      end

      # Declares fields that can be set once (nil → value) but cannot be changed
      # once set (value → different_value).
      sig { params(fields: Symbol).void }
      def write_once_fields(*fields)
        # RATIONALE: define_method — metaprogramming in AS::Concern class_methods block.
        # Would need AS::Concern typed RBI to reconsider.
        T.bind(self, T.class_of(ActiveRecord::Base)).define_method(:validate_write_once_fields) do
          validate_fields_write_once(fields)
        end

        T.bind(self, T.class_of(ActiveRecord::Base)).validate(:validate_write_once_fields)
      end
    end

    private

    sig { params(fields: T::Array[Symbol]).void }
    def validate_fields_immutable(fields)
      return unless persisted?

      fields.each do |attr|
        next unless attribute_changed?(attr.to_s)

        # attribute_in_database returns Object per RBI — nil? check is safe on any Ruby value.
        # A nil value from attribute_in_database means the field was nil before this change,
        # which is a valid initial set on a persisted record (e.g., created without the field).
        # RATIONALE: send/attribute_in_database returns untyped; T.cast to nullable Object.
        # Would need typed AR concern RBIs to remove.
        next if T.cast(attribute_in_database(attr.to_s), T.nilable(Object)).nil?

        errors.add(attr, "cannot be changed after creation — create a replacement instead")
      end
    end

    sig { params(fields: T::Array[Symbol]).void }
    def validate_fields_write_once(fields)
      return unless persisted?

      fields.each do |attr|
        next unless attribute_changed?(attr.to_s)

        # attribute_in_database returns the pre-change value. If it's nil,
        # the field is being set for the first time — that's allowed.
        # RATIONALE: send/attribute_in_database returns untyped; T.cast to nullable Object.
        # Would need typed AR concern RBIs to remove.
        next if T.cast(attribute_in_database(attr.to_s), T.nilable(Object)).nil?

        errors.add(attr, "cannot be changed once set")
      end
    end
  end
end
