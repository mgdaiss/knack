export type ErrorCode =
  | "bad_request"
  | "unauthorized"
  | "not_found"
  | "unknown_skill"
  | "tier_not_allowed"
  | "out_of_credit"
  | "daily_limit"
  | "rate_limited"
  | "model_unavailable"
  | "internal";

const STATUS: Record<ErrorCode, number> = {
  bad_request: 400,
  unauthorized: 401,
  not_found: 404,
  unknown_skill: 400,
  tier_not_allowed: 403,
  out_of_credit: 402,
  daily_limit: 429,
  rate_limited: 429,
  model_unavailable: 503,
  internal: 500,
};

// Plain, friendly defaults. The app maps codes to each character's voice.
const MESSAGE: Record<ErrorCode, string> = {
  bad_request: "That request didn't look right.",
  unauthorized: "Please sign in again.",
  not_found: "Nothing here.",
  unknown_skill: "That helper isn't available.",
  tier_not_allowed: "That helper can't use that kind of model.",
  out_of_credit: "You're out of credit.",
  daily_limit: "That's a lot of helping for one day. Try again tomorrow.",
  rate_limited: "Slow down a little and try again in a minute.",
  model_unavailable: "The helper's brain is taking a break. Try again shortly.",
  internal: "Something went wrong on our side.",
};

export class ApiError extends Error {
  constructor(public code: ErrorCode, message?: string) {
    super(message ?? MESSAGE[code]);
  }
  get status(): number {
    return STATUS[this.code];
  }
}

export function errorBody(code: ErrorCode, message?: string) {
  return { error: { code, message: message ?? MESSAGE[code] } };
}

export function errorResponse(err: unknown): Response {
  if (err instanceof ApiError) {
    return json(errorBody(err.code, err.message), err.status);
  }
  console.error("unhandled error", err instanceof Error ? err.message : "unknown");
  return json(errorBody("internal"), 500);
}

export function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}
