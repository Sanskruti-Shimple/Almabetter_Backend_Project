# Almabetter Backend — End-to-End Presentation Script

## Opening

“This project is the backend API for managing subscriber records. It is built with Node.js and Express, and it uses MongoDB through Mongoose. The API exposes three read-only routes: one returns every subscriber, one returns only subscriber names and channels, and one returns a single subscriber by its MongoDB ID.”

## Architecture and request flow

“A client sends an HTTPS request to the Express application. Express matches the route and the route handler calls the Mongoose `Subscriber` model. Mongoose converts that request into MongoDB operations and returns the result as JSON. In Azure, the Node.js API runs on Linux App Service and the database is Azure Cosmos DB’s MongoDB-compatible API. App Service reads the MongoDB URI from Key Vault using a user-assigned managed identity, so the connection credential is not shipped in the source package.”

“Application Insights receives application telemetry, and App Service diagnostic settings send platform logs and metrics to Log Analytics. The web app is HTTPS-only, requires TLS 1.2, and disables FTP.”

## Code walkthrough

“The application entry point is `src/index.js`. It loads environment settings, connects to MongoDB with Mongoose, and only starts listening after the database connection opens. The listening port comes from `PORT`, with 3000 as the local-development fallback.”

“`src/app.js` creates the Express app and defines the HTTP routes. `GET /subscribers` returns all records. `GET /subscribers/names` projects only `name` and `subscribedChannel`, leaving out MongoDB’s `_id`. `GET /subscribers/:id` first validates the ID format, returns HTTP 400 for an invalid format, HTTP 404 when no matching record exists, and the document when found. Database errors are returned with an HTTP error response.”

“`src/models/subscribers.js` defines the Mongoose schema. Each subscriber requires a `name` and a `subscribedChannel`, both strings. Mongoose uses this model for database reads and writes.”

“`src/createDatabase.js` is the optional sample-data seeder. It clears the subscriber collection and inserts four sample records, so I only run it against a fresh demo database or when I intentionally want to reset that data.”

## Environment and local run

“The app uses `MONGODB_URI` for the database connection and `PORT` for its HTTP listener. Locally, I set those values in `src/.env`, install dependencies with `npm install`, and start the service with `npm start`. The deployment package excludes `src/.env` and `node_modules`; Azure injects configuration instead, and App Service builds the Node.js dependencies during deployment.”

## Azure deployment walkthrough

“The infrastructure is described in `infra/main.bicep`, with parameter values in `infra/main.parameters.json`. The deployment provisions an F1 Linux App Service plan, the web app, a user-assigned identity, Cosmos DB for MongoDB in serverless mode, Key Vault, Application Insights, and Log Analytics. Resource names are deterministic and unique within the subscription, resource group, region, and environment.”

“The deployment script, `.azure/deploy.ps1`, first checks the Azure CLI subscription and identity, compiles the Bicep template, creates the resource group, and runs an Azure `what-if` preview before provisioning. It then obtains the Cosmos DB key without printing it, stores a MongoDB URI in Key Vault, and deploys a zip containing only the application source and package manifests. Finally, it restarts the app and probes `GET /subscribers` over HTTPS.”

“Cosmos DB is configured with the required Azure-services firewall rule. The deployment uses one region and serverless database capacity, so Cosmos DB charges can still apply based on requests and stored data. The F1 App Service tier is appropriate for a low-traffic demo and does not provide Always On. Before production, I would choose a production hosting tier, replace wildcard CORS with the real frontend origin, add authentication and authorization, and review the database network design and scale requirements.”

## Demo sequence

1. “I’ll call `GET /subscribers` to show the full response.”
2. “I’ll call `GET /subscribers/names` to show the limited projection.”
3. “I’ll call `GET /subscribers/{id}` with a valid ID, an invalid ID, and an unknown valid ID to demonstrate the 200, 400, and 404 responses.”
4. “I’ll show the Azure App Service URL and the resource group, then point out that the MongoDB credential is stored in Key Vault rather than in the deployment package.”

## Closing summary

“In summary, the project separates HTTP routing, data modeling, and database connection startup. The API is small and read-only; the seeder is a separate optional operation. Azure hosts the API, Cosmos DB provides MongoDB-compatible storage, managed identity and Key Vault protect the database credential, and Application Insights plus Log Analytics provide operational visibility.”
