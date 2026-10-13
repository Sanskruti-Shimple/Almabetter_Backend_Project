#Live link-
https://almabetter-backend-project-737r.onrender.com/

# Almabetter Backend

A simple Node.js + Express + MongoDB backend for managing subscribers.

## Tech Stack

- Node.js
- Express
- MongoDB
- Mongoose
- dotenv

## Prerequisites

Before running this project, make sure you have:

- Node.js installed
- MongoDB installed and running locally
- npm installed

## Local MongoDB Setup

### 1) Start MongoDB

Open a terminal and run:

```bash
mongod
```

If MongoDB is installed correctly, it will start on:

```text
mongodb://127.0.0.1:27017
```

### 2) Install dependencies

From the project root:

```bash
npm install
```

### 3) Seed sample data

Run:

```bash
npm run seed
```

This clears the subscriber collection before inserting sample records. Do not run it on a database with data you need to keep.

### 4) Start the server

```bash
npm start
```

The server will run on:

```text
http://localhost:3000
```

## API Endpoints

### Get all subscribers

```http
GET /subscribers
```


### Get a subscriber by ID

```http
GET /subscribers/:id
```

## Environment Variables

Create a `.env` file inside the `src` folder with:

```env
MONGODB_URI=mongodb://127.0.0.1:27017/almabetter
PORT=3000
```

`src/.env.example` documents the local settings. Copy it to `src/.env` and adjust the values for your machine. Never commit `.env` files or real database credentials.

## Project Structure

```text
Almabetter_backend/
├── src/
│   ├── .env.example
│   ├── app.js
│   ├── createDatabase.js
│   ├── index.js
│   └── models/
│       └── subscribers.js
├── test/
├── .gitignore
├── package.json
├── README.md
└── package-lock.json
```

## Common Issues

### MongoDB connection error

If you see an error like:

```text
ECONNREFUSED
```

then check:

- MongoDB is running
- MongoDB is installed correctly
- your `.env` file uses the local MongoDB URI

### Empty list from `/subscribers`

This usually means:

- the database is empty
- the connection is not working
- sample data was never inserted

Run:

```bash
npm run seed
```

again to replace all subscriber documents with the test records. This operation is destructive.

## Notes

This project is configured for local MongoDB development. If you later want to move to MongoDB Atlas, update the `MONGODB_URI` in the `.env` file.

## Azure deployment

The optional Azure deployment provisions a Linux App Service API and Azure Cosmos DB for MongoDB. The app obtains `MONGODB_URI` from Key Vault through a user-assigned managed identity; do not add database credentials to the repository or deployment package.

Prerequisites: Azure CLI with an authenticated account that can create the required resources and role assignments in the target subscription.

From the repository root, run:

```powershell
.\.azure\deploy.ps1
```

The script builds the Bicep template, previews infrastructure changes with `what-if`, provisions the resources, stores the Cosmos DB URI in Key Vault, packages the app without `src/.env` or `node_modules`, deploys it, and checks `GET /subscribers`. The default region is Central US and the App Service plan is F1 for a low-traffic demo. Cosmos DB serverless storage and operations may still incur charges. Review `.azure\plan.copilotmd` for the architecture and `.azure\presentation-script.md` for the project walkthrough.

The `seed` script deletes existing subscriber documents before inserting sample records. Do not run it against a database containing data you need to keep.
