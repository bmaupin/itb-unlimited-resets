// Shim to add fs/promises support for Node < 14
try {
  module.exports = require('fs/promises');
} catch {
  const fs = require('fs');
  const { promisify } = require('util');
  module.exports = {
    open: promisify(fs.open),
  };
}
