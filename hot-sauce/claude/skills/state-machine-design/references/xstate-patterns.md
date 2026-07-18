# XState Implementation Patterns (TypeScript)

## Basic Machine

```typescript
import { createMachine, assign } from 'xstate';

interface OrderContext {
  items: LineItem[];
  customerId: string;
  paymentId?: string;
  trackingNumber?: string;
}

type OrderEvent =
  | { type: 'ADD_ITEM'; item: LineItem }
  | { type: 'REMOVE_ITEM'; itemId: string }
  | { type: 'SUBMIT' }
  | { type: 'PAY'; paymentId: string }
  | { type: 'CANCEL' }
  | { type: 'SHIP'; trackingNumber: string }
  | { type: 'DELIVER' }
  | { type: 'RETURN' }
  | { type: 'REFUND' };

const orderMachine = createMachine({
  id: 'order',
  initial: 'draft',
  context: {
    items: [],
    customerId: '',
  } as OrderContext,

  states: {
    draft: {
      entry: 'initializeOrder',
      on: {
        ADD_ITEM: {
          actions: assign({
            items: ({ context, event }) => [...context.items, event.item],
          }),
        },
        REMOVE_ITEM: {
          actions: assign({
            items: ({ context, event }) =>
              context.items.filter(i => i.id !== event.itemId),
          }),
        },
        SUBMIT: {
          target: 'submitted',
          guard: 'hasItems',
        },
        CANCEL: 'cancelled',
      },
    },

    submitted: {
      entry: 'reserveInventory',
      exit: 'onSubmittedExit',
      on: {
        PAY: {
          target: 'paid',
          guard: 'paymentValid',
          actions: assign({
            paymentId: ({ event }) => event.paymentId,
          }),
        },
        CANCEL: {
          target: 'cancelled',
          actions: 'releaseInventory',
        },
      },
    },

    paid: {
      entry: 'confirmInventory',
      on: {
        SHIP: {
          target: 'shipped',
          actions: assign({
            trackingNumber: ({ event }) => event.trackingNumber,
          }),
        },
        REFUND: 'refunded',
      },
    },

    shipped: {
      entry: 'sendTrackingNotification',
      on: {
        DELIVER: 'delivered',
        RETURN: 'returned',
      },
    },

    delivered: {
      on: {
        RETURN: 'returned',
      },
      after: {
        // Auto-complete after 14 days
        '14d': 'completed',
      },
    },

    returned: {
      on: {
        REFUND: 'refunded',
      },
    },

    completed: { type: 'final' },
    cancelled: { type: 'final' },
    refunded: { type: 'final' },
  },
}, {
  guards: {
    hasItems: ({ context }) => context.items.length > 0,
    paymentValid: ({ event }) => event.type === 'PAY' && !!event.paymentId,
  },
  actions: {
    initializeOrder: () => console.log('Order initialized'),
    reserveInventory: ({ context }) =>
      console.log(`Reserving ${context.items.length} items`),
    confirmInventory: () => console.log('Inventory confirmed'),
    releaseInventory: () => console.log('Inventory released'),
    sendTrackingNotification: ({ context }) =>
      console.log(`Tracking: ${context.trackingNumber}`),
  },
});
```

## Key XState Patterns

### Guards (Conditional Transitions)

```typescript
on: {
  SUBMIT: {
    target: 'submitted',
    guard: 'hasItems',        // Named guard
  },
  PAY: {
    target: 'paid',
    guard: ({ context }) => context.balance >= context.total,  // Inline guard
  },
}
```

### Entry/Exit Actions

```typescript
states: {
  submitted: {
    entry: 'reserveInventory',     // Runs when entering
    exit: 'releaseInventory',      // Runs when leaving
    on: { /* transitions */ },
  },
}
```

### Context Updates with assign

```typescript
on: {
  ADD_ITEM: {
    actions: assign({
      items: ({ context, event }) => [...context.items, event.item],
    }),
  },
}
```

### Delayed Transitions (after)

```typescript
states: {
  delivered: {
    after: {
      '14d': 'completed',          // Auto-transition after 14 days
      5000: 'timeout',             // After 5 seconds (ms)
    },
  },
}
```

### Composite (Nested) States

```typescript
states: {
  draft: {
    initial: 'empty',
    states: {
      empty: {
        on: { ADD_ITEM: 'hasItems' },
      },
      hasItems: {
        on: {
          ADD_ITEM: 'hasItems',
          REMOVE_LAST: 'empty',
        },
      },
    },
    on: {
      SUBMIT: { target: 'submitted', guard: 'hasItems' },
    },
  },
}
```

### Parallel States

```typescript
states: {
  processing: {
    type: 'parallel',
    states: {
      payment: {
        initial: 'charging',
        states: {
          charging: { on: { CHARGED: 'complete' } },
          complete: { type: 'final' },
        },
      },
      inventory: {
        initial: 'reserving',
        states: {
          reserving: { on: { RESERVED: 'complete' } },
          complete: { type: 'final' },
        },
      },
    },
    onDone: 'fulfilled',  // When ALL parallel regions reach final
  },
}
```
