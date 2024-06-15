import { gql, makeExtendSchemaPlugin } from "graphile-utils";

import { OurGraphQLContext } from "../middleware/installGraphile";
import { ERROR_MESSAGE_OVERRIDES } from "../utility";

const PassportLoginPlugin = makeExtendSchemaPlugin((build) => ({
  typeDefs: gql`
    input RegisterInput {
      username: String!
      email: String!
      password: String!
    }

    type RegisterPayload {
      user: User! @pgField
      token: String
    }

    input LoginInput {
      username: String!
      password: String!
    }

    type LoginPayload {
      user: User! @pgField
      token: String
    }

    type LogoutPayload {
      success: Boolean
    }

    extend type Mutation {
      register(input: RegisterInput!): RegisterPayload

      login(input: LoginInput!): LoginPayload

      logout: LogoutPayload
    }
  `,
  resolvers: {
    Mutation: {
      async register(_, args, context: OurGraphQLContext, resolveInfo) {
        const { selectGraphQLResultFromTable } = resolveInfo.graphile;
        const { username, password, email } = args.input;
        const { rootPgPool, pgClient, login } = context;
        try {
          // Create a user and create a session for it in the proccess
          const {
            rows: [details],
          } = await rootPgPool.query(
            `
            with new_user as (
              select users.* from app_private.really_create_user(
                username => $1,
                email => $2,
                password => $3
              ) users where not (users is null)
            ), new_session as (
              insert into app_private.sessions (user_id)
              select id from new_user
              returning *
            )
            select new_user.id as user_id, new_session.uuid as session_id
            from new_user, new_session`,
            [username, email, password]
          );

          if (!details || !details.user_id) {
            const e = new Error("Registration failed");
            e["code"] = "FFFFF";
            throw e;
          }

          if (details.session_id) {
            // Store into transaction
            await pgClient.query(
              `select set_config('jwt.claims.session_id', $1, true)`,
              [details.session_id]
            );
          }

          // Fetch the data that was requested from GraphQL, and return it
          const sql = build.pgSql;
          const [row] = await selectGraphQLResultFromTable(
            sql.fragment`app_public.users`,
            (tableAlias, sqlBuilder) => {
              sqlBuilder.where(
                sql.fragment`${tableAlias}.id = ${sql.value(details.user_id)}`
              );
            }
          );

          const token = await login({ session_id: details.session_id });

          return {
            data: row,
            token,
          };
        } catch (e: any) {
          const { code } = e;

          const safeErrorCodes = [
            "WEAKP",
            "LOCKD",
            "UMTKN",
            "INVLD",
            ...Object.keys(ERROR_MESSAGE_OVERRIDES),
          ];

          if (safeErrorCodes.includes(code)) {
            throw e;
          } else {
            console.error(
              "Unrecognised error in PassportLoginPlugin; replacing with sanitized version"
            );
            console.error(e);
            const error = new Error("Registration failed");
            error["code"] = code;
            throw error;
          }
        }
      },
      async login(_mutation, args, context: OurGraphQLContext, resolveInfo) {
        const { selectGraphQLResultFromTable } = resolveInfo.graphile;
        const { username, password } = args.input;
        const { rootPgPool, login, pgClient } = context;
        try {
          // Call our login function to find out if the username/password combination exists
          const {
            rows: [session],
          } = await rootPgPool.query(
            `select sessions.* from app_private.login($1, $2) sessions where not (sessions is null)`,
            [username, password]
          );

          if (!session) {
            const error = new Error("Incorrect username/password");
            error["code"] = "CREDS";
            throw error;
          }

          // Get session_id from PG
          await pgClient.query(
            `select set_config('jwt.claims.session_id', $1, true)`,
            [session.uuid]
          );

          // Fetch the data that was requested from GraphQL, and return it
          const sql = build.pgSql;
          const [row] = await selectGraphQLResultFromTable(
            sql.fragment`app_public.users`,
            (tableAlias, sqlBuilder) => {
              sqlBuilder.where(
                sql.fragment`${tableAlias}.id = app_public.current_user_id()`
              );
            }
          );
          // Tell Passport.js we're logged in
          const token = await login({ session_id: session.uuid });

          return {
            data: row,
            token,
          };
        } catch (e: any) {
          const { code } = e;
          const safeErrorCodes = ["LOCKD", "CREDS"];
          if (safeErrorCodes.includes(code)) {
            throw e;
          } else {
            console.error(e);
            const error = new Error("Login failed");
            error["code"] = e.code;
            throw error;
          }
        }
      },
      async logout(_mutation, _args, context: OurGraphQLContext, _resolveInfo) {
        const { pgClient, logout } = context;
        await pgClient.query("select app_public.logout();");
        await logout();
        return {
          success: true,
        };
      },
    },
  },
}));

export default PassportLoginPlugin;
