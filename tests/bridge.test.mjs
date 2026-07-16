import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { after, before, test } from "node:test";
import { WebSocket } from "ws";

const port = 4197;
const baseUrl = `http://127.0.0.1:${port}`;
let bridge;

async function waitForBridge() {
  for (let attempt = 0; attempt < 80; attempt += 1) {
    try {
      const response = await fetch(`${baseUrl}/api/state`);
      if (response.ok) return;
    } catch {
      // The child process is still starting.
    }
    await new Promise((resolve) => setTimeout(resolve, 75));
  }
  throw new Error("PeekDock bridge did not start");
}

async function post(path, body = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  const json = await response.json();
  assert.equal(response.ok, true, JSON.stringify(json));
  return json;
}

before(async () => {
  bridge = spawn(process.execPath, ["runtime-bridge/server.mjs"], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(port),
      PEEKDOCK_HEADLESS: "1",
      PEEKDOCK_SOUNDS: "0",
      PEEKDOCK_REAL_MONITORS: "0",
      PEEKDOCK_SERIAL_PORT: "/tmp/peekdock-test-mock-serial"
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  await waitForBridge();
});

after(() => {
  bridge?.kill("SIGTERM");
});

test("serves the console and initializes four idle agents", async () => {
  const page = await fetch(baseUrl);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /PeekDock/);

  const response = await fetch(`${baseUrl}/api/state`);
  const { state } = await response.json();
  assert.deepEqual(state.agentOrder, ["codex", "claude", "jimeng", "browser"]);
  assert.equal(state.transport, "mock-serial");
  assert.equal(Object.values(state.tasksByAgent).every((task) => task.status === "idle"), true);
});

test("seed scenario exposes all competition-demo states", async () => {
  const { state } = await post("/api/demo/seed");
  assert.equal(state.tasksByAgent.codex.status, "running");
  assert.equal(state.tasksByAgent.claude.status, "needs_input");
  assert.equal(state.tasksByAgent.jimeng.status, "completed");
  assert.equal(state.tasksByAgent.browser.status, "running");
  assert.equal(state.tasksByAgent.jimeng.statusText, "老板，我做好啦");
});

test("task API moves a selected agent through input-required and done", async () => {
  await post("/api/demo/reset");
  const sent = await post("/api/send-task", {
    agent: "codex",
    prompt: "检查首页按钮并给出修改建议",
    scenario: "input_required"
  });
  assert.equal(sent.state.currentAgent, "codex");
  assert.equal(sent.state.tasksByAgent.codex.status, "running");

  await new Promise((resolve) => setTimeout(resolve, 3650));
  const waiting = await (await fetch(`${baseUrl}/api/state`)).json();
  assert.equal(waiting.state.tasksByAgent.codex.status, "needs_input");

  const done = await post("/api/task-status", {
    agent: "codex",
    status: "completed"
  });
  assert.equal(done.task.status, "completed");
  assert.equal(done.task.statusText, "老板，我做好啦");
  assert.equal(done.task.progress, 100);
});

test("WebSocket sends an authoritative initial state", async () => {
  const event = await new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    const timeout = setTimeout(() => reject(new Error("WebSocket timeout")), 2000);
    socket.on("message", (data) => {
      const parsed = JSON.parse(String(data));
      if (parsed.type !== "state") return;
      clearTimeout(timeout);
      socket.close();
      resolve(parsed);
    });
    socket.on("error", reject);
  });
  assert.equal(event.state.agentOrder.length, 4);
});
