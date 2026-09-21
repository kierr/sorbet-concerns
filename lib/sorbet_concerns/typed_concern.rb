# typed: strong
# frozen_string_literal: true

require "active_support/concern"

module SorbetConcerns
  # Provides typed access to the including class, eliminating T.bind/T.unsafe
  # boilerplate in ActiveSupport::Concern blocks.
  #
  # ActiveSupport::Concern is not type-safe under Sorbet: inside `included` and
  # `class_methods` blocks, `self` is typed as the concern module (or its
  # ClassMethods submodule), not the including AR class. Every call to AR
  # class methods (validates, enum, belongs_to, define_method) requires
  # T.bind(self, T.class_of(ActiveRecord::Base)) or T.unsafe(self).
  #
  # TypedConcern provides two helpers that centralize this pattern:
  #
  #   - typed_class — returns self cast as T.class_of(ActiveRecord::Base),
  #     available as both a class method and in class_methods blocks
  #   - typed_instance — returns self cast as ActiveRecord::Base,
  #     available as an instance method on the including model
  #
  # These do not eliminate T.cast — Sorbet fundamentally cannot know that
  # `self` inside a concern block is the including class. But they centralize
  # the cast into a single, documented, consistent call site, so:
  #   1. Per-concern RBI shims are unnecessary
  #   2. All T.cast usage is grep-able (typed_class / typed_instance)
  #   3. Implementation can change in one place if Sorbet adds native support
  #
  # Usage — include in your ActiveRecord model:
  #
  #   class Order < ActiveRecord::Base
  #     include SorbetConcerns::TypedConcern
  #
  #     # typed_class is now available as a class method:
  #     typed_class.validates :status, presence: true
  #     typed_class.enum :status, { draft: 0, published: 1 }
  #
  #     def active?
  #       typed_instance.status == "published"
  #     end
  #   end
  #
  # For concern authors: extend ActiveSupport::Concern as usual, and
  # declare that models must include TypedConcern. Then typed_class is
  # available in the concern's included block because it's a class method
  # on the including model:
  #
  #   module MyConcern
  #     extend ActiveSupport::Concern
  #
  #     included do
  #       typed_class.validates :status, presence: true
  #     end
  #
  #     class_methods do
  #       def build_default
  #         new(status: :draft)
  #       end
  #     end
  #   end
  #
  #   class Order < ActiveRecord::Base
  #     include SorbetConcerns::TypedConcern  # must come first
  #     include MyConcern
  #   end
  #
  # Design tradeoff: this is the best possible abstraction given Sorbet's
  # fundamental limitation. A perfect solution (self automatically typed as
  # the including class) would require Sorbet to support generic modules or
  # first-class concern type inference, which it does not. An honest
  # This is the best possible abstraction given the limitation.
  module TypedConcern
    extend ActiveSupport::Concern
    extend T::Sig

    class_methods do
      extend T::Sig

      # Returns self cast as T.class_of(ActiveRecord::Base).
      # Use in `included` blocks and `class_methods` blocks to call AR class
      # methods without per-call T.bind:
      #
      #   included do
      #     typed_class.validates :name, presence: true
      #     typed_class.enum :status, { draft: 0, published: 1 }
      #   end
      sig { returns(T.class_of(ActiveRecord::Base)) }
      def typed_class
        T.cast(self, T.class_of(ActiveRecord::Base))
      end
    end

    # Returns self cast as ActiveRecord::Base.
    # Use in concern instance methods where self's type is narrowed to the
    # concern module instead of the including AR model:
    #
    #   def active?
    #     typed_instance.status == "published"
    #   end
    sig { returns(ActiveRecord::Base) }
    def typed_instance
      T.cast(self, ActiveRecord::Base)
    end
  end
end
