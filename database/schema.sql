-- =============================================================================
--  RAPID RESPONSE DISASTER RELIEF SYSTEM (RRDRS)
--  Course  : UCS310 - Database Management Systems
--  Group   : Samarth Badola · Shourya Kansal · Pallav Nirola
--  Sub-grp : 2C65  |  Thapar Institute of Engineering & Technology
--  DB      : Oracle 19c
-- =============================================================================
--
--  EXECUTION ORDER (run top to bottom):
--    1. SEQUENCES
--    2. TABLE DDL (parent tables first, then child tables)
--    3. TRIGGERS  (validation → automation → delivery)
--    4. STORED PROCEDURE & FUNCTION
--    5. SAMPLE DATA (INSERT statements)
--    6. DML DEMO  (UPDATE, trigger verification)
--    7. ANALYTICAL QUERIES
--
-- =============================================================================


-- =============================================================================
-- SECTION 1 : SEQUENCES
--   Sequences provide auto-incrementing surrogate PKs for tables that need
--   system-generated IDs (Relief_Requests and Shipments).
--   Camp IDs and item IDs are inserted manually so they are NOT sequenced.
-- =============================================================================

-- Auto-generates request_id for every new row in Relief_Requests
CREATE SEQUENCE seq_request
    START WITH 1
    INCREMENT BY 1;

-- Auto-generates shipment_id for every new row in Shipments
CREATE SEQUENCE seq_shipment
    START WITH 1
    INCREMENT BY 1;


-- =============================================================================
-- SECTION 2 : TABLE DDL
--   Order matters: parent tables (no FKs) must be created before child tables
--   (which reference them).
--
--   Dependency chain:
--     Relief_Camps ──┐
--                    ├──► Camp_Inventory
--     Supply_Catalog ┘
--
--     Relief_Camps ──┐
--                    ├──► Relief_Requests ──► Shipments
--     Supply_Catalog ┘                    │
--                                         ▼
--                                         Warehouses
--
--     Warehouses ────┐
--                    ├──► Warehouse_Inventory
--     Supply_Catalog ┘
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 2.1  Relief_Camps  (PARENT — no foreign keys)
--   Stores one row per physical disaster relief camp.
--   current_population drives the "days of supply left" calculation.
-- -----------------------------------------------------------------------------
CREATE TABLE Relief_Camps (
    camp_id            NUMBER          PRIMARY KEY,
    camp_name          VARCHAR2(100)   NOT NULL,
    district           VARCHAR2(50),
    latitude           NUMBER(9,6),                -- GPS coordinate (optional)
    longitude          NUMBER(9,6),                -- GPS coordinate (optional)
    current_population NUMBER          NOT NULL
                           CHECK (current_population >= 0),
    contact_person     VARCHAR2(100),
    contact_number     VARCHAR2(15)
);


-- -----------------------------------------------------------------------------
-- 2.2  Supply_Catalog  (PARENT — no foreign keys)
--   Master list of all relief item types.
--   per_person_daily_need is the denominator in the days-left formula:
--     days_left = quantity_on_hand / (current_population * per_person_daily_need)
-- -----------------------------------------------------------------------------
CREATE TABLE Supply_Catalog (
    item_id               NUMBER          PRIMARY KEY,
    item_name             VARCHAR2(100)   NOT NULL,
    category              VARCHAR2(50),            -- e.g. 'Essential', 'Food', 'Medical'
    per_person_daily_need NUMBER(10,2)
                              CHECK (per_person_daily_need >= 0)
);


-- -----------------------------------------------------------------------------
-- 2.3  Camp_Inventory  (CHILD — references Relief_Camps + Supply_Catalog)
--   Tracks how much of each supply item is currently held at each camp.
--   Primary key is COMPOSITE (camp_id, item_id) — one row per camp-item pair.
--   last_updated is set automatically by trg_update_timestamp (Section 3.2).
--   ON DELETE CASCADE: removing a camp or item cleans up its inventory rows.
-- -----------------------------------------------------------------------------
CREATE TABLE Camp_Inventory (
    camp_id          NUMBER,
    item_id          NUMBER,
    quantity_on_hand NUMBER   NOT NULL
                         CHECK (quantity_on_hand >= 0),
    last_updated     DATE,

    -- Composite primary key — no separate inventory_id column needed
    CONSTRAINT pk_camp_inventory PRIMARY KEY (camp_id, item_id),

    CONSTRAINT fk_ci_camp FOREIGN KEY (camp_id)
        REFERENCES Relief_Camps(camp_id)  ON DELETE CASCADE,

    CONSTRAINT fk_ci_item FOREIGN KEY (item_id)
        REFERENCES Supply_Catalog(item_id) ON DELETE CASCADE
);


-- -----------------------------------------------------------------------------
-- 2.4  Relief_Requests  (CHILD — references Relief_Camps + Supply_Catalog)
--   Formal supply requests raised by camps.
--   request_id is populated via seq_request.NEXTVAL.
--   priority_level is auto-set by trg_set_priority (Section 3.4).
--   status lifecycle: Pending → Fulfilled | Rejected
--   ON DELETE CASCADE: removing a camp or item removes its requests.
-- -----------------------------------------------------------------------------
CREATE TABLE Relief_Requests (
    request_id         NUMBER          PRIMARY KEY,
    camp_id            NUMBER,
    item_id            NUMBER,
    quantity_requested NUMBER          NOT NULL
                           CHECK (quantity_requested > 0),
    request_date       DATE,
    status             VARCHAR2(20),
    priority_level     VARCHAR2(20),

    CONSTRAINT fk_rr_camp FOREIGN KEY (camp_id)
        REFERENCES Relief_Camps(camp_id)   ON DELETE CASCADE,

    CONSTRAINT fk_rr_item FOREIGN KEY (item_id)
        REFERENCES Supply_Catalog(item_id) ON DELETE CASCADE,

    -- Only valid lifecycle values allowed
    CONSTRAINT chk_rr_status   CHECK (status         IN ('Pending', 'Fulfilled', 'Rejected')),
    CONSTRAINT chk_rr_priority CHECK (priority_level IN ('Low', 'Medium', 'High', 'Critical'))
);


-- -----------------------------------------------------------------------------
-- 2.5  Warehouses  (PARENT — no foreign keys)
--   Dispatch points that hold bulk stock and send shipments to camps.
-- -----------------------------------------------------------------------------
CREATE TABLE Warehouses (
    warehouse_id NUMBER          PRIMARY KEY,
    location     VARCHAR2(100),
    capacity     NUMBER          CHECK (capacity >= 0),
    contact_info VARCHAR2(100)
);


-- -----------------------------------------------------------------------------
-- 2.6  Warehouse_Inventory  (CHILD — references Warehouses + Supply_Catalog)
--   Tracks stock available at each warehouse per item type.
--   Composite PK (warehouse_id, item_id) — mirrors Camp_Inventory pattern.
--   ON DELETE CASCADE: removing a warehouse or item cleans up stock rows.
-- -----------------------------------------------------------------------------
CREATE TABLE Warehouse_Inventory (
    warehouse_id       NUMBER,
    item_id            NUMBER,
    quantity_available NUMBER   NOT NULL
                           CHECK (quantity_available >= 0),

    CONSTRAINT pk_wh_inventory PRIMARY KEY (warehouse_id, item_id),

    CONSTRAINT fk_whi_warehouse FOREIGN KEY (warehouse_id)
        REFERENCES Warehouses(warehouse_id)  ON DELETE CASCADE,

    CONSTRAINT fk_whi_item FOREIGN KEY (item_id)
        REFERENCES Supply_Catalog(item_id)   ON DELETE CASCADE
);


-- -----------------------------------------------------------------------------
-- 2.7  Shipments  (CHILD — references Relief_Requests + Warehouses)
--   Tracks physical dispatch of supplies from a warehouse to a camp.
--   shipment_id is populated via seq_shipment.NEXTVAL.
--   When status is updated to 'Delivered', trg_update_inventory_on_delivery
--   (Section 3.5) auto-increases Camp_Inventory.quantity_on_hand.
--   ON DELETE CASCADE: removing a request or warehouse removes its shipments.
-- -----------------------------------------------------------------------------
CREATE TABLE Shipments (
    shipment_id     NUMBER          PRIMARY KEY,
    request_id      NUMBER,
    warehouse_id    NUMBER,
    dispatch_date   DATE,
    delivery_date   DATE,
    shipped_quantity NUMBER         CHECK (shipped_quantity > 0),
    status          VARCHAR2(20),

    CONSTRAINT fk_ship_request FOREIGN KEY (request_id)
        REFERENCES Relief_Requests(request_id) ON DELETE CASCADE,

    CONSTRAINT fk_ship_warehouse FOREIGN KEY (warehouse_id)
        REFERENCES Warehouses(warehouse_id)    ON DELETE CASCADE,

    -- Only valid status values allowed
    CONSTRAINT chk_ship_status CHECK (status IN ('In Transit', 'Delivered', 'Delayed'))
);


-- =============================================================================
-- SECTION 3 : TRIGGERS
--   Five triggers enforce data integrity and automate business logic.
--   Ordered by firing sequence:
--     3.1 BEFORE INSERT/UPDATE — guard against negative stock
--     3.2 BEFORE UPDATE        — auto-set timestamp
--     3.3 AFTER  UPDATE        — auto-create critical request when stock < 10
--     3.4 BEFORE INSERT        — auto-set priority based on quantity
--     3.5 AFTER  UPDATE        — sync Camp_Inventory when shipment is delivered
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 3.1  trg_no_negative_stock
--   BEFORE INSERT OR UPDATE on Camp_Inventory (FOR EACH ROW)
--   Purpose : Reject any DML that would set quantity_on_hand < 0.
--   Why     : The CHECK constraint handles this too, but this trigger gives a
--             friendlier ORA-20001 application error instead of a generic
--             constraint violation — useful for UI error handling.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_no_negative_stock
BEFORE INSERT OR UPDATE ON Camp_Inventory
FOR EACH ROW
BEGIN
    IF :NEW.quantity_on_hand < 0 THEN
        RAISE_APPLICATION_ERROR(
            -20001,
            'Stock cannot be negative. Camp: ' || :NEW.camp_id ||
            ', Item: ' || :NEW.item_id
        );
    END IF;
END;
/


-- -----------------------------------------------------------------------------
-- 3.2  trg_update_timestamp
--   BEFORE UPDATE on Camp_Inventory (FOR EACH ROW)
--   Purpose : Automatically record the time of every stock change so the
--             application never needs to pass last_updated explicitly.
--   Note    : Fires on every UPDATE; trg_no_negative_stock fires first.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_update_timestamp
BEFORE UPDATE ON Camp_Inventory
FOR EACH ROW
BEGIN
    :NEW.last_updated := SYSDATE;
END;
/


-- -----------------------------------------------------------------------------
-- 3.3  trg_low_stock_alert
--   AFTER UPDATE OF quantity_on_hand ON Camp_Inventory (FOR EACH ROW)
--   WHEN condition : only fires when the new quantity drops below 10
--   Purpose : Core automation — inserts a Critical relief request automatically
--             so coordinators do not need to monitor stock manually.
--   Chain   : The INSERT here fires trg_set_priority (Section 3.4) on the
--             newly created Relief_Requests row.
--   Threshold: 10 units is the minimum viable stock level. Adjust as needed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_low_stock_alert
AFTER UPDATE OF quantity_on_hand
ON Camp_Inventory
FOR EACH ROW
WHEN (NEW.quantity_on_hand < 10)
BEGIN
    INSERT INTO Relief_Requests (
        request_id,
        camp_id,
        item_id,
        quantity_requested,
        request_date,
        status,
        priority_level
    )
    VALUES (
        seq_request.NEXTVAL, -- auto-generated PK
        :NEW.camp_id,
        :NEW.item_id,
        50,                  -- default emergency quantity; adjust per item
        SYSDATE,
        'Pending',
        'Critical'           -- trg_set_priority may override this below
    );
END;
/


-- -----------------------------------------------------------------------------
-- 3.4  trg_set_priority
--   BEFORE INSERT on Relief_Requests (FOR EACH ROW)
--   Purpose : Enforces consistent priority assignment based on quantity bands,
--             overriding whatever priority_level value was supplied by the
--             calling code (including the auto-insert from trg_low_stock_alert).
--   Bands   :
--     quantity > 100  → Critical
--     quantity >  50  → High
--     quantity >  20  → Medium
--     otherwise       → Low
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_set_priority
BEFORE INSERT ON Relief_Requests
FOR EACH ROW
BEGIN
    IF    :NEW.quantity_requested > 100 THEN
        :NEW.priority_level := 'Critical';
    ELSIF :NEW.quantity_requested > 50  THEN
        :NEW.priority_level := 'High';
    ELSIF :NEW.quantity_requested > 20  THEN
        :NEW.priority_level := 'Medium';
    ELSE
        :NEW.priority_level := 'Low';
    END IF;
END;
/


-- -----------------------------------------------------------------------------
-- 3.5  trg_update_inventory_on_delivery
--   AFTER UPDATE OF status ON Shipments (FOR EACH ROW)
--   WHEN condition : only fires when status changes to 'Delivered'
--   Purpose : Atomically syncs Camp_Inventory when a shipment arrives, so no
--             coordinator needs to manually update stock upon delivery.
--   How     : Uses two scalar subqueries on Relief_Requests to look up
--             camp_id and item_id from the linked request.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_update_inventory_on_delivery
AFTER UPDATE OF status ON Shipments
FOR EACH ROW
WHEN (NEW.status = 'Delivered')
BEGIN
    UPDATE Camp_Inventory
    SET    quantity_on_hand = quantity_on_hand + :NEW.shipped_quantity
    WHERE  camp_id = (
               SELECT camp_id
               FROM   Relief_Requests
               WHERE  request_id = :NEW.request_id
           )
    AND    item_id = (
               SELECT item_id
               FROM   Relief_Requests
               WHERE  request_id = :NEW.request_id
           );
END;
/


-- =============================================================================
-- SECTION 4 : STORED PROCEDURE & FUNCTION
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 4.1  process_shipment  (PROCEDURE)
--   Purpose : Encapsulates the full shipment dispatch workflow in one
--             atomic call — insert the shipment row and mark the linked
--             request as Fulfilled, then COMMIT both together.
--   Why use a procedure?
--     If the INSERT succeeds but the UPDATE fails, COMMIT is never reached,
--     so Oracle rolls back automatically — ensuring atomicity (Section 12
--     of the synopsis).
--   Parameters:
--     p_request_id   — FK to Relief_Requests
--     p_warehouse_id — FK to Warehouses
--     p_quantity     — shipped_quantity value
-- -----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE process_shipment (
    p_request_id   NUMBER,
    p_warehouse_id NUMBER,
    p_quantity     NUMBER
)
IS
BEGIN
    -- Step 1: Create the shipment record (status starts as 'In Transit')
    INSERT INTO Shipments (
        shipment_id,
        request_id,
        warehouse_id,
        dispatch_date,
        delivery_date,
        shipped_quantity,
        status
    )
    VALUES (
        seq_shipment.NEXTVAL,
        p_request_id,
        p_warehouse_id,
        SYSDATE,
        NULL,               -- delivery_date unknown at dispatch time
        p_quantity,
        'In Transit'
    );

    -- Step 2: Mark the originating request as fulfilled
    UPDATE Relief_Requests
    SET    status = 'Fulfilled'
    WHERE  request_id = p_request_id;

    -- Step 3: Commit both DML statements together (atomicity)
    COMMIT;
END;
/


-- -----------------------------------------------------------------------------
-- 4.2  get_days_left  (FUNCTION → returns NUMBER)
--   Purpose : Calculates how many days of supply remain for a specific
--             (camp, item) pair using the formula:
--               days_left = quantity_on_hand
--                           / (current_population * per_person_daily_need)
--   Returns : ROUND(days_left, 2) — two decimal places
--   Usage   : Can be called inline in SELECT statements.
--   Example : SELECT get_days_left(1, 101) FROM dual;
--             → returns 0.13 for Water at Camp Roorkee B (1280 / 3200*3)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_days_left (
    p_camp_id NUMBER,
    p_item_id NUMBER
)
RETURN NUMBER
IS
    v_days NUMBER;
BEGIN
    SELECT
        ci.quantity_on_hand
        / (rc.current_population * sc.per_person_daily_need)
    INTO   v_days
    FROM   Camp_Inventory ci
    JOIN   Relief_Camps   rc ON ci.camp_id = rc.camp_id
    JOIN   Supply_Catalog sc ON ci.item_id = sc.item_id
    WHERE  ci.camp_id = p_camp_id
    AND    ci.item_id = p_item_id;

    RETURN ROUND(v_days, 2);
END;
/


-- =============================================================================
-- SECTION 5 : SAMPLE DATA (INSERT)
--   Inserts enough rows to demonstrate all triggers and queries.
--   Insertion order: parents before children.
-- =============================================================================

-- ── 5.1  Relief_Camps ────────────────────────────────────────────────────────
INSERT INTO Relief_Camps VALUES (1, 'Camp Roorkee B',  'Roorkee',  29.8543, 77.8880, 3200, 'Ravi Sharma',  '+91 98100 00001');
INSERT INTO Relief_Camps VALUES (2, 'Camp Haridwar A', 'Haridwar', 29.9457, 78.1642, 4100, 'Priya Singh',  '+91 98100 00002');
INSERT INTO Relief_Camps VALUES (3, 'Camp Dehradun C', 'Dehradun', 30.3165, 78.0322, 2950, 'Anil Mehta',   '+91 98100 00003');
INSERT INTO Relief_Camps VALUES (4, 'Camp Rishikesh D','Rishikesh',30.0869, 78.2676, 2200, 'Sunita Rawat', '+91 98100 00004');

-- ── 5.2  Supply_Catalog ──────────────────────────────────────────────────────
-- per_person_daily_need drives the days-left formula (see get_days_left)
INSERT INTO Supply_Catalog VALUES (101, 'Water',     'Essential', 3);     -- 3 L/person/day
INSERT INTO Supply_Catalog VALUES (102, 'Rice',      'Food',      0.5);   -- 0.5 kg/person/day
INSERT INTO Supply_Catalog VALUES (103, 'Medicine',  'Medical',   0.1);   -- 0.1 strips/person/day
INSERT INTO Supply_Catalog VALUES (104, 'Insulin',   'Medical',   0.01);  -- 0.01 units/person/day
INSERT INTO Supply_Catalog VALUES (105, 'Blankets',  'Shelter',   0.003); -- one-time use; very low daily rate

-- ── 5.3  Camp_Inventory ──────────────────────────────────────────────────────
-- Note: trg_update_timestamp fires on UPDATE, not INSERT, so last_updated
--       is set explicitly here with SYSDATE.
INSERT INTO Camp_Inventory VALUES (1, 101,  1280, SYSDATE);  -- Roorkee B  / Water   → 0.13 days
INSERT INTO Camp_Inventory VALUES (2, 104,     8, SYSDATE);  -- Haridwar A / Insulin → <1 day (triggers alert)
INSERT INTO Camp_Inventory VALUES (3, 102,  4200, SYSDATE);  -- Dehradun C / Rice    → 2.8 days
INSERT INTO Camp_Inventory VALUES (4, 101, 22000, SYSDATE);  -- Rishikesh D/ Water   → 10 days
INSERT INTO Camp_Inventory VALUES (4, 102,  8800, SYSDATE);  -- Rishikesh D/ Rice    → 8 days

-- ── 5.4  Warehouses ──────────────────────────────────────────────────────────
INSERT INTO Warehouses VALUES (1, 'Dehradun Central Warehouse', 200000, '9876543201');
INSERT INTO Warehouses VALUES (2, 'Haridwar Depot',             150000, '9876543202');
INSERT INTO Warehouses VALUES (3, 'Roorkee Distribution Hub',   100000, '9876543203');

-- ── 5.5  Warehouse_Inventory ─────────────────────────────────────────────────
INSERT INTO Warehouse_Inventory VALUES (1, 101,  80000);  -- Dehradun / Water
INSERT INTO Warehouse_Inventory VALUES (1, 102,  40000);  -- Dehradun / Rice
INSERT INTO Warehouse_Inventory VALUES (2, 104,   1200);  -- Haridwar / Insulin
INSERT INTO Warehouse_Inventory VALUES (3, 101,  12000);  -- Roorkee  / Water
INSERT INTO Warehouse_Inventory VALUES (3, 105,    800);  -- Roorkee  / Blankets

-- ── 5.6  Relief_Requests (manual pre-seed — bypassing seq for demo IDs) ──────
-- In production, always use seq_request.NEXTVAL.
-- request_id = 1: auto-created by trg_low_stock_alert when Insulin < 10 (demo below)
-- Pre-seeding additional requests for shipment testing:
INSERT INTO Relief_Requests VALUES (seq_request.NEXTVAL, 1, 101, 50000, SYSDATE, 'Pending',   'Critical'); -- Water for Roorkee B
INSERT INTO Relief_Requests VALUES (seq_request.NEXTVAL, 2, 104,   200, SYSDATE, 'Pending',   'Critical'); -- Insulin for Haridwar A
INSERT INTO Relief_Requests VALUES (seq_request.NEXTVAL, 3, 102, 10000, SYSDATE, 'Pending',   'High');     -- Rice for Dehradun C
INSERT INTO Relief_Requests VALUES (seq_request.NEXTVAL, 4, 105,   500, SYSDATE, 'Fulfilled', 'Low');      -- Blankets for Rishikesh D (already done)

-- ── 5.7  Shipments ───────────────────────────────────────────────────────────
-- Use process_shipment() in production; direct inserts here for demo clarity.
INSERT INTO Shipments VALUES (seq_shipment.NEXTVAL, 1, 3, SYSDATE, NULL,                SYSDATE, 50000, 'In Transit'); -- Water to Roorkee B from Roorkee Hub
INSERT INTO Shipments VALUES (seq_shipment.NEXTVAL, 2, 1, SYSDATE, NULL,                SYSDATE,   200, 'In Transit'); -- Insulin to Haridwar A from Dehradun
INSERT INTO Shipments VALUES (seq_shipment.NEXTVAL, 4, 2, SYSDATE, SYSDATE - 1,                   500, 'Delivered');  -- Blankets delivered (triggers inventory update)


-- =============================================================================
-- SECTION 6 : DML DEMO — TRIGGER VERIFICATION
--   Shows how the triggers fire during normal operations.
-- =============================================================================

-- ── 6.1  Demonstrate trg_low_stock_alert ─────────────────────────────────────
-- Dropping Roorkee B Water stock below 10 → trigger auto-inserts a Critical request
UPDATE Camp_Inventory
SET    quantity_on_hand = 5        -- below threshold of 10
WHERE  camp_id = 1
AND    item_id = 101;
-- Expected: trg_update_timestamp sets last_updated = SYSDATE
--           trg_low_stock_alert fires → new row in Relief_Requests (Critical, qty=50)

-- Verify the auto-created request:
SELECT * FROM Relief_Requests ORDER BY request_id DESC;

-- ── 6.2  Demonstrate trg_update_inventory_on_delivery ────────────────────────
-- Mark shipment 1 as Delivered → trigger adds shipped_quantity to Camp_Inventory
UPDATE Shipments
SET    status        = 'Delivered',
       delivery_date = SYSDATE
WHERE  shipment_id  = 1;
-- Expected: Camp_Inventory row (camp_id=1, item_id=101) increases by 50,000

-- Verify stock was updated:
SELECT * FROM Camp_Inventory WHERE camp_id = 1 AND item_id = 101;

-- ── 6.3  Demonstrate process_shipment() procedure ────────────────────────────
-- Dispatch a new shipment for the Insulin request (request_id=2)
BEGIN
    process_shipment(
        p_request_id   => 2,   -- FK → Relief_Requests
        p_warehouse_id => 1,   -- FK → Warehouses (Dehradun Central)
        p_quantity     => 200  -- ships 200 units of Insulin
    );
END;
/


-- =============================================================================
-- SECTION 7 : ANALYTICAL QUERIES
--   All queries from the project synopsis (Sections 11 & 12), ordered from
--   simple to complex.
-- =============================================================================

-- ── 7.1  Critical shortage report (3-table JOIN) ─────────────────────────────
-- Shows every (camp, item) pair where supply will run out in less than 3 days.
-- Uses the same formula as get_days_left(). Ordered most urgent first.
SELECT
    rc.camp_name,
    rc.district,
    sc.item_name,
    ci.quantity_on_hand,
    ROUND(
        ci.quantity_on_hand / (rc.current_population * sc.per_person_daily_need),
        2
    ) AS days_left,
    rc.current_population
FROM  Camp_Inventory ci
JOIN  Relief_Camps   rc ON ci.camp_id = rc.camp_id
JOIN  Supply_Catalog sc ON ci.item_id = sc.item_id
WHERE (ci.quantity_on_hand / (rc.current_population * sc.per_person_daily_need)) < 3
ORDER BY days_left ASC;


-- ── 7.2  Full request view (JOIN across 3 tables) ────────────────────────────
-- Displays human-readable request details instead of raw FK numbers.
SELECT
    rc.camp_name,
    rc.district,
    sc.item_name,
    rr.quantity_requested,
    rr.priority_level,
    rr.status,
    rr.request_date
FROM  Relief_Requests rr
JOIN  Relief_Camps    rc ON rr.camp_id = rc.camp_id
JOIN  Supply_Catalog  sc ON rr.item_id = sc.item_id
ORDER BY rr.priority_level DESC, rr.request_date ASC;


-- ── 7.3  Total demand per item (GROUP BY aggregation) ────────────────────────
-- Useful for procurement planning: shows which items are most demanded.
SELECT
    sc.item_name,
    SUM(rr.quantity_requested) AS total_demand
FROM  Relief_Requests rr
JOIN  Supply_Catalog  sc ON rr.item_id = sc.item_id
GROUP BY sc.item_name
ORDER BY total_demand DESC;


-- ── 7.4  Items critically low (quantity_on_hand < 10) ────────────────────────
-- Direct filter on Camp_Inventory — these rows would have triggered alerts.
SELECT
    ci.camp_id,
    rc.camp_name,
    sc.item_name,
    ci.quantity_on_hand,
    ci.last_updated
FROM  Camp_Inventory ci
JOIN  Relief_Camps   rc ON ci.camp_id = rc.camp_id
JOIN  Supply_Catalog sc ON ci.item_id = sc.item_id
WHERE ci.quantity_on_hand < 10;


-- ── 7.5  Days-of-supply for all (camp, item) pairs ───────────────────────────
-- Uses the stored function get_days_left() for clean, reusable calculation.
SELECT
    ci.camp_id,
    rc.camp_name,
    ci.item_id,
    sc.item_name,
    get_days_left(ci.camp_id, ci.item_id) AS days_left
FROM  Camp_Inventory ci
JOIN  Relief_Camps   rc ON ci.camp_id = rc.camp_id
JOIN  Supply_Catalog sc ON ci.item_id = sc.item_id
ORDER BY days_left ASC;


-- ── 7.6  Shipment tracking — full traceability ───────────────────────────────
-- Shows the complete supply chain path: request → warehouse → camp.
SELECT
    sh.shipment_id,
    sh.status                          AS shipment_status,
    rc.camp_name                       AS destination_camp,
    sc.item_name,
    sh.shipped_quantity,
    w.location                         AS dispatched_from,
    sh.dispatch_date,
    sh.delivery_date,
    rr.priority_level                  AS request_priority
FROM  Shipments      sh
JOIN  Relief_Requests rr ON sh.request_id    = rr.request_id
JOIN  Warehouses      w  ON sh.warehouse_id  = w.warehouse_id
JOIN  Relief_Camps    rc ON rr.camp_id       = rc.camp_id
JOIN  Supply_Catalog  sc ON rr.item_id       = sc.item_id
ORDER BY sh.dispatch_date DESC;


-- ── 7.7  Quick function call (single value lookup) ───────────────────────────
-- How many days of Water remain at Camp Roorkee B (camp_id=1, item_id=101)?
SELECT get_days_left(1, 101) AS water_days_left FROM dual;