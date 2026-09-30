import { handleAppleSignIn, handleDevSignIn, handleRefresh } from "./auth";
import type { Env } from "./env";
import { ApiError, errorResponse, json } from "./errors";
import { handleGenerate } from "./generate";
import { handleMe } from "./me";

export type { Env };

type Handler = (request: Request, env: Env, ctx: ExecutionContext) => Promise<Response>;

const routes: Record<string, Handler> = {
  "POST /v1/auth/apple": handleAppleSignIn,
  "POST /v1/auth/dev": handleDevSignIn,
  "POST /v1/auth/refresh": handleRefresh,
  "GET /v1/me": handleMe,
  "POST /v1/generate": handleGenerate,
  "GET /v1/health": async () => json({ ok: true }),
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const handler = routes[`${request.method} ${url.pathname}`];
    try {
      if (!handler) throw new ApiError("not_found");
      return await handler(request, env, ctx);
    } catch (err) {
      return errorResponse(err);
    }
  },
} satisfies ExportedHandler<Env>;
