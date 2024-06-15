import { makeApp } from "./app";

const app = makeApp();

const server = app.listen(process.env.PORT || 5001, () => {
  const address = server.address();
  if (typeof address !== "string") {
    const href = `http://localhost:${address.port}/graphiql`;
    console.log(`PostGraphiQL available at ${href} 🚀`);
  } else {
    console.log(`PostGraphile listening on ${address} 🚀`);
  }
});
