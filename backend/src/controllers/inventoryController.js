// =============================================================================
//  src/controllers/inventoryController.js
//  Handles CAMP_INVENTORY — composite PK (camp_id, item_id)
//
//  Routes:
//    GET /api/inventory                   → getAllInventory
//    GET /api/inventory/:campId/:itemId   → getInventoryRow
//    PUT /api/inventory/:campId/:itemId   → updateStock
// =============================================================================
const { getConnection } = require('../db/pool');

// ---------------------------------------------------------------------------
// GET /api/inventory
// Returns all inventory rows with item name and days_left (via get_days_left).
// ---------------------------------------------------------------------------
async function getAllInventory(req, res, next) {
  let conn;
  try {
    conn = await getConnection();
    const result = await conn.execute(`
      SELECT
        ci.camp_id,
        ci.item_id,
        sc.item_name,
        sc.category,
        ci.quantity_on_hand,
        ci.last_updated,
        get_days_left(ci.camp_id, ci.item_id) AS days_left
      FROM Camp_Inventory ci
      JOIN Supply_Catalog sc ON ci.item_id = sc.item_id
      ORDER BY days_left ASC
    `);
    res.json({ count: result.rows.length, data: result.rows });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

// ---------------------------------------------------------------------------
// GET /api/inventory/:campId/:itemId
// ---------------------------------------------------------------------------
async function getInventoryRow(req, res, next) {
  let conn;
  try {
    conn = await getConnection();
    const result = await conn.execute(`
      SELECT ci.*, sc.item_name, get_days_left(ci.camp_id, ci.item_id) AS days_left
      FROM Camp_Inventory ci
      JOIN Supply_Catalog sc ON ci.item_id = sc.item_id
      WHERE ci.camp_id = :cid AND ci.item_id = :iid`,
      { cid: parseInt(req.params.campId), iid: parseInt(req.params.itemId) }
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Row not found.' });
    res.json({ data: result.rows[0] });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

// ---------------------------------------------------------------------------
// PUT /api/inventory/:campId/:itemId
// Body: { quantity_on_hand: number }
// trg_no_negative_stock and trg_update_timestamp fire automatically on DB.
// trg_low_stock_alert fires if new qty < 10.
// ---------------------------------------------------------------------------
async function updateStock(req, res, next) {
  let conn;
  try {
    const { quantity_on_hand } = req.body;
    if (quantity_on_hand === undefined) return res.status(400).json({ error: 'quantity_on_hand is required.' });

    conn = await getConnection();
    const result = await conn.execute(
      `UPDATE Camp_Inventory
       SET quantity_on_hand = :qty
       WHERE camp_id = :cid AND item_id = :iid`,
      {
        qty: quantity_on_hand,
        cid: parseInt(req.params.campId),
        iid: parseInt(req.params.itemId)
      }
    );
    if (!result.rowsAffected) return res.status(404).json({ error: 'Inventory row not found.' });
    await conn.commit();

    res.json({
      message: `Camp_Inventory updated. qty=${quantity_on_hand}. Triggers: trg_update_timestamp, trg_no_negative_stock${quantity_on_hand < 10 ? ', trg_low_stock_alert' : ''} fired.`,
      trigger_alert: quantity_on_hand < 10
    });
  } catch(err) { next(err); }
  finally { if (conn) await conn.close(); }
}

module.exports = { getAllInventory, getInventoryRow, updateStock };
