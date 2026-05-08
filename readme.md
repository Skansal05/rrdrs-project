```mermaid
erDiagram
    RELIEF_CAMPS ||--o{ CAMP_INVENTORY : "has stock in"
    SUPPLY_CATALOG ||--o{ CAMP_INVENTORY : "is tracked as"
    
    RELIEF_CAMPS ||--o{ RELIEF_REQUESTS : "raises"
    SUPPLY_CATALOG ||--o{ RELIEF_REQUESTS : "is requested via"
    
    WAREHOUSES ||--o{ WAREHOUSE_INVENTORY : "stores"
    SUPPLY_CATALOG ||--o{ WAREHOUSE_INVENTORY : "is stored as"
    
    WAREHOUSES ||--o{ SHIPMENTS : "dispatches"
    RELIEF_REQUESTS ||--o{ SHIPMENTS : "is fulfilled by"

    RELIEF_CAMPS {
        NUMBER camp_id PK
        VARCHAR2 camp_name
        VARCHAR2 district
        NUMBER latitude
        NUMBER longitude
        NUMBER current_population
        VARCHAR2 contact_person
        VARCHAR2 contact_number
    }

    SUPPLY_CATALOG {
        NUMBER item_id PK
        VARCHAR2 item_name
        VARCHAR2 category
        NUMBER per_person_daily_need
    }

    CAMP_INVENTORY {
        NUMBER camp_id PK,FK
        NUMBER item_id PK,FK
        NUMBER quantity_on_hand
        DATE last_updated
    }

    RELIEF_REQUESTS {
        NUMBER request_id PK
        NUMBER camp_id FK
        NUMBER item_id FK
        NUMBER quantity_requested
        DATE request_date
        VARCHAR2 status
        VARCHAR2 priority_level
    }

    WAREHOUSES {
        NUMBER warehouse_id PK
        VARCHAR2 location
        NUMBER capacity
        VARCHAR2 contact_info
    }

    WAREHOUSE_INVENTORY {
        NUMBER warehouse_id PK,FK
        NUMBER item_id PK,FK
        NUMBER quantity_available
    }

    SHIPMENTS {
        NUMBER shipment_id PK
        NUMBER request_id FK
        NUMBER warehouse_id FK
        DATE dispatch_date
        DATE delivery_date
        NUMBER shipped_quantity
        VARCHAR2 status
    }
