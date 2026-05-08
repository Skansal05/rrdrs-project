// =============================================================================
//  src/server.js  — RRDRS Express server (entry point)
//  Run with: npm run dev
//  Listens on: http://localhost:3000
// =============================================================================
require('dotenv').config();
const express      = require('express');
const cors         = require('cors');
const { createPool, closePool } = require('./src/db/pool');
const errorHandler = require('./src/middleware/errorHandler');

const app = express();

// Allow the HTML file (opened directly from disk) to call this API
app.use(cors());
app.use(express.json());

// ── Route groups (each maps to one DB table / feature) ───────────────────────
app.use('/api/camps',     require('./src/routes/camps'));
app.use('/api/inventory', require('./src/routes/inventory'));
app.use('/api/requests',  require('./src/routes/requests'));
app.use('/api/shipments', require('./src/routes/shipments'));
app.use('/api/report',    require('./src/routes/report'));

// Health check — visit http://localhost:3000/api/health in browser to verify
app.get('/api/health', (req, res) => res.json({ status: 'ok', project: 'RRDRS', group: '2C65' }));

// Central error handler (must be last middleware)
app.use(errorHandler);

// ── Startup ──────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
(async () => {
  await createPool();           // open Oracle connection pool first
  app.listen(PORT, () => {
    console.log(`🚀  RRDRS backend running on http://localhost:${PORT}`);
    console.log(`📋  Routes: /api/camps · /api/inventory · /api/requests · /api/shipments · /api/report`);
  });
})();

// Graceful shutdown on Ctrl+C
process.on('SIGINT', async () => { await closePool(); process.exit(0); });
