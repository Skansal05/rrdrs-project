const express = require('express');
const router = express.Router();
const shipmentsController = require('../controllers/shipmentsController');

router.get('/', shipmentsController.getAllShipments);
router.post('/', shipmentsController.createShipment);
router.put('/:id', shipmentsController.updateShipmentStatus);

module.exports = router;