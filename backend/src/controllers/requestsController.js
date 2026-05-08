// =============================================================================
//  src/controllers/requestsController.js
//  Handles RELIEF_REQUESTS table.
//
//  Routes:
//    GET    /api/requests       → getAllRequests
//    POST   /api/requests       → createRequest
//    PUT    /api/requests/:id   → updateRequestStatus
// =============================================================================
const { getConnection } = require('../db/pool');

async function getAllRequests(req, res, next) {
  let conn;
  try {
    conn = await getConnection();
    const result = await conn.execute(`
      SELECT
        rr.request_id, rr.camp_id, rr.item_id,
        rr.quantity_requested, rr.request_date,
        rr.status, rr.priority_level,
        rc.camp_name, sc.item_name
      FROM Relief_Requests rr
      JOIN Relief_Camps    rc ON rr.camp_id = rc.camp_id
      JOIN Supply_Catalog  sc ON rr.item_id = sc.item_id
      ORDER BY rr.request_id DESC
    `);
    res.json({ count: result.rows.length, data: result.rows });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

// POST /api/requests
// priority_level is set by trg_set_priority on the DB — no need to send it
async function createRequest(req, res, next) {
  let conn;
  try {
    const { camp_id, item_id, quantity_requested } = req.body;
    if (!camp_id || !item_id || !quantity_requested) {
      return res.status(400).json({ error: 'camp_id, item_id and quantity_requested are required.' });
    }
    if (quantity_requested < 1) {
      return res.status(400).json({ error: 'CHECK constraint: quantity_requested > 0.' });
    }

    conn = await getConnection();
    await conn.execute(
      `INSERT INTO Relief_Requests
         (request_id, camp_id, item_id, quantity_requested, request_date, status, priority_level)
       VALUES
         (seq_request.NEXTVAL, :camp_id, :item_id, :qty, SYSDATE, 'Pending', 'Low')`,
      // priority_level = 'Low' is a placeholder — trg_set_priority overwrites it immediately
      { camp_id, item_id, qty: quantity_requested }
    );
    await conn.commit();
    res.status(201).json({ message: 'Request inserted. trg_set_priority fired — priority_level auto-set by DB.' });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

// PUT /api/requests/:id   { status: 'Fulfilled' | 'Rejected' }
async function updateRequestStatus(req, res, next) {
  let conn;
  try {
    const { status } = req.body;
    const validStatuses = ['Pending', 'Fulfilled', 'Rejected'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: 'status must be Pending, Fulfilled or Rejected.' });
    }
    conn = await getConnection();
    const result = await conn.execute(
      `UPDATE Relief_Requests SET status = :status WHERE request_id = :id`,
      { status, id: parseInt(req.params.id) }
    );
    if (!result.rowsAffected) return res.status(404).json({ error: 'Request not found.' });
    await conn.commit();
    res.json({ message: `Request ${req.params.id} status set to ${status}.` });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

module.exports = { getAllRequests, createRequest, updateRequestStatus };
