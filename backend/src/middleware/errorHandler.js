function errorHandler(err, req, res, next) {
  console.error('Server Error:', err.message);
  
  // Send a clean JSON error to the frontend instead of crashing
  res.status(500).json({
    error: err.message || 'Internal Server Error'
  });
}

module.exports = errorHandler;