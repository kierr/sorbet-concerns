# typed: strong
# frozen_string_literal: true

require 'active_support/concern'

module SorbetConcerns
  # Validates that state transitions follow a declared transition map.
  #
  # Models define a hash constant (default: VALID_TRANSITIONS) mapping each
  # state to an array of allowed next states. The concern generates a
  # validation method named "#{field}_transition_valid" and registers it.
  #
  # Usage:
  #   class Order < ActiveRecord::Base
  #     include SorbetConcerns::StateTransitionValidatable
  #
  #     VALID_TRANSITIONS = {
  #       'draft'     => %w[submitted cancelled],
  #       'submitted' => %w[approved cancelled],
  #       'approved'  => %w[shipped],
  #       'shipped'   => %w[delivered],
  #       'cancelled' => %w[],
  #       'delivered' => %w[]
  #     }.freeze
  #
  #     validate_state_transitions_on :status
  #   end
  #
  #   order = Order.create!(status: :draft)
  #   order.update(status: :submitted)   # => true
  #   order.update(status: :delivered)   # => false, errors[:status] includes transition message
  #
  # For models using a different constant name:
  #   validate_state_transitions_on :phase, transitions_constant: :PHASE_MAP
  #
  # When the previous state has no entry in the transition map (nil allowed list),
  # the validation fails with "unknown previous state". To allow any transition
  # from unknown states instead:
  #   validate_state_transitions_on :status, unknown_state_handler: :allow
  module StateTransitionValidatable
    extend ActiveSupport::Concern
    extend T::Sig

    class_methods do
      extend T::Sig

      # Declares which enum column to validate transitions on and which constant
      # to use as the transition map. Generates a validation method named
      # "#{field}_transition_valid" that matches the AR validation convention.
      #
      # @param field [Symbol] the enum column name (e.g., :status, :lifecycle_state)
      # @param transitions_constant [Symbol] the constant name on the model (default: :VALID_TRANSITIONS)
      # @param unknown_state_handler [Symbol] :error (default, block transition) or :allow (permit any transition)
      sig { params(field: Symbol, transitions_constant: Symbol, unknown_state_handler: Symbol).void }
      def validate_state_transitions_on(field, transitions_constant: :VALID_TRANSITIONS, unknown_state_handler: :error)
        # RATIONALE: define_method — metaprogramming pattern. The block runs in the including model's
        # instance context at runtime, but Sorbet types self as ClassMethods here.
        # Would need ActiveSupport::Concern typed RBI to reconsider.
        T.bind(self, T.class_of(ActiveRecord::Base)).define_method(:"#{field}_transition_valid") do
          send(:validate_field_transition, field, transitions_constant, unknown_state_handler)
        end

        # RATIONALE: validate — AS::Concern class_methods block types self as the
        # ClassMethods module, but at runtime self is the including AR class which has #validate.
        # Would need ActiveSupport::Concern typed RBI to reconsider.
        T.bind(self, T.class_of(ActiveRecord::Base)).validate(:"#{field}_transition_valid")
      end
    end

    private

    sig { params(field: Symbol, transitions_constant: Symbol, unknown_state_handler: Symbol).void }
    def validate_field_transition(field, transitions_constant, unknown_state_handler)
      field_s = field.to_s
      changed_method = :"#{field_s}_changed?"
      was_method = :"#{field_s}_was"

      # RATIONALE: send returns untyped from the concern's perspective; T.cast restores the expected type.
      # Would need typed AR concern RBIs to remove.
      return unless T.cast(send(changed_method), T::Boolean)
      return if T.bind(self, ActiveRecord::Base).new_record?

      # RATIONALE: const_get returns untyped; T.cast to the expected transition map shape.
      # Would need a typed state machine DSL to reconsider.
      transitions = T.cast(self.class.const_get(transitions_constant), T::Hash[String, T::Array[String]])
      # RATIONALE: send returns untyped; T.cast restores the expected String return for enum attribute readers.
      # Would need typed AR concern RBIs to remove.
      previous_value = T.cast(send(was_method), String)
      # RATIONALE: same as above — enum attribute reader returns untyped from concern scope.
      current_value = T.cast(send(field), String)

      allowed = transitions[previous_value]

      if allowed.nil?
        return if unknown_state_handler == :allow

        T.bind(self, ActiveRecord::Base).errors.add(field, "unknown previous state '#{previous_value}'")

        return
      end

      return if allowed.include?(current_value)

      T.bind(self, ActiveRecord::Base).errors.add(field, "cannot transition from #{previous_value} to #{current_value}")
    end
  end
end
