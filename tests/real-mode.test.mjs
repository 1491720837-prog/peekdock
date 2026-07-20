import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { test } from "node:test";

const port = 4198;
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
  throw new Error("Timed out waiting for real-mode bridge");
}

test("real mode uses desktop overlay and accepts normalized Agent events", async (t) => {
  const child = spawn(process.execPath, ["runtime-bridge/server.mjs"], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(port),
      PEEKDOCK_HEADLESS: "1",
      PEEKDOCK_SOUNDS: "0",
      PEEKDOCK_REAL_MONITORS: "1",
      PEEKDOCK_BROWSER: "safari",
      PEEKDOCK_CODEX_SESSIONS_DIR: "/tmp/peekdock-no-codex-sessions",
      PEEKDOCK_CLAUDE_PROJECTS_DIR: "/tmp/peekdock-no-claude-sessions",
      PEEKDOCK_SERIAL_PORT: "/tmp/peekdock-no-real-serial"
    },
    stdio: ["ignore", "pipe", "pipe"]
  });
  t.after(async () => {
    if (child.exitCode === null) {
      child.kill("SIGTERM");
      await Promise.race([once(child, "exit"), new Promise((resolve) => setTimeout(resolve, 2_000))]);
    }
  });

  await waitForServer(child);
  const initial = await (await fetch(`${baseUrl}/api/state`)).json();
  assert.equal(initial.state.dataMode, "real");
  assert.equal(initial.state.transport, "desktop-overlay");
  assert.equal(initial.state.displayTarget, "desktop-overlay");

  const ingested = await fetch(`${baseUrl}/api/ingest`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      agent: "browser",
      taskId: "browser-real-1",
      title: "Research real sources",
      status: "completed",
      statusText: "真实检索已完成",
      progress: 100,
      resultUri: "https://example.com/result"
    })
  });
  assert.equal(ingested.status, 200);
  const { state } = await ingested.json();
  assert.equal(state.tasksByAgent.browser.taskId, "browser-real-1");
  assert.equal(state.tasksByAgent.browser.status, "completed");
  assert.equal(state.adapterHealth.browser.state, "connected");

  const approval = await fetch(`${baseUrl}/api/codex-test-event`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ simulateApproval: true })
  });
  assert.equal(approval.status, 200);
  const approvalPayload = await approval.json();
  assert.equal(approvalPayload.state.tasksByAgent.codex.status, "needs_input");
  assert.equal(approvalPayload.state.tasksByAgent.codex.statusText, "review");

  const invalidAction = await fetch(`${baseUrl}/api/agent-action`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ agent: "codex", action: "not-supported" })
  });
  assert.equal(invalidAction.status, 400);
});
