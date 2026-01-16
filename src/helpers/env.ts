declare const preval: any;

const env = preval`
  const path = require("path");
  const p = path.resolve(process.cwd(), './.env');
  const env = require('dotenv').config({ path: p })
  module.exports = env.parsed
`;

export default env;
