const express = require('express');
const router = express.Router();
const reportController = require('../controllers/reportController');

// GET /api/report/shortages
router.get('/shortages', reportController.getCriticalShortages);

module.exports = router;