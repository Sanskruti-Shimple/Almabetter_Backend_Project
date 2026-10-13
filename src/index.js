const path = require("path");
require("dotenv").config({ path: path.join(__dirname, ".env") });

const mongoose = require("mongoose");
const app = require("./app"); // Import the app from app.js

const start = async () => {
  if (!process.env.MONGODB_URI) {
    throw new Error("MONGODB_URI must be set before starting the server");
  }

  await mongoose.connect(process.env.MONGODB_URI, {
    serverSelectionTimeoutMS: 5000,
  });
  console.log("Connected to MongoDB");

  const PORT = process.env.PORT || 3000;
  const server = app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server listening on port ${PORT}`);
  });

  server.on("error", (error) => {
    console.error("HTTP server error:", error);
    process.exitCode = 1;
  });
};

start().catch((error) => {
  console.error("Server startup failed:", error);
  process.exitCode = 1;
});
