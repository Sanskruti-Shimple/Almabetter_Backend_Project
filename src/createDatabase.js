const path = require("path");
require("dotenv").config({ path: path.join(__dirname, ".env") }); // <-- Load .env variables

const mongoose = require("mongoose");
const Subscriber = require("./models/subscribers");

const createDatabase = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI, {
      serverSelectionTimeoutMS: 5000,
    });

    console.log("Connected to MongoDB");

    await Subscriber.deleteMany({});
    await Subscriber.insertMany([
      { name: "Alice", subscribedChannel: "Tech Talks" },
      { name: "Bob", subscribedChannel: "Cooking with Bob" },
      { name: "Charlie", subscribedChannel: "Fitness Freak" },
      { name: "Gaurav", subscribedChannel: "Fitness Boy" },
    ]);

    console.log("Sample subscribers added");
    await mongoose.connection.close();
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
};

createDatabase();
