# State Machine Notation Examples

## PlantUML

### Full Example — Order Lifecycle

```plantuml
@startuml
title Order State Machine

[*] --> Draft : Create

state Draft {
  Draft : entry / initializeOrder
  Draft : exit / validateOrder
}

Draft --> Submitted : Submit [hasItems]
Draft --> Cancelled : Cancel

state Submitted {
  Submitted : entry / reserveInventory
}

Submitted --> Paid : ProcessPayment [paymentValid]
Submitted --> Cancelled : Cancel / releaseInventory
Submitted --> Draft : RequireChanges

state Paid {
  Paid : entry / confirmInventory
}

Paid --> Shipped : Ship
Paid --> Refunded : Refund

state Shipped {
  Shipped : entry / sendTrackingNotification
}

Shipped --> Delivered : Deliver
Shipped --> Returned : Return

Delivered --> Completed : Finalize
Delivered --> Returned : Return

Returned --> Refunded : ProcessReturn

Completed --> [*]
Refunded --> [*]
Cancelled --> [*]

@enduml
```

### Composite State

```plantuml
@startuml
state Draft {
  [*] --> Empty
  Empty --> HasItems : AddItem
  HasItems --> HasItems : AddItem
  HasItems --> Empty : RemoveLastItem
}
@enduml
```

### Parallel States

```plantuml
@startuml
state Processing {
  state "Payment" as pay {
    [*] --> Charging
    Charging --> Charged
  }
  --
  state "Inventory" as inv {
    [*] --> Reserving
    Reserving --> Reserved
  }
}
@enduml
```

## Mermaid

### Full Example — Order Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Draft : Create

    state Draft {
        direction LR
        [*] --> Empty
        Empty --> HasItems : AddItem
        HasItems --> HasItems : AddItem
        HasItems --> Empty : RemoveLastItem
    }

    Draft --> Submitted : Submit
    Draft --> Cancelled : Cancel

    Submitted --> Paid : PaymentReceived
    Submitted --> Cancelled : Cancel
    Submitted --> Draft : RequireChanges

    Paid --> Shipped : Ship
    Paid --> Refunded : Refund

    Shipped --> Delivered : Deliver
    Shipped --> Returned : Return

    Delivered --> Completed : Finalize
    Delivered --> Returned : Return

    Returned --> Refunded : ProcessReturn

    Completed --> [*]
    Refunded --> [*]
    Cancelled --> [*]
```

### Choice (Decision) Points

```mermaid
stateDiagram-v2
    state check_payment <<choice>>
    Submitted --> check_payment : Pay
    check_payment --> Paid : [paymentValid]
    check_payment --> PaymentFailed : [else]
```
