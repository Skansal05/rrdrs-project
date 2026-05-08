const oracledb = require('oracledb');
require('dotenv').config();
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;

console.log("ENV CHECK:", process.env.DB_CONNECT_STRING);
// Initialize the Oracle connection pool
async function createPool() {
  try {
    await oracledb.createPool({
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      connectString: process.env.DB_CONNECT_STRING,
      // Optional pool settings
      poolMin: 2,
      poolMax: 10,
      poolIncrement: 2
    });
    console.log('✅ Oracle Database connection pool created.');
  } catch (err) {
    console.error('❌ Error creating Oracle connection pool:', err);
    throw err;
  }
}

// Get a connection from the pool (used by all controllers)
async function getConnection() {
  return await oracledb.getConnection();
}

// Close the pool safely when the server shuts down
async function closePool() {
  try {
    await oracledb.getPool().close(10);
    console.log('Oracle Database connection pool closed.');
  } catch (err) {
    console.error('Error closing Oracle connection pool:', err);
  }
}

module.exports = { createPool, getConnection, closePool };