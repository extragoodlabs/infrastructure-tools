require("dotenv").config();
const name = "forest-admin";

console.log(`Booting ${name} agent`);

const express = require("express");

// Constants
const PORT = 3000;
// Important to bind to all hosts to run in a container
const HOST = "0.0.0.0";

// App
const app = express();
// Healthcheck route for ALB
app.get("/", (req, res) => {
  res.send("ping");
});

// Retrieve your sequelize instance
const { createAgent } = require("@forestadmin/agent");
const { createSequelizeDataSource } = require("@forestadmin/datasource-sequelize");
const { Sequelize } = require('sequelize');

const sequelize = new Sequelize(
  process.env.POSTGRESQL_URL
);
require("./models")(sequelize);

// Create your Forest Admin agent
// This must be called BEFORE all other middleware on the app
createAgent({
  authSecret: process.env.FOREST_AUTH_SECRET,
  envSecret: process.env.FOREST_ENV_SECRET,
  isProduction: process.env.NODE_ENV === "production",
  loggerLevel: "Info", // Valid values are 'Debug', 'Info', 'Warn' and 'Error'
  logger: (logLevel, message) => {
    console.log(logLevel, message);
  }
})
  // Create your SQL datasource
  .addDataSource(createSequelizeDataSource(sequelize))
  // Replace "myExpressApp" by your Express application
  .mountOnExpress(app)
  .start();

// Capture interrupt signal so that Docker container can gracefully exit
// https://github.com/nodejs/node/issues/4182
process.on("SIGINT", function () {
  console.log(`Exiting from http://${HOST}:${PORT}`);
  process.exit();
});

app.listen(PORT, HOST, () => {
  console.log(`Running on http://${HOST}:${PORT}`);
});
