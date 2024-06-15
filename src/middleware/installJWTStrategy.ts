import { Express, RequestHandler } from "express";
import passport from "passport";
import { ExtractJwt, Strategy as JwtStrategy } from "passport-jwt";

import { getWebsocketMiddlewares } from "../app";
import { getRootPgPool } from "./installDatabase";

interface DbSession {
  uuid: string;
  user_id: string;
  created_at: Date;
  last_active: Date;
}

export interface JwtPayload {
  session_id: string;
}

export default async (app: Express) => {
  if (!process.env.JWT_SECRET) {
    return;
  }
  const options = {
    jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
    secretOrKey: process.env.JWT_SECRET,
  };
  const rootPgPool = getRootPgPool(app);
  passport.use(
    new JwtStrategy(options, async (jwtPayload: JwtPayload, done: Function) => {
      try {
        let session: DbSession | null = null;
        if (!jwtPayload || !jwtPayload.session_id) {
          done(null);
        }
        ({
          rows: [session],
        } = await rootPgPool.query<DbSession>(
          "select * from app_private.sessions where uuid = $1",
          [jwtPayload.session_id]
        ));
        done(null, { session_id: session?.uuid });
      } catch (err) {
        console.log(err, "error in verify");
        done(err);
      }
    })
  );
  const jwtMiddleware: RequestHandler = (req, res, next) => {
    const token = options.jwtFromRequest(req);
    if (token) {
      passport.authenticate("jwt", {
        session: false,
      })(req, res, next);
    } else {
      next();
    }
  };
  app.use(jwtMiddleware);
  getWebsocketMiddlewares(app).push(jwtMiddleware);
};
