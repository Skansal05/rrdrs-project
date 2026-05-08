const { getConnection } = require('../db/pool');

async function getCriticalShortages(req, res, next) {
  let conn;
  try {
    conn = await getConnection();
    const result = await conn.execute(`
      SELECT
        rc.camp_name,
        rc.district,
        sc.item_name,
        ci.quantity_on_hand,
        rc.current_population,
        ROUND(
          ci.quantity_on_hand
          / NULLIF(rc.current_population * sc.per_person_daily_need, 0),
          2
        ) AS days_left
      FROM Camp_Inventory ci
      JOIN Relief_Camps   rc ON ci.camp_id = rc.camp_id
      JOIN Supply_Catalog sc ON ci.item_id = sc.item_id
      WHERE (
        ci.quantity_on_hand
        / NULLIF(rc.current_population * sc.per_person_daily_need, 0)
      ) < 3
      ORDER BY days_left ASC
    `);
    res.json({ count: result.rows.length, data: result.rows });
  } catch(err) { 
    next(err); 
  } finally { 
    if (conn) await conn.close(); 
  }
}

// Export the function exactly like the other controllers do
module.exports = { getCriticalShortages };