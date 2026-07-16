const AGENTS = ["codex", "claude", "jimeng", "browser"];

const AGENT_META = {
  codex: {
    name: "Codex",
    role: "工程师",
    label: "CODEX",
    color: "#69c86e",
    initials: "CX",
    art: {
      idle: "/assets/processed/p2_codex/codex_idle_p2.png",
      running: "/assets/processed/p2_codex/codex_running_p2.png",
      needs_input: "/assets/processed/p2_codex/codex_error_p2.png",
      completed: "/assets/processed/p2_codex/codex_completed_p2.png",
      failed: "/assets/processed/p2_codex/codex_error_p2.png"
    }
  },
  claude: {
    name: "Claude",
    role: "策划 / 文档",
    label: "CLAUDE",
    color: "#f29b52",
    initials: "CL",
    art: {
      idle: "/assets/processed/p2_claude/claude_idle_p2.png",
      running: "/assets/processed/p2_claude/claude_running_p2.png",
      needs_input: "/assets/raw/claude-need-input%207.png",
      completed: "/assets/processed/p2_claude/claude_completed_p2.png",
      failed: "/assets/processed/p2_claude/claude_completed_p2.png"
    }
  },
  jimeng: {
    name: "Jimeng",
    role: "艺术家",
    label: "JIMENG",
    color: "#a875ff",
    initials: "JM",
    art: {
      idle: "/assets/processed/p2_jimeng/jimeng_idle_p2.png",
      running: "/assets/processed/p2_jimeng/jimeng_running_p2.png",
      needs_input: "/assets/processed/p2_jimeng/jimeng_idle_p2.png",
      completed: "/assets/processed/p2_jimeng/jimeng_completed_p2.png",
      failed: "/assets/processed/p2_jimeng/jimeng_idle_p2.png"
    }
  },
  browser: {
    name: "Browser Agent",
    role: "研究侦探",
    label: "BROWSER",
    color: "#61b7ff",
    initials: "BR",
    art: {
      idle: "/assets/raw/browser_working_01.png",
      running: "/assets/raw/browser_working_02.png",
      needs_input: "/assets/raw/browser_working_01.png",
      completed: "/assets/raw/browser_working_01.png",
      failed: "/assets/raw/browser_working_02.png"
    }
  }
};

const STATUS_COPY = {
  idle: "Idle",
  running: "Working",
  needs_input: "Input required",
  completed: "Done",
  failed: "Error"
};

const els = Object.fromEntries([
  "agentList", "activeCount", "queueList", "agentSelect", "scenarioSelect", "promptInput",
  "voiceButton", "voiceState", "sendButton", "bridgeStatus", "serialStatus", "dockScreen",
  "dockAgentName", "dockSignal", "dockAgentArt", "dockPrimary", "dockTaskTitle", "dockAlert",
  "dockProgress", "dockProgressFill", "dockProgressLabel", "pageDots", "prevAgent", "nextAgent",
  "eventLog", "eventCount", "toast"
].map((id) => [id, document.getElementById(id)]));

let bridgeState = {
  currentAgent: "codex",
  tasksByAgent: Object.fromEntries(AGENTS.map((agent) => [agent, null])),
  transport: "mock-serial",
  eventLog: []
};
let selectedAgent = "codex";
let socket = null;
let eventSource = null;
let recognition = null;
let listening = false;
let lastStatuses = {};
let toastTimer = null;
let swipeStartX = 0;

function normalizeStatus(status = "idle") {
  if (status === "done") return "completed";
  if (status === "working" || status === "thinking" || status === "queued") return "running";
  if (status === "input_required") return "needs_input";
  if (status === "error") return "failed";
  return STATUS_COPY[status] ? status : "idle";
}

function taskFor(agent) {
  const task = bridgeState.tasksByAgent?.[agent];
  if (task) return { ...task, status: normalizeStatus(task.status) };
  return {
    source: agent,
    agentName: AGENT_META[agent].name,
    title: `${AGENT_META[agent].name} 待命中`,
    status: "idle",
    statusText: "等待新任务",
    progress: -1,
    taskType: AGENT_META[agent].role
  };
}

function escapeHtml(value = "") {
  return String(value).replace(/[&<>'"]/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;"
  })[char]);
}

function statusLabel(task) {
  return STATUS_COPY[normalizeStatus(task.status)] || "Idle";
}

function setSelectedAgent(agent, { sync = true } = {}) {
  if (!AGENTS.includes(agent)) return;
  selectedAgent = agent;
  els.agentSelect.value = agent;
  render();
  if (sync) api("/api/switch-agent", { agent }).catch(() => {});
}

function renderAgentList() {
  const active = AGENTS.filter((agent) => !["idle", "completed"].includes(taskFor(agent).status)).length;
  els.activeCount.textContent = `${active} active`;
  els.agentList.innerHTML = AGENTS.map((agent) => {
    const meta = AGENT_META[agent];
    const task = taskFor(agent);
    const status = normalizeStatus(task.status);
    return `
      <button class="agent-card ${agent === selectedAgent ? "active" : ""}" data-agent="${agent}" style="--card-agent:${meta.color}">
        <img class="agent-avatar" src="${meta.art[status] || meta.art.idle}" alt="" />
        <span class="agent-copy"><b>${meta.name}</b><span>${escapeHtml(task.statusText || meta.role)}</span></span>
        <i class="status-mini ${status}" title="${statusLabel(task)}"></i>
      </button>`;
  }).join("");
  els.agentList.querySelectorAll("[data-agent]").forEach((button) => {
    button.addEventListener("click", () => setSelectedAgent(button.dataset.agent));
  });
}

function renderQueue() {
  els.queueList.innerHTML = AGENTS.map((agent, index) => {
    const meta = AGENT_META[agent];
    const task = taskFor(agent);
    const status = normalizeStatus(task.status);
    const progress = Number.isFinite(task.progress) && task.progress >= 0 ? Math.min(100, task.progress) : 0;
    return `
      <article class="task-row" data-agent="${agent}" style="--row-agent:${meta.color}">
        <span class="task-index">0${index + 1}</span>
        <span class="task-info">
          <b>${meta.name}</b><small>${statusLabel(task)}</small>
          <span>${escapeHtml(task.title || task.statusText || "等待新任务")}</span>
        </span>
        <span class="task-progress" title="${progress}%"><i style="width:${progress}%"></i></span>
      </article>`;
  }).join("");
  els.queueList.querySelectorAll("[data-agent]").forEach((row) => {
    row.addEventListener("click", () => setSelectedAgent(row.dataset.agent));
  });
}

function renderDock() {
  const meta = AGENT_META[selectedAgent];
  const task = taskFor(selectedAgent);
  const status = normalizeStatus(task.status);
  const progress = Number.isFinite(task.progress) && task.progress >= 0 ? Math.min(100, task.progress) : 0;
  els.dockScreen.style.setProperty("--agent", meta.color);
  els.dockScreen.dataset.status = status;
  els.dockAgentName.textContent = meta.label;
  els.dockSignal.className = `status-signal ${status}`;
  els.dockAgentArt.src = meta.art[status] || meta.art.idle;
  els.dockAgentArt.alt = `${meta.name} 像素角色 · ${statusLabel(task)}`;
  els.dockPrimary.textContent = statusLabel(task);
  els.dockTaskTitle.textContent = task.statusText || task.title || "等待新任务";
  els.dockAlert.textContent = status === "needs_input" ? "老板，需要你看一下" : status === "failed" ? "遇到问题，点我重试" : "老板，我做好啦";
  els.dockProgressFill.style.width = `${progress}%`;
  els.dockProgressLabel.textContent = `${progress}%`;
  els.pageDots.innerHTML = AGENTS.map((agent) => `<i class="${agent === selectedAgent ? "active" : ""}"></i>`).join("");
}

function renderEvents() {
  const logs = (bridgeState.eventLog || []).slice(-8).reverse();
  els.eventCount.textContent = `${bridgeState.eventLog?.length || 0} events`;
  els.eventLog.innerHTML = logs.length ? logs.map((entry) => {
    const time = entry.at ? new Date(entry.at).toLocaleTimeString("zh-CN", { hour12: false, minute: "2-digit", second: "2-digit" }) : "--:--";
    return `<li><time>${time}</time><b>${escapeHtml(entry.source || "system")}</b><span>${escapeHtml(entry.status || entry.type || "event")}</span></li>`;
  }).join("") : "<li><time>--:--</time><b>bridge</b><span>waiting for events</span></li>";
}

function render() {
  renderAgentList();
  renderQueue();
  renderDock();
  renderEvents();
  const transport = bridgeState.transport || "mock-serial";
  els.serialStatus.className = `connection-pill ${transport === "usb-serial" ? "" : "muted"}`;
  els.serialStatus.innerHTML = `<i></i> ${transport === "usb-serial" ? "USB serial" : "Mock serial"}`;
}

function notify(message) {
  els.toast.textContent = message;
  els.toast.classList.add("visible");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => els.toast.classList.remove("visible"), 3200);
}

function applyState(nextState) {
  for (const agent of AGENTS) {
    const nextStatus = normalizeStatus(nextState.tasksByAgent?.[agent]?.status || "idle");
    if (lastStatuses[agent] && lastStatuses[agent] !== "completed" && nextStatus === "completed") {
      notify(`${AGENT_META[agent].name}：老板，我做好啦`);
    }
    lastStatuses[agent] = nextStatus;
  }
  bridgeState = { ...bridgeState, ...nextState };
  render();
}

function handleBridgeEvent(event) {
  if (event.type === "state" && event.state) applyState(event.state);
  if (event.type === "serial_status") {
    bridgeState.transport = event.transport || (event.connected ? "usb-serial" : "mock-serial");
    render();
  }
}

function markConnected(connected, label = "WebSocket") {
  els.bridgeStatus.className = `connection-pill ${connected ? "" : "offline"}`;
  els.bridgeStatus.innerHTML = `<i></i> ${connected ? `${label} live` : "Bridge offline"}`;
}

function connectSseFallback() {
  if (eventSource) return;
  eventSource = new EventSource("/events");
  eventSource.onopen = () => markConnected(true, "SSE");
  eventSource.onmessage = (message) => {
    try { handleBridgeEvent(JSON.parse(message.data)); } catch {}
  };
  eventSource.onerror = () => markConnected(false);
}

function connectBridge() {
  const protocol = location.protocol === "https:" ? "wss:" : "ws:";
  socket = new WebSocket(`${protocol}//${location.host}/ws`);
  const fallbackTimer = setTimeout(() => {
    if (!socket || socket.readyState !== WebSocket.OPEN) connectSseFallback();
  }, 1400);
  socket.onopen = () => {
    clearTimeout(fallbackTimer);
    markConnected(true);
    if (eventSource) { eventSource.close(); eventSource = null; }
  };
  socket.onmessage = (message) => {
    try { handleBridgeEvent(JSON.parse(message.data)); } catch {}
  };
  socket.onerror = () => connectSseFallback();
  socket.onclose = () => {
    markConnected(false);
    connectSseFallback();
    setTimeout(connectBridge, 2600);
  };
}

async function api(path, body = {}) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  const data = await response.json();
  if (!response.ok || !data.ok) throw new Error(data.error || `Request failed: ${response.status}`);
  if (data.state) applyState(data.state);
  return data;
}

async function sendTask() {
  const prompt = els.promptInput.value.trim();
  if (!prompt) {
    els.promptInput.focus();
    notify("先说点什么，或输入一条任务");
    return;
  }
  const agent = els.agentSelect.value;
  setSelectedAgent(agent, { sync: false });
  els.sendButton.disabled = true;
  els.sendButton.firstChild.textContent = "发送中 ";
  try {
    await api("/api/send-task", { prompt, agent, scenario: els.scenarioSelect.value });
    notify(`任务已发送给 ${AGENT_META[agent].name}`);
  } catch (error) {
    notify(`发送失败：${error.message}`);
  } finally {
    els.sendButton.disabled = false;
    els.sendButton.firstChild.textContent = "发送任务 ";
  }
}

function finishVoiceUi(message = "转写完成，可继续编辑后发送") {
  listening = false;
  document.querySelector(".composer")?.classList.remove("recording");
  els.voiceButton.classList.remove("recording");
  els.voiceButton.setAttribute("aria-pressed", "false");
  els.voiceButton.querySelector("b").textContent = "按下说话";
  els.voiceState.textContent = message;
}

function setupVoice() {
  const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!Recognition) {
    els.voiceState.textContent = "当前浏览器不支持语音转写，请使用文字输入";
    els.voiceButton.addEventListener("click", () => notify("建议使用 Chrome 打开，以启用浏览器语音转写"));
    return;
  }
  recognition = new Recognition();
  recognition.lang = "zh-CN";
  recognition.continuous = false;
  recognition.interimResults = true;
  let finalTranscript = "";
  recognition.onstart = () => {
    listening = true;
    finalTranscript = "";
    document.querySelector(".composer")?.classList.add("recording");
    els.voiceButton.classList.add("recording");
    els.voiceButton.setAttribute("aria-pressed", "true");
    els.voiceButton.querySelector("b").textContent = "正在听…";
    els.voiceState.textContent = "录音中 · 再点一次结束";
  };
  recognition.onresult = (event) => {
    let interim = "";
    for (let index = event.resultIndex; index < event.results.length; index += 1) {
      const text = event.results[index][0].transcript;
      if (event.results[index].isFinal) finalTranscript += text;
      else interim += text;
    }
    const transcript = (finalTranscript || interim).trim();
    if (transcript) els.promptInput.value = transcript.slice(0, 140);
    els.voiceState.textContent = interim ? `正在转写：${interim}` : "转写完成，可继续编辑后发送";
  };
  recognition.onerror = (event) => finishVoiceUi(event.error === "not-allowed" ? "麦克风权限未开启，请使用文字输入" : "语音识别未完成，请重试或使用文字输入");
  recognition.onend = () => finishVoiceUi();
  els.voiceButton.addEventListener("click", () => {
    if (listening) recognition.stop();
    else {
      els.voiceState.textContent = "正在请求麦克风…";
      try { recognition.start(); } catch { finishVoiceUi("语音服务正忙，请稍后重试"); }
    }
  });
}

function cycleAgent(direction) {
  const current = AGENTS.indexOf(selectedAgent);
  setSelectedAgent(AGENTS[(current + direction + AGENTS.length) % AGENTS.length]);
}

els.sendButton.addEventListener("click", sendTask);
els.promptInput.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") sendTask();
});
els.prevAgent.addEventListener("click", () => cycleAgent(-1));
els.nextAgent.addEventListener("click", () => cycleAgent(1));
els.dockScreen.addEventListener("pointerdown", (event) => { swipeStartX = event.clientX; });
els.dockScreen.addEventListener("pointerup", (event) => {
  const delta = event.clientX - swipeStartX;
  if (Math.abs(delta) > 32) cycleAgent(delta < 0 ? 1 : -1);
});
els.dockScreen.addEventListener("keydown", (event) => {
  if (event.key === "ArrowLeft") cycleAgent(-1);
  if (event.key === "ArrowRight") cycleAgent(1);
});
document.querySelectorAll("[data-demo]").forEach((button) => {
  button.addEventListener("click", async () => {
    try {
      await api(`/api/demo/${button.dataset.demo}`);
      notify(button.dataset.demo === "seed" ? "四 Agent 演示场景已装载" : "所有 Agent 已回到待命状态");
    } catch (error) { notify(error.message); }
  });
});
document.querySelectorAll("[data-status]").forEach((button) => {
  button.addEventListener("click", async () => {
    try { await api("/api/task-status", { agent: selectedAgent, status: button.dataset.status }); }
    catch (error) { notify(error.message); }
  });
});

setupVoice();
render();
connectBridge();
fetch("/api/state").then((response) => response.json()).then((data) => data.state && applyState(data.state)).catch(() => {});
