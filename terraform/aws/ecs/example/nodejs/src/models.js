const { DataTypes } = require("sequelize");

module.exports = (sequelize) => {
  // Define Customer.
  const Customer = sequelize.define(
    "customer",
    {
      customer_id: {
        type: DataTypes.INTEGER,
        primaryKey: true,
      },
      store_id: DataTypes.INTEGER,
      address_id: DataTypes.INTEGER,
      first_name: DataTypes.TEXT,
      last_name: DataTypes.TEXT,
      email: DataTypes.TEXT,
      ssn: DataTypes.TEXT,
      active: {
        type: DataTypes.BOOLEAN,
        default: true,
      },
      create_date: DataTypes.DATEONLY,
      last_update: DataTypes.TIME,
    },
    { freezeTableName: true, timestamps: false }
  );

  // Define Staff.
  const Staff = sequelize.define(
    "staff",
    {
      staff_id: {
        type: DataTypes.INTEGER,
        primaryKey: true,
      },
      store_id: DataTypes.INTEGER,
      address_id: DataTypes.INTEGER,
      first_name: DataTypes.TEXT,
      last_name: DataTypes.TEXT,
      email: DataTypes.TEXT,
      username: DataTypes.TEXT,
      password: DataTypes.TEXT,
      active: {
        type: DataTypes.BOOLEAN,
        default: true,
      },
      last_update: DataTypes.TIME,
    },
    { freezeTableName: true, timestamps: false }
  );

  // Define Payment.
  const Payment = sequelize.define(
    "payment",
    {
      payment_id: {
        type: DataTypes.INTEGER,
        primaryKey: true,
      },
      staff_id: DataTypes.INTEGER,
      customer_id: DataTypes.INTEGER,
      rental_id: DataTypes.INTEGER,
      amount: DataTypes.INTEGER,
      cc_number: DataTypes.TEXT,
      cc_expiration: DataTypes.TEXT,
      cc_cvv: DataTypes.TEXT,
      payment_date: DataTypes.TIME,
    },
    { freezeTableName: true, timestamps: false }
  );

  return { Staff, Customer, Payment };
};
