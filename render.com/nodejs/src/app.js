require("dotenv").config();

const express = require("express");
const app = express();

const { createAgent } = require("@forestadmin/agent");
const {
  createSequelizeDataSource,
} = require("@forestadmin/datasource-sequelize");

// Retrieve your sequelize instance
const { Sequelize } = require('sequelize');

const sequelize = new Sequelize(
  "postgres://postgres:postgres@localhost:5432/storefront"
); // Example for postgres
require("./models")(sequelize);

// Create your Forest Admin agent
// This must be called BEFORE all other middleware on the app
createAgent({
  authSecret: process.env.FOREST_AUTH_SECRET,
  envSecret: process.env.FOREST_ENV_SECRET,
  isProduction: process.env.NODE_ENV === "production",
})
  // Create your Sequelize datasource
  .addDataSource(createSequelizeDataSource(sequelize))
  // Replace "myExpressApp" by your Express application
  .mountOnExpress(app)
  .start();

app.listen(3000);
