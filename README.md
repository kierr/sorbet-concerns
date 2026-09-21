# sorbet-concerns

Typed `ActiveSupport::Concern` building blocks for Sorbet + Rails. Every file is `typed: strong`.

## The Problem

`ActiveSupport::Concern` is Sorbet-hostile. Inside `included` and `class_methods` blocks, `self` is typed as the concern module (or its `ClassMethods` submodule), not the including ActiveRecord class. Every call to AR class methods — `validates`, `enum`, `belongs_to`, `define_method` — requires `T.bind(self, T.class_of(ActiveRecord::Base))` or `T.unsafe(self)`.

The standard workaround is hand-written RBI shims declaring stub methods on each concern module. A single codebase can accumulate hundreds of lines of these shims, which drift out of sync and provide no runtime safety.

## What This Gem Provides

Four modules that eliminate the boilerplate:

### TypedConcern

Adds `typed_class` and `typed_instance` helpers to your ActiveRecord models. These are `T.cast` wrappers that centralize the pattern in a single, documented, consistent call site.

```ruby
class Order < ActiveRecord::Base
  include SorbetConcerns::TypedConcern

  # typed_class replaces T.bind(self, T.class_of(ActiveRecord::Base))
  typed_class.validates :status, presence: true
  typed_class.enum :status, { draft: 0, published: 1 }

  def active?
    # typed_instance replaces T.cast(self, ActiveRecord::Base)
    typed_instance.status == "published"
  end
end
```

For concern authors — your concern's `included` block can use `typed_class` as long as the model includes `TypedConcern`:

```ruby
module Auditable
  extend ActiveSupport::Concern

  included do
    typed_class.belongs_to :audit_log, optional: true
  end
end

class Order < ActiveRecord::Base
  include SorbetConcerns::TypedConcern
  include Auditable
end
```

**Design note:** `typed_class` and `typed_instance` do not eliminate `T.cast` — Sorbet fundamentally cannot infer that `self` inside a concern block is the including class. A perfect solution would require Sorbet to support generic modules or first-class concern type inference, which it does not. These helpers centralize the cast so it is documented, consistent, and grep-able, and so that per-concern RBI shims become unnecessary.

### StateTransitionValidatable

Validates that state transitions follow a declared transition map.

```ruby
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

order = Order.create!(status: :draft)
order.update(status: :submitted)   # => true
order.update(status: :delivered)   # => false, errors[:status]
```

Options:
- `transitions_constant: :PHASE_MAP` — use a different constant name (default: `:VALID_TRANSITIONS`)
- `unknown_state_handler: :allow` — permit any transition from an unknown previous state (default: `:error`, which blocks)

### ImmutableFields

Validates that specified fields cannot change after creation (`immutable_fields`) or can only be set once (`write_once_fields`).

```ruby
class Document < ActiveRecord::Base
  include SorbetConcerns::ImmutableFields

  immutable_fields :entity_id, :country_id, :kind
  write_once_fields :source_id, :source_record_id
end

doc = Document.create!(entity_id: 1, country_id: "US", source_id: 42)
doc.update(entity_id: 2)     # => false, errors[:entity_id]
doc.update(source_id: 99)    # => false, errors[:source_id] — already set
```

- **immutable_fields**: blocks any change after creation. A nil immutable field can still be set on a persisted record (nil → value is allowed) because the field was not previously assigned a meaningful value.
- **write_once_fields**: allows nil → value once, blocks value → different_value

### ThreadGuardedTransition

Thread-local transition guard for fields that must only be changed through authorized service objects. Whereas `StateTransitionValidatable` controls *which* transitions are legal, `ThreadGuardedTransition` controls *who* can make them. Use both together when state machines must only be mutated through service objects.

```ruby
class Order < ActiveRecord::Base
  include SorbetConcerns::ThreadGuardedTransition

  guard_transition_on :status
end

# Direct mutation is blocked:
order.update(status: :shipped)  # => false, errors[:status]

# Authorized mutation:
Order.allow_transition_on!(:status) do
  order.update!(status: :shipped)
end

# Instance-scoped authorization:
order.with_transition_allowed(:status) do
  order.update!(status: :shipped)
end
```

Predicate methods are available for conditional logic or debugging:

```ruby
Order.transition_allowed_on?(:status)   # class-level — true inside allow_transition_on! block
order.transition_allowed?(:status)              # instance-level — true inside with_transition_allowed block
```

Nested calls are safe — the outer block's authorization is preserved:

```ruby
Order.allow_transition_on!(:status) do
  Order.allow_transition_on!(:status) do  # nested
    order.update!(status: :shipped)
  end
  # still authorized — inner ensure restores outer value
end
```

## Composing Concerns

The modules are designed to work together. A model that needs typed access, state validation, and transition authorization simply includes what it needs:

```ruby
class Order < ActiveRecord::Base
  include SorbetConcerns::TypedConcern
  include SorbetConcerns::StateTransitionValidatable
  include SorbetConcerns::ThreadGuardedTransition

  VALID_TRANSITIONS = {
    "draft" => %w[submitted cancelled],
    "submitted" => %w[approved cancelled],
    "approved" => %w[shipped],
    "shipped" => %w[delivered],
    "cancelled" => %w[],
    "delivered" => %w[]
  }.freeze

  # TypedConcern gives us typed_class for Sorbet-safe class method calls
  typed_class.validates :status, presence: true
  typed_class.enum :status, VALID_TRANSITIONS.keys.index_with(&:itself)

  # StateTransitionValidatable enforces which transitions are legal
  validate_state_transitions_on :status

  # ThreadGuardedTransition enforces that only authorized code can change status
  guard_transition_on :status
end
```

Now `Order` has both transition validation (draft→approved is illegal) and transition authorization (direct `update(status:)` is blocked without `allow_transition_on!`).

## Installation

Add to your Gemfile:

```ruby
gem "sorbet-concerns", github: "kierr/sorbet-concerns"
```

Or via path for development:

```ruby
gem "sorbet-concerns", path: "~/git/github.com/kierr/sorbet-concerns"
```

## Requirements

- Ruby >= 3.2
- Rails >= 7.0 (ActiveRecord and ActiveSupport)
- Sorbet (sorbet-runtime)

## Development

```
bundle install
bundle exec rake spec
```

Tests run against an in-memory SQLite database — no external setup required.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT
