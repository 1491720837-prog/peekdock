import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { test } from "node:test";
import { WebSocket } from "ws";

const port = 4199;
const baseUrl = `http://127.0.0.1:${port}`;

async function waitForServer(child) {
  const deadline = Date.now() + 10_000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error(`Bridge exited with ${child.exitCode}`);
    try {
      const response = await fetch(`${baseUrl}/api/state`);
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Timed out waiting for PeekDock bridge");
}

async function post(path, body = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  return { response, json: await response.json() };
}

test("runtime bridge serves the demo and drives all four agents", async (t) => {
  const child = spawn(process.execPath, ["runtime-bridge/server.mjs"], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      PORT: String(port),
      PEEKDOCK_HEADLESS: "0",
      PEEKDOCK_SOUNDS: "0",
      PEEKDOCK_REAL_MONITORS: "0",
      PEEKDOCK_SERIAL_PORT: "/tmp/peekdock-test-serial-does-not-exist"
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  let output = "";
  child.stdout.on("data", (chunk) => { output += chunk; });
  child.stderr.on("data", (chunk) => { output += chunk; });
  t.after(async () => {
    if (child.exitCode === null) {
      child.kill("SIGTERM");
      await Promise.race([once(child, "exit"), new Promise((resolve) => setTimeout(resolve, 2_000))]);
    }
  });

  await waitForServer(child);

  const page = await fetch(`${baseUrl}/`);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /PeekDock/);

  const initial = await (await fetch(`${baseUrl}/api/state`)).json();
  assert.deepEqual(initial.state.agentOrder, ["codex", "claude", "jimeng", "browser"]);
  assert.equal(initial.state.transport, "mock-serial");
  assert.ok(Object.values(initial.state.tasksByAgent).every((task) => task.status === "idle"));

  const socket = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  const [socketMessage] = await once(socket, "message");
  assert.equal(JSON.parse(socketMessage.toString()).type, "state");
  socket.close();

  const seeded = await post("/api/demo/seed");
  assert.equal(seeded.response.status, 200);
  assert.equal(Object.keys(seeded.json.state.tasksByAgent).length, 4);
  assert.equal(seeded.json.state.tasksByAgent.claude.status, "needs_input");
  assert.equal(seeded.json.state.tasksByAgent.jimeng.status, "completed");

  await post("/api/demo/reset");
  const sent = await post("/api/send-task", {
    agent: "codex",
    prompt: "Build a launch checklist",
    scenario: "done"
  });
  assert.equal(sent.response.status, 200, output);
  assert.equal(sent.json.state.tasksByAgent.codex.status, "running");

  const completed = await post("/api/task-status", {
    agent: "codex",
    status: "completed",
    statusText: "老板，我做好啦",
    progress: 100
  });
  assert.equal(completed.json.task.status, "completed");
  assert.equal(completed.json.task.progress, 100);
  assert.equal(completed.json.state.currentAgent, "codex");

  const traversal = await fetch(`${baseUrl}/%2e%2e/package.json`);
  assert.equal(traversal.status, 404);
});
