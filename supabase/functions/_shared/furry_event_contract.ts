export const FURRY_EVENT_SOURCE = "furfantasia_event_data";

export const FURRY_EVENT_FIELDS = Object.freeze([
  "source_id",
  "name",
  "full_name",
  "start_at",
  "end_at",
  "province",
  "city",
  "address",
  "venue",
  "cover",
  "status",
  "source_state",
  "source_state_text",
  "source_url",
  "source_path",
  "detail",
  "organization",
  "updated_at",
] as const);

export type FurryEvent = {
  source_id: string;
  name: string;
  full_name: string;
  start_at: string;
  end_at: string;
  province: string | null;
  city: string | null;
  address: string | null;
  venue: string | null;
  cover: string | null;
  status: "preview" | "confirmed" | null;
  source_state: number | null;
  source_state_text: string | null;
  source_url: string | null;
  source_path: string | null;
  detail: string | null;
  organization: string | null;
  updated_at: string;
};

export class ContractError extends Error {
  code: string;
  details: Record<string, unknown>;

  constructor(code: string, message: string, details: Record<string, unknown> = {}) {
    super(message);
    this.name = "ContractError";
    this.code = code;
    this.details = details;
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function validHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

function validateEvent(raw: unknown, index: number): FurryEvent {
  if (!isObject(raw)) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event must be an object", { index });
  }
  const keys = Object.keys(raw).sort();
  const expectedKeys = [...FURRY_EVENT_FIELDS].sort();
  if (keys.length !== expectedKeys.length || keys.some((key, i) => key !== expectedKeys[i])) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event fields do not match the public contract", {
      index,
      fields: keys,
    });
  }

  for (const key of ["source_id", "name", "full_name", "start_at", "end_at", "updated_at"] as const) {
    if (typeof raw[key] !== "string" || raw[key].trim() === "") {
      throw new ContractError("WORKER_CONTRACT_INVALID", `Worker event has invalid ${key}`, { index });
    }
  }
  for (const key of [
    "province", "city", "address", "venue", "cover", "source_state_text",
    "source_url", "source_path", "detail", "organization",
  ] as const) {
    if (!isNullableString(raw[key])) {
      throw new ContractError("WORKER_CONTRACT_INVALID", `Worker event has invalid ${key}`, { index });
    }
  }
  if (raw.status !== null && raw.status !== "preview" && raw.status !== "confirmed") {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event has invalid status", { index });
  }
  if (raw.source_state !== null && !Number.isInteger(raw.source_state)) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event has invalid source_state", { index });
  }
  const datePattern = /^\d{4}-\d{2}-\d{2}T00:00:00\+08:00$/;
  if (!datePattern.test(raw.start_at as string) || !datePattern.test(raw.end_at as string)) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event has invalid date format", { index });
  }
  if (Number.isNaN(Date.parse(raw.start_at as string)) || Number.isNaN(Date.parse(raw.end_at as string))) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event has an invalid date", { index });
  }
  if (Date.parse(raw.end_at as string) < Date.parse(raw.start_at as string)) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event ends before it starts", { index });
  }
  if (Number.isNaN(Date.parse(raw.updated_at as string))) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event has invalid updated_at", { index });
  }
  if (typeof raw.cover === "string" && !validHttpUrl(raw.cover)) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event has invalid cover", { index });
  }
  if (typeof raw.source_url === "string" && !validHttpUrl(raw.source_url)) {
    throw new ContractError("WORKER_CONTRACT_INVALID", "Worker event has invalid source_url", { index });
  }
  return raw as FurryEvent;
}

export function validateWorkerPayload(payload: unknown): FurryEvent[] {
  if (!isObject(payload) || Object.keys(payload).length !== 1 || !Array.isArray(payload.events)) {
    throw new ContractError(
      "WORKER_CONTRACT_INVALID",
      "Worker response must be exactly { events: [] }",
    );
  }
  const events = payload.events.map(validateEvent);
  const seen = new Set<string>();
  for (const [index, event] of events.entries()) {
    const key = `${event.name}\u0000${event.start_at}`;
    if (seen.has(key)) {
      throw new ContractError(
        "WORKER_CONTRACT_INVALID",
        "Worker response contains duplicate (name, start_at)",
        { index, name: event.name, start_at: event.start_at },
      );
    }
    seen.add(key);
  }
  return events;
}

export function parseAllowEmpty(payload: unknown): boolean {
  if (payload == null) return false;
  if (!isObject(payload)) {
    throw new ContractError("INVALID_REQUEST", "Request body must be a JSON object");
  }
  if (!("allow_empty" in payload)) return false;
  if (typeof payload.allow_empty !== "boolean") {
    throw new ContractError("INVALID_REQUEST", "allow_empty must be a boolean");
  }
  return payload.allow_empty;
}

export function validateEmptyOverride(allowEmpty: boolean, trigger: string): void {
  const normalizedTrigger = trigger.trim().toLowerCase();
  if (normalizedTrigger === "scheduled" && allowEmpty) {
    throw new ContractError(
      "SCHEDULED_EMPTY_OVERRIDE_FORBIDDEN",
      "Scheduled syncs cannot override empty snapshot protection",
    );
  }
  if (allowEmpty && normalizedTrigger !== "manual") {
    throw new ContractError(
      "ALLOW_EMPTY_REQUIRES_MANUAL_TRIGGER",
      "allow_empty=true is only accepted for an authenticated manual sync",
    );
  }
}

export function shouldRejectEmptySnapshot(
  eventCount: number,
  activeCount: number,
  allowEmpty: boolean,
): boolean {
  return eventCount === 0 && activeCount > 0 && !allowEmpty;
}

export function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  const length = Math.max(a.length, b.length, 1);
  let difference = a.length ^ b.length;
  for (let index = 0; index < length; index += 1) {
    difference |= (a[index] ?? 0) ^ (b[index] ?? 0);
  }
  return difference === 0;
}
