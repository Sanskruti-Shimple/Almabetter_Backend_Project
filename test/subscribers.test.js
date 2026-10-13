const assert = require("node:assert/strict");
const http = require("node:http");
const { after, afterEach, before, test } = require("node:test");
const app = require("../src/app");
const Subscriber = require("../src/models/subscribers");

let server;
let baseUrl;

before(async () => {
  server = app.listen(0, "127.0.0.1");
  await new Promise((resolve, reject) => {
    server.once("listening", resolve);
    server.once("error", reject);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.closeAllConnections();
  await new Promise((resolve, reject) => {
    server.close((error) => (error ? reject(error) : resolve()));
  });
});

afterEach(() => {
  Subscriber.find = originalFind;
  Subscriber.findById = originalFindById;
});

const originalFind = Subscriber.find;
const originalFindById = Subscriber.findById;

const request = (path) =>
  new Promise((resolve, reject) => {
    http.get(`${baseUrl}${path}`, (response) => {
      let body = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => {
        body += chunk;
      });
      response.on("end", () => {
        resolve({
          status: response.statusCode,
          json: JSON.parse(body),
        });
      });
    }).on("error", reject);
  });

test("GET /subscribers returns subscriber records", async () => {
  const records = [{ name: "Alice", subscribedChannel: "Tech Talks" }];
  Subscriber.find = async () => records;

  const response = await request("/subscribers");

  assert.equal(response.status, 200);
  assert.deepEqual(response.json, records);
});

test("GET /subscribers/names returns only name and channel fields", async () => {
  const records = [{ name: "Alice", subscribedChannel: "Tech Talks" }];
  Subscriber.find = () => ({
    select: async (fields) => {
      assert.equal(fields, "name subscribedChannel -_id");
      return records;
    },
  });

  const response = await request("/subscribers/names");

  assert.equal(response.status, 200);
  assert.deepEqual(response.json, records);
});

test("GET /subscribers/:id rejects malformed IDs", async () => {
  const response = await request("/subscribers/not-an-object-id");

  assert.equal(response.status, 400);
  assert.deepEqual(response.json, { message: "Invalid ID format" });
});

test("GET /subscribers/:id returns 404 for an unknown subscriber", async () => {
  Subscriber.findById = async () => null;

  const response = await request("/subscribers/507f1f77bcf86cd799439011");

  assert.equal(response.status, 404);
  assert.deepEqual(response.json, { message: "Subscriber not found" });
});

test("GET /subscribers returns a generic error when the database query fails", async () => {
  Subscriber.find = async () => {
    throw new Error("internal database details");
  };

  const response = await request("/subscribers");

  assert.equal(response.status, 500);
  assert.deepEqual(response.json, { message: "Unable to fetch subscribers" });
  assert.equal(JSON.stringify(response.json).includes("internal database"), false);
});
