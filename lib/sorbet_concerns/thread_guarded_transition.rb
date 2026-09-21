# typed: strong
# frozen_string_literal: true

require 'active_support/concern'

module SorbetConcerns
  # Thread-local transition guard for fields that must only be changed
  # through authorized service objects.
  #
  # Prevents accidental direct mutation of guarded fields by installing a
  # before_update callback that blocks changes unless explicitly allowed.
  # Authorization is thread-local, so it is safe across concurrent requests
  # and scoped to the current transaction.
  #
  # Usage:
  #   class Order < ActiveRecord::Base
  #     include SorbetConcerns::ThreadGuardedTransition
  #
  #     guard_transition_on :status
  #   end
  #
  #   # Direct mutation is blocked:
  #   order.update(status: :shipped)  # => false, errors[:status]
  #
  #   # Authorized mutation via class method:
  #   Order.allow_transition_on!(:status) do
  #     order.update!(status: :shipped)
  #   end
  #
  #   # Or via instance method:
  #   order.with_transition_allowed(:status) do
  #     order.update!(status: :shipped)
  #   end
  #
  # Nested calls are safe — the outer block's authorization is preserved:
  #   Order.allow_transition_on!(:status) do
  #     Order.allow_transition_on!(:status) do  # nested
  #       order.update!(status: :shipped)
  #     end
  #     # still authorized here — inner ensure restores outer value (true)
  #   end
  #
  # RATIONALE: Extracted from thread-local transition guard patterns used to
  # ensure state changes go through service objects rather than direct AR updates.
  # The thread-local key per-instance approach avoids global locks and is
  # scoped to the request/transaction. Would need a different
  # authorization model (e.g., database-level locking, actor-based) to reconsider.
  module ThreadGuardedTransition
    extend ActiveSupport::Concern
    extend T::Sig

    class_methods do
      extend T::Sig

      # Allows the given field to be transitioned within the block, bypassing
      # the guard callback. Thread-local, save/restore for nesting safety.
      sig { params(field: Symbol, _block: T.proc.void).void }
      def allow_transition_on!(field, &_block)
        key = thread_key(field)
        # Save and restore the prior value so a nested block does not reset the
        # flag to nil while the outer block is still executing (without this,
        # the inner ensure would block the outer save).
        prior = Thread.current[key]
        Thread.current[key] = true
        yield
      ensure
        Thread.current[key] = prior
      end

      # Returns whether transitions are currently allowed for the given field
      # on the current thread.
      sig { params(field: Symbol).returns(T::Boolean) }
      def transition_allowed_on?(field)
        # RATIONALE: Thread.current returns untyped; T.cast restores expected type.
        # Would need typed Thread.current RBI to remove.
        T.cast(Thread.current[thread_key(field)], T.nilable(T::Boolean)) == true
      end

      # Constructs the thread-local key for a given field. Uses the class name
      # to avoid collisions between different models with the same field name.
      sig { params(field: Symbol).returns(Symbol) }
      def thread_key(field)
        :"sorbet_concerns_transition_#{name}_#{field}"
      end

      # Installs a before_update callback that blocks direct changes to the
      # given field unless authorized via allow_transition_on!.
      sig { params(field: Symbol, error_message: String).void }
      def guard_transition_on(field, error_message: 'must be changed through an authorized service')
        # RATIONALE: define_method — metaprogramming in AS::Concern class_methods block.
        # Would need AS::Concern typed RBI to reconsider.
        T.bind(self, T.class_of(ActiveRecord::Base)).define_method(:"guard_#{field}_transition") do
          guard_field_transition(field, error_message)
        end

        T.bind(self, T.class_of(ActiveRecord::Base)).before_update(:"guard_#{field}_transition")
      end
    end

    # Instance method: allows transition within the block, scoped to this
    # specific instance (uses object_id in the thread key).
    sig { params(field: Symbol, _block: T.proc.void).void }
    def with_transition_allowed(field, &_block)
      key = instance_thread_key(field)
      prior = Thread.current[key]
      Thread.current[key] = true
      yield
    ensure
      Thread.current[key] = prior
    end

    # Returns whether transitions are currently allowed for this specific
    # instance and field on the current thread.
    sig { params(field: Symbol).returns(T::Boolean) }
    def transition_allowed?(field)
      # RATIONALE: Thread.current returns untyped; T.cast restores expected type.
      # Would need typed Thread.current RBI to remove.
      T.cast(Thread.current[instance_thread_key(field)], T.nilable(T::Boolean)) == true
    end

    private

    sig { params(field: Symbol, error_message: String).void }
    def guard_field_transition(field, error_message)
      return unless attribute_changed?(field.to_s)

      # Check instance-level guard first, then class-level.
      return if transition_allowed?(field)
      return if self.class.transition_allowed_on?(field)

      errors.add(field, error_message)
      Kernel.throw(:abort)
    end

    sig { params(field: Symbol).returns(Symbol) }
    def instance_thread_key(field)
      :"sorbet_concerns_transition_#{object_id}_#{field}"
    end
  end
end
