import test from "node:test";
import assert from "node:assert/strict";

import {
  ContractError,
  constantTimeEqual,
  parseAllowEmpty,
  shouldRejectEmptySnapshot,
  validateEmptyOverride,
  validateWorkerPayload,
} from "../supabase/functions/_shared/furry_event_contract.ts";
import { readFile } from "node:fs/promises";

function event(overrides = {}) {
  return {
    source_id: "source-1",
    name: "霜蓝兽聚",
    full_name: "霜蓝兽聚",
    start_at: "2026-08-01T00:00:00+08:00",
    end_at: "2026-08-02T00:00:00+08:00",
    province: "上海",
    city: "长宁",
    address: "上海·长宁",
    venue: null,
    cover: "https://images.example.com/cover.jpg",
    status: "preview",
    source_state: 1,
    source_state_text: "预告",
    source_url: "https://www.furryfusion.net/event/1",
    source_path: "/event/1",
    detail: null,
    organization: "测试组织",
    updated_at: "2026-08-01T00:00:00.000Z",
    ...overrides,
  };
}

test("Edge 只接受完整 Worker 契约", () => {
  const events = validateWorkerPayload({ events: [event()] });
  assert.equal(events.length, 1);
  assert.throws(
    () => validateWorkerPayload({ events: [{ ...event(), unexpected: true }] }),
    error => error instanceof ContractError && error.code === "WORKER_CONTRACT_INVALID",
  );
});

test("Edge 拒绝重复 (name, start_at)，但不把 source_id 当唯一键", () => {
  assert.throws(
    () => validateWorkerPayload({ events: [event(), event({ source_id: "source-2" })] }),
    error => error.code === "WORKER_CONTRACT_INVALID",
  );
  assert.equal(validateWorkerPayload({ events: [
    event(),
    event({
      name: "另一场",
      start_at: "2026-09-01T00:00:00+08:00",
      end_at: "2026-09-02T00:00:00+08:00",
    }),
  ] }).length, 2);
});

test("allow_empty 必须是显式严格布尔值", () => {
  assert.equal(parseAllowEmpty({}), false);
  assert.equal(parseAllowEmpty({ allow_empty: false }), false);
  assert.equal(parseAllowEmpty({ allow_empty: true }), true);
  assert.throws(() => parseAllowEmpty({ allow_empty: "true" }), /boolean/);
});

test("空快照覆盖只允许显式 manual 触发", () => {
  assert.doesNotThrow(() => validateEmptyOverride(false, "scheduled"));
  assert.doesNotThrow(() => validateEmptyOverride(true, "manual"));
  assert.throws(
    () => validateEmptyOverride(true, "scheduled"),
    error => error.code === "SCHEDULED_EMPTY_OVERRIDE_FORBIDDEN",
  );
  assert.throws(
    () => validateEmptyOverride(true, ""),
    error => error.code === "ALLOW_EMPTY_REQUIRES_MANUAL_TRIGGER",
  );
});

test("Edge 空快照预检查在 active 数据存在时拒绝且不调用写入路径", () => {
  assert.equal(shouldRejectEmptySnapshot(0, 26, false), true);
  assert.equal(shouldRejectEmptySnapshot(0, 26, true), false);
  assert.equal(shouldRejectEmptySnapshot(0, 0, false), false);
  assert.equal(shouldRejectEmptySnapshot(26, 26, false), false);
});

test("定时 workflow 固定 scheduled 标记且不发送 allow_empty", async () => {
  const workflow = await readFile(
    new URL("../../Developer/xixi/.github/workflows/fetch-furry-events.yml", import.meta.url),
    "utf8",
  );
  assert.match(workflow, /x-sync-trigger: scheduled/);
  assert.match(workflow, /--data '\{\}'/);
  assert.doesNotMatch(workflow, /allow_empty/i);
});

test("查询函数固定为新来源 active 只读查询", async () => {
  const source = await readFile(
    new URL("../supabase/functions/furry-event-search/index.ts", import.meta.url),
    "utf8",
  );
  assert.match(source, /\.eq\("source", FURRY_EVENT_SOURCE\)/);
  assert.match(source, /\.eq\("is_active", true\)/);
  assert.doesNotMatch(source, /\.insert\(|\.upsert\(|\.update\(|\.delete\(/);
  assert.doesNotMatch(source, /open-meteo|WORKER_URL|weather/i);
});

test("函数密钥比较不接受长度或内容不同的字符串", () => {
  assert.equal(constantTimeEqual("same-secret", "same-secret"), true);
  assert.equal(constantTimeEqual("same-secret", "wrong-secret"), false);
  assert.equal(constantTimeEqual("same-secret", "same-secret-extra"), false);
});
