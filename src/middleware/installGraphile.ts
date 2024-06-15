import PgManyToManyPlugin from "@graphile-contrib/pg-many-to-many";
import PgSimplifyInflectorPlugin from "@graphile-contrib/pg-simplify-inflector";
import PgPubsub from "@graphile/pg-pubsub";
import { Express, Request, Response } from "express";
import { NodePlugin } from "graphile-build";
import Jwt from "jsonwebtoken";
import { resolve } from "path";
import { Pool, PoolClient } from "pg";
import {
  PostGraphileOptions,
  makePluginHook,
  postgraphile,
} from "postgraphile";
import ConnectionFilterPlugin from "postgraphile-plugin-connection-filter";
import { makePgSmartTagsFromFilePlugin } from "postgraphile/plugins";
// @ts-ignore (type not available yet)
import PostGraphileNestedMutations from "postgraphile-plugin-nested-mutations";
import { getWebsocketMiddlewares } from "../app";
import { PassportLoginPlugin } from "../plugins";
import { uuidOrNull } from "../utility";
import { getAuthPgPool, getRootPgPool } from "./installDatabase";

export interface OurGraphQLContext {
  pgClient: PoolClient;
  sessionId: string | null;
  rootPgPool: Pool;
  login(user: any): Promise<string>;
  logout(): Promise<void>;
}

const pluginHook = makePluginHook([PgPubsub]);

const TagsFilePlugin = makePgSmartTagsFromFilePlugin(
  resolve(__dirname, "../../postgraphile.tags.jsonc")
);

const isDev = process.env.NODE_ENV === "development";

const getGraphileOptions = ({
  rootPgPool,
  websocketMiddlewares,
}): PostGraphileOptions<Request, Response> => {
  return {
    pluginHook,
    appendPlugins: [
      TagsFilePlugin,
      PgManyToManyPlugin,
      PostGraphileNestedMutations,
      PgSimplifyInflectorPlugin,
      ConnectionFilterPlugin,
      PassportLoginPlugin,
    ],
    skipPlugins: [NodePlugin],
    websocketMiddlewares,
    async pgSettings(req) {
      // @ts-ignore
      const sessionId = uuidOrNull(req.user?.session_id);
      if (sessionId) {
        await rootPgPool.query(
          "UPDATE app_private.sessions SET last_active = NOW() WHERE uuid = $1 AND last_active < NOW() - INTERVAL '15 seconds'",
          [sessionId]
        );
      }
      return {
        role: process.env.DATABASE_VISITOR,
        "jwt.claims.session_id": sessionId,
      };
    },
    async additionalGraphQLContextFromRequest(
      req
    ): Promise<Partial<OurGraphQLContext>> {
      return {
        // @ts-ignore
        sessionId: uuidOrNull(req.user?.session_id),
        login(session) {
          const token = Jwt.sign(session, process.env.JWT_SECRET || "", {
            issuer: process.env.ROOT_URL,
          });
          return Promise.resolve(token);
        },
        logout() {
          return Promise.resolve();
        },
        rootPgPool,
      };
    },
    graphileBuildOptions: {
      pgStrictFunctions: true,
      nestedMutationsSimpleFieldNames: true,
      connectionFilterAllowedOperators: [
        "isNull",
        "equalTo",
        "notEqualTo",
        "distinctFrom",
        "notDistinctFrom",
        "lessThan",
        "lessThanOrEqualTo",
        "greaterThan",
        "greaterThanOrEqualTo",
        "in",
        "notIn",
        "includesInsensitive",
      ],

      connectionFilterOperatorNames: {
        equalTo: "eq",
        notEqualTo: "ne",
      },

      connectionFilterRelations: true, // default: false

      connectionFilterAllowNullInput: true, // default: false

      connectionFilterAllowEmptyObjectInput: true, // default: false
    },
    watchPg: isDev,
    graphiql: isDev || !!process.env.ENABLE_GRAPHIQL,
    enhanceGraphiql: true,
    subscriptions: true,
    dynamicJson: true,
    setofFunctionsContainNulls: false,
    ignoreRBAC: false,
    ignoreIndexes: false,
    showErrorStack: "json",
    extendedErrors: ["hint", "detail", "errcode"],
    allowExplain: isDev,
    legacyRelations: "omit",
    exportGqlSchemaPath: `${__dirname}/../../data/schema.graphql`,
    sortExport: true,
    disableQueryLog: true,
  };
};

const installGraphile = (app: Express) => {
  const authPgPool = getAuthPgPool(app);
  const rootPgPool = getRootPgPool(app);
  const websocketMiddlewares = getWebsocketMiddlewares(app);

  const options = getGraphileOptions({ rootPgPool, websocketMiddlewares });
  const middleware = postgraphile(authPgPool, "app_public", options);
  app.use(middleware);
};

export default installGraphile;
