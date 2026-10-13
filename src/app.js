const express = require("express");
const mongoose = require("mongoose");
const Subscriber = require("./models/subscribers");

const app = express();

app.use(express.json());

// GET /subscribers: Fetch all subscribers
app.get("/subscribers", async (req, res) => {
  try {
    const subscribers = await Subscriber.find();
    res.json(subscribers); // Return full subscriber details
  } catch (error) {
    console.error("Failed to fetch subscribers:", error);
    res.status(500).json({ message: "Unable to fetch subscribers" });
  }
});

// GET /subscribers/names: Fetch only name and subscribedChannel fields (exclude _id)
app.get("/subscribers/names", async (req, res) => {
  try {
    const subscribers = await Subscriber.find().select(
      "name subscribedChannel -_id",
    );
    res.json(subscribers); // Return only name and subscribedChannel
  } catch (error) {
    console.error("Failed to fetch subscriber names:", error);
    res.status(500).json({ message: "Unable to fetch subscriber names" });
  }
});

// GET /subscribers/:id: Fetch a subscriber by their ID
app.get("/subscribers/:id", async (req, res) => {
  try {
    if (!mongoose.Types.ObjectId.isValid(req.params.id)) {
      return res.status(400).json({ message: "Invalid ID format" });
    }

    const subscriber = await Subscriber.findById(req.params.id);
    if (!subscriber) {
      return res.status(404).json({ message: "Subscriber not found" });
    }

    res.json(subscriber); // Return the subscriber data
  } catch (error) {
    console.error("Failed to fetch subscriber:", error);
    res.status(500).json({ message: "Unable to fetch subscriber" });
  }
});

module.exports = app; // Export the app to be used in index.js
