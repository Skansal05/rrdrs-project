const express = require('express');
const router = express.Router();
const inventoryController = require('../controllers/inventoryController');

router.get('/', inventoryController.getAllInventory);
router.get('/:campId/:itemId', inventoryController.getInventoryRow);
router.put('/:campId/:itemId', inventoryController.updateStock);

module.exports = router;