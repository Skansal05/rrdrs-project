// =============================================================================
//  src/controllers/campsController.js
//  CRUD for RELIEF_CAMPS table.
//
//  Routes handled (see src/routes/camps.js):
//    GET    /api/camps          → getAllCamps
//    GET    /api/camps/:id      → getCampById
//    POST   /api/camps          → createCamp
//    PUT    /api/camps/:id      → updateCamp
//    DELETE /api/camps/:id      → deleteCamp
// =============================================================================

const { getConnection } = require('../db/pool');

// ---------------------------------------------------------------------------
// GET /api/camps
// Returns every row in RELIEF_CAMPS ordered by camp_id.
// Also computes a "status" label based on Camp_Inventory days_left
// (Critical < 1 day, Low < 3 days, Stable otherwise).
// ---------------------------------------------------------------------------
async function getAllCamps(req, res, next) {
  let conn;
  try {
    conn = await getConnection();

    const result = await conn.execute(`
      SELECT
        rc.camp_id,
        rc.camp_name,
        rc.district,
        rc.latitude,
        rc.longitude,
        rc.current_population,
        rc.contact_person,
        rc.contact_number,
        -- Minimum days-left across all items at this camp
        ROUND(
          MIN(
            ci.quantity_on_hand
            / NULLIF(rc.current_population * sc.per_person_daily_need, 0)
          ), 2
        ) AS min_days_left
      FROM Relief_Camps rc
      LEFT JOIN Camp_Inventory ci ON rc.camp_id = ci.camp_id
      LEFT JOIN Supply_Catalog sc ON ci.item_id  = sc.item_id
      GROUP BY
        rc.camp_id, rc.camp_name, rc.district,
        rc.latitude, rc.longitude, rc.current_population,
        rc.contact_person, rc.contact_number
      ORDER BY rc.camp_id
    `);

    // Attach a human-readable status label
    const camps = result.rows.map(row => ({
      ...row,
      STATUS:
        row.MIN_DAYS_LEFT === null   ? 'No Stock Data' :
        row.MIN_DAYS_LEFT < 1        ? 'Critical' :
        row.MIN_DAYS_LEFT < 3        ? 'Low Stock' : 'Stable',
    }));

    res.json({ count: camps.length, data: camps });
  } catch (err) {
    next(err);
  } finally {
    if (conn) await conn.close(); // always return connection to pool
  }
}

// ---------------------------------------------------------------------------
// GET /api/camps/:id
// Returns a single camp with its full inventory breakdown.
// ---------------------------------------------------------------------------
async function getCampById(req, res, next) {
  let conn;
  try {
    conn = await getConnection();
    const campId = parseInt(req.params.id, 10);

    // Camp row
    const campResult = await conn.execute(
      `SELECT * FROM Relief_Camps WHERE camp_id = :id`,
      { id: campId }
    );

    if (campResult.rows.length === 0) {
      return res.status(404).json({ error: `Camp with id ${campId} not found.` });
    }

    // Inventory for this camp (uses get_days_left function)
    const invResult = await conn.execute(
      `SELECT
         ci.item_id,
         sc.item_name,
         sc.category,
         ci.quantity_on_hand,
         sc.per_person_daily_need,
         get_days_left(ci.camp_id, ci.item_id) AS days_left,
         ci.last_updated
       FROM Camp_Inventory ci
       JOIN Supply_Catalog sc ON ci.item_id = sc.item_id
       WHERE ci.camp_id = :id
       ORDER BY days_left ASC`,
      { id: campId }
    );

    res.json({
      camp: campResult.rows[0],
      inventory: invResult.rows,
    });
  } catch (err) {
    next(err);
  } finally {
    if (conn) await conn.close();
  }
}

// ---------------------------------------------------------------------------
// POST /api/camps
// Inserts a new camp. camp_id must be provided (not sequenced by design).
// Body: { camp_id, camp_name, district, latitude, longitude,
//         current_population, contact_person, contact_number }
// ---------------------------------------------------------------------------
async function createCamp(req, res, next) {
  let conn;
  try {
    const {
      camp_id, camp_name, district,
      latitude, longitude, current_population,
      contact_person, contact_number,
    } = req.body;

    // Basic validation
    if (!camp_id || !camp_name || current_population === undefined) {
      return res.status(400).json({
        error: 'camp_id, camp_name, and current_population are required.',
      });
    }
    if (current_population < 0) {
      return res.status(400).json({ error: 'current_population must be >= 0.' });
    }

    conn = await getConnection();

    await conn.execute(
      `INSERT INTO Relief_Camps
         (camp_id, camp_name, district, latitude, longitude,
          current_population, contact_person, contact_number)
       VALUES
         (:camp_id, :camp_name, :district, :latitude, :longitude,
          :current_population, :contact_person, :contact_number)`,
      {
        camp_id, camp_name, district: district || null,
        latitude: latitude || null, longitude: longitude || null,
        current_population, contact_person: contact_person || null,
        contact_number: contact_number || null,
      }
    );

    await conn.commit();
    res.status(201).json({ message: `Camp ${camp_id} created successfully.` });
  } catch (err) {
    next(err);
  } finally {
    if (conn) await conn.close();
  }
}

// ---------------------------------------------------------------------------
// PUT /api/camps/:id
// Updates a camp's editable fields (not camp_id itself — that's the PK).
// Body: any subset of { camp_name, district, current_population,
//                       contact_person, contact_number }
// ---------------------------------------------------------------------------
async function updateCamp(req, res, next) {
  let conn;
  try {
    const campId = parseInt(req.params.id, 10);
    const {
      camp_name, district, current_population,
      contact_person, contact_number,
    } = req.body;

    if (current_population !== undefined && current_population < 0) {
      return res.status(400).json({ error: 'current_population must be >= 0.' });
    }

    conn = await getConnection();

    const result = await conn.execute(
      `UPDATE Relief_Camps SET
         camp_name          = NVL(:camp_name,          camp_name),
         district           = NVL(:district,           district),
         current_population = NVL(:current_population, current_population),
         contact_person     = NVL(:contact_person,     contact_person),
         contact_number     = NVL(:contact_number,     contact_number)
       WHERE camp_id = :id`,
      {
        camp_name: camp_name || null,
        district: district || null,
        current_population: current_population !== undefined ? current_population : null,
        contact_person: contact_person || null,
        contact_number: contact_number || null,
        id: campId,
      }
    );

    if (result.rowsAffected === 0) {
      return res.status(404).json({ error: `Camp ${campId} not found.` });
    }

    await conn.commit();
    res.json({ message: `Camp ${campId} updated.` });
  } catch (err) {
    next(err);
  } finally {
    if (conn) await conn.close();
  }
}

// ---------------------------------------------------------------------------
// DELETE /api/camps/:id
// Deletes a camp. ON DELETE CASCADE handles Camp_Inventory and
// Relief_Requests rows automatically.
// ---------------------------------------------------------------------------
async function deleteCamp(req, res, next) {
  let conn;
  try {
    const campId = parseInt(req.params.id, 10);
    conn = await getConnection();

    const result = await conn.execute(
      `DELETE FROM Relief_Camps WHERE camp_id = :id`,
      { id: campId }
    );

    if (result.rowsAffected === 0) {
      return res.status(404).json({ error: `Camp ${campId} not found.` });
    }

    await conn.commit();
    res.json({
      message: `Camp ${campId} deleted. CASCADE removed linked inventory and requests.`,
    });
  } catch (err) {
    next(err);
  } finally {
    if (conn) await conn.close();
  }
}

module.exports = { getAllCamps, getCampById, createCamp, updateCamp, deleteCamp };
