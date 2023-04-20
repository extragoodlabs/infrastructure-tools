const { DataTypes } = require('sequelize')

module.exports = (sequelize) => {
  // Define Country.
  const Country = sequelize.define(
    'country',
    {
      country_id: {
        type: DataTypes.INTEGER,
        primaryKey: true
      },
      country: DataTypes.TEXT,
      last_update: DataTypes.TIME
    },
    { freezeTableName: true, timestamps: false }
  )

  // Define City.
  const City = sequelize.define(
    'city',
    {
      city_id: {
        type: DataTypes.INTEGER,
        primaryKey: true
      },
      city: DataTypes.TEXT,
      country_id: DataTypes.INTEGER,
      last_update: DataTypes.TIME
    },
    { freezeTableName: true, timestamps: false }
  )

  City.hasOne(Country, { foreignKey: 'country_id' })

  // Define Address.
  const Address = sequelize.define(
    'address',
    {
      address_id: {
        type: DataTypes.INTEGER,
        primaryKey: true
      },
      address: DataTypes.TEXT,
      address2: DataTypes.TEXT,
      district: DataTypes.TEXT,
      city_id: DataTypes.INTEGER,
      postal_code: DataTypes.TEXT,
      phone: DataTypes.TEXT,
      last_update: DataTypes.TIME
    },
    { freezeTableName: true, timestamps: false }
  )

  Address.hasOne(City, { foreignKey: 'city_id' })

  // Define Customer.
  const Customer = sequelize.define(
    'customer',
    {
      customer_id: {
        type: DataTypes.INTEGER,
        primaryKey: true
      },
      store_id: DataTypes.INTEGER,
      address_id: DataTypes.INTEGER,
      first_name: DataTypes.TEXT,
      last_name: DataTypes.TEXT,
      ssn: DataTypes.TEXT,
      email: DataTypes.TEXT,
      active: {
        type: DataTypes.BOOLEAN,
        default: true
      },
      create_date: DataTypes.DATEONLY,
      last_update: DataTypes.TIME
    },
    { freezeTableName: true, timestamps: false }
  )

  Customer.hasOne(Address, { foreignKey: 'address_id' })

  // Define Staff.
  const Staff = sequelize
    .define(
      'staff',
      {
        staff_id: {
          type: DataTypes.INTEGER,
          primaryKey: true
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
          default: true
        },
        last_update: DataTypes.TIME
      },
      { freezeTableName: true, timestamps: false }
    )
  Staff.hasOne(Address, { foreignKey: 'address_id' })

  // Define Payment.
  const Payment = sequelize.define(
    'payment',
    {
      payment_id: {
        type: DataTypes.INTEGER,
        primaryKey: true
      },
      amount: DataTypes.NUMBER,
      customer_id: DataTypes.INTEGER,
      staff_id: DataTypes.INTEGER,
      cc_number: DataTypes.TEXT,
      cc_expiration: DataTypes.TEXT,
      cc_cvv: DataTypes.TEXT,
      payment_date: DataTypes.TIME
    },
    { freezeTableName: true, timestamps: false }
  )
  Payment.hasOne(Customer, {foreignKey: 'customer_id'})
  Payment.hasOne(Staff, { foreignKey: 'staff_id' })

  return { Country, City, Address, Customer, Staff, Payment }
}
