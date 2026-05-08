// =============================================================================
//  src/controllers/shipmentsController.js
//  Handles SHIPMENTS table.
//
//  Routes:
//    GET  /api/shipments       → getAllShipments
//    POST /api/shipments       → createShipment  (calls process_shipment procedure)
//    PUT  /api/shipments/:id   → updateShipmentStatus
// =============================================================================
const { getConnection } = require('../db/pool');

async function getAllShipments(req, res, next) {
  let conn;
  try {
    conn = await getConnection();
    const result = await conn.execute(`
      SELECT
        sh.shipment_id, sh.request_id, sh.warehouse_id,
        sh.dispatch_date, sh.delivery_date,
        sh.shipped_quantity, sh.status,
        w.location AS warehouse_location,
        rc.camp_name
      FROM Shipments sh
      JOIN Warehouses       w  ON sh.warehouse_id = w.warehouse_id
      JOIN Relief_Requests  rr ON sh.request_id   = rr.request_id
      JOIN Relief_Camps     rc ON rr.camp_id       = rc.camp_id
      ORDER BY sh.shipment_id DESC
    `);
    res.json({ count: result.rows.length, data: result.rows });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

// POST /api/shipments
// Calls the process_shipment() stored procedure on Oracle.
// Body: { request_id, warehouse_id, shipped_quantity, delivery_date? }
async function createShipment(req, res, next) {
  let conn;
  try {
    const { request_id, warehouse_id, shipped_quantity, delivery_date } = req.body;
    if (!request_id || !warehouse_id || !shipped_quantity) {
      return res.status(400).json({ error: 'request_id, warehouse_id and shipped_quantity are required.' });
    }
    if (shipped_quantity < 1) {
      return res.status(400).json({ error: 'CHECK constraint: shipped_quantity > 0.' });
    }

    conn = await getConnection();

    // Call the stored procedure — it inserts the row AND marks request Fulfilled
    await conn.execute(
      `BEGIN process_shipment(:req_id, :wh_id, :qty); END;`,
      {
        req_id: request_id,
        wh_id:  warehouse_id,
        qty:    shipped_quantity
      }
    );
    // Note: process_shipment() contains its own COMMIT

    res.status(201).json({
      message: `Shipment created via process_shipment(${request_id}, ${warehouse_id}, ${shipped_quantity}). Request ${request_id} marked Fulfilled.`
    });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

// PUT /api/shipments/:id   { status: 'Delivered' | 'Delayed' }
// When status = 'Delivered', trg_update_inventory_on_delivery fires on DB
// and automatically adds shipped_quantity to Camp_Inventory.
async function updateShipmentStatus(req, res, next) {
  let conn;
  try {
    const { status } = req.body;
    const valid = ['In Transit', 'Delivered', 'Delayed'];
    if (!valid.includes(status)) {
      return res.status(400).json({ error: 'status must be: In Transit, Delivered, or Delayed.' });
    }

    conn = await getConnection();
    const result = await conn.execute(
      `UPDATE Shipments
       SET    status        = :status,
              delivery_date = CASE WHEN :status = 'Delivered' THEN SYSDATE ELSE delivery_date END
       WHERE  shipment_id  = :id`,
      { status, id: parseInt(req.params.id) }
    );
    if (!result.rowsAffected) return res.status(404).json({ error: 'Shipment not found.' });
    await conn.commit();

    res.json({
      message: `Shipment ${req.params.id} status → ${status}.`
        + (status === 'Delivered' ? ' trg_update_inventory_on_delivery fired — Camp_Inventory updated.' : '')
    });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

module.exports = { getAllShipments, createShipment, updateShipmentStatus };
