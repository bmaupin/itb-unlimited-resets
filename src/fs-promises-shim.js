// Shim to add fs/promises support for Node < 14
try {
  module.exports = require('fs/promises');
} catch {
  const fs = require('fs');
  const { promisify } = require('util');
  module.exports = {
    readFile: promisify(fs.readFile),
    writeFile: promisify(fs.writeFile),
    // Add others if needed later
  };
}
