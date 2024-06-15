import express, { Express } from "express";
import { Middleware } from "postgraphile";

import * as middlewares from "./middleware";
import { makeShutdownActions, ShutdownAction } from "./utility";

export function getShutdownActions(app: Express): ShutdownAction[] {
  return app.get("shutdownActions");
}

export function getWebsocketMiddlewares(
  app: Express
): Middleware<express.Request, express.Response>[] {
  return app.get("websocketMiddlewares");
}

export function makeApp(): Express {
  const app = express();
  app.use(express.json({ limit: "1mb" }));
  const shutdownActions = makeShutdownActions();
  app.set("shutdownActions", shutdownActions);

  const websocketMiddlewares: Middleware<express.Request, express.Response>[] =
    [];
  app.set("websocketMiddlewares", websocketMiddlewares);

  middlewares.installCORS(app);
  middlewares.installDatabase(app);
  middlewares.installPassport(app);
  middlewares.installGraphile(app);
  return app;
}
