const express = require('express');
const router = express.Router();
const campsController = require('../controllers/campsController');

router.get('/', campsController.getAllCamps);
router.get('/:id', campsController.getCampById);
router.post('/', campsController.createCamp);
router.put('/:id', campsController.updateCamp);
router.delete('/:id', campsController.deleteCamp);

module.exports = router;