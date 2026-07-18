"""idfc-coder UI — Textual reimplementation.

A ground-up rewrite of the interactive session UI on top of the **Textual**
framework (https://textual.textualize.io). It is functionally equivalent to the
prior ``agentic_tui``/prompt_toolkit adapter — same agent-event handling, the
same PLAN/EXECUTE phases, todos, activity feed, slash commands, feedback/rating,
and session save/restore — but the presentation layer is entirely new:

  - A persistent app chrome: brand bar, conversation transcript, a context
    side-rail (phase + context gauge + live activity feed + todo tracker), a
    multi-line composer, and a status footer.
  - Live agent progress renders in a dedicated "now" line above the composer
    (spinner / thinking tail / current tool / retry) instead of an ephemeral.
  - Categorised agent activity streams into the side-rail feed.

Integration surface is unchanged: construct ``IDFCUI(agent, todo_manager, ...)``
and ``await .run()`` exactly as before. Internally that now boots a Textual
``App``.

Requires: ``textual`` (``pip install textual``), plus the existing
``idfc_coder`` package + ``langchain_core``.

Agent events → UI:
  - token       → grows the live "thinking" tail; final answer commits to transcript
  - tool_start  → live "now" line shows ``name (arg)`` + bumps tool counter
  - tool_end    → live line reverts to thinking
  - retry       → live line shows ``retrying N/M``
  - activity    → categorised event appended to the side-rail feed
  - error       → committed error panel in the transcript
  - plan_ready  → stored as ``last_plan``; enables Tab/Ctrl+Y approve
  - done        → finalize; commit answer + todo snapshot + per-turn stats
"""
from __future__ import annotations

import asyncio
import json
import logging
import re
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Optional

from langchain_core.messages import HumanMessage
from rich.console import Group
from rich.markdown import Markdown
from rich.panel import Panel
from rich.rule import Rule
from rich.text import Text

from textual import events, on
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.message import Message
from textual.reactive import reactive
from textual.widgets import Label, RichLog, Static, TextArea

from idfc_coder.agent import (
    EXECUTE_SYSTEM_PROMPT,
    PLAN_SYSTEM_PROMPT,
    CodingAgent,
    Phase,
)
from idfc_coder.todo import TodoItem, TodoManager, TodoStatus

logger = logging.getLogger("idfc_coder.ui")


# ======================================================================
# Design tokens — a fresh palette (not derived from the old UI).
# ======================================================================

BRAND = "#9b6bff"          # violet — product brand
BRAND_SOFT = "#c4a8ff"
PLAN_HUE = "#38bdf8"       # cyan — PLAN phase
EXEC_HUE = "#34d399"       # green — EXECUTE phase
WARN_HUE = "#fbbf24"
ERR_HUE = "#fb7185"
INK = "#e6e8ef"
MUTED = "#8a90a6"
FAINT = "#5b6178"

_SPINNER_FRAMES = ("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")


def phase_hue(phase: "Phase") -> str:
    return PLAN_HUE if phase == Phase.PLAN else EXEC_HUE


# ======================================================================
# Activity feed model (categorised agent progress)
# ======================================================================


class ActivityCategory(str, Enum):
    ANALYSIS = "analysis"
    PLANNING = "planning"
    MODIFICATION = "modification"
    VALIDATION = "validation"
    COMPLETION = "completion"


_ACTIVITY_GLYPH: dict[ActivityCategory, str] = {
    ActivityCategory.ANALYSIS: "◈",
    ActivityCategory.PLANNING: "◇",
    ActivityCategory.MODIFICATION: "◆",
    ActivityCategory.VALIDATION: "✓",
    ActivityCategory.COMPLETION: "●",
}

_ACTIVITY_COLOR: dict[ActivityCategory, str] = {
    ActivityCategory.ANALYSIS: PLAN_HUE,
    ActivityCategory.PLANNING: BRAND_SOFT,
    ActivityCategory.MODIFICATION: EXEC_HUE,
    ActivityCategory.VALIDATION: "#60a5fa",
    ActivityCategory.COMPLETION: INK,
}


@dataclass
class ActivityEvent:
    timestamp: datetime
    category: ActivityCategory
    message: str
    detail: str = ""


# ======================================================================
# Side-rail widgets
# ======================================================================


class PhaseCard(Static):
    """Top of the side-rail: phase pill, model, connectivity badges."""

    def render_state(
        self,
        *,
        phase: Phase,
        model_label: str,
        jira: bool,
        gocd: bool,
        update_available: str | None,
    ) -> None:
        hue = phase_hue(phase)
        name = "PLAN" if phase == Phase.PLAN else "EXECUTE"
        lines: list[Text] = []
        lines.append(
            Text.assemble(
                (f"  {name}  ", f"bold black on {hue}"),
                ("  mode", f"{MUTED}"),
            )
        )
        lines.append(Text.assemble(("⚙ ", BRAND), (model_label, INK)))
        jira_t = ("● Jira", EXEC_HUE) if jira else ("○ Jira", FAINT)
        gocd_t = ("● GoCD", EXEC_HUE) if gocd else ("○ GoCD", FAINT)
        lines.append(Text.assemble(jira_t, ("   ", ""), gocd_t))
        if update_available:
            lines.append(Text(f"⬆ update → {update_available}", style=WARN_HUE))
        self.update(Group(*lines))


class ContextGauge(Static):
    """Context-window usage bar."""

    def render_state(self, used: int, limit: int) -> None:
        pct = int(used / limit * 100) if limit else 0
        if pct >= 75:
            hue = ERR_HUE
        elif pct >= 50:
            hue = WARN_HUE
        else:
            hue = EXEC_HUE
        width = 22
        filled = min(width, int(width * pct / 100))
        bar = Text()
        bar.append("█" * filled, style=hue)
        bar.append("░" * (width - filled), style=FAINT)
        head = Text.assemble(
            ("context  ", MUTED),
            (f"{used // 1000}K", INK),
            (f" / {limit // 1000}K  ", MUTED),
            (f"{pct}%", hue),
        )
        self.update(Group(head, bar))


class ActivityFeed(Static):
    """Scrolling list of categorised activity events for the current turn."""

    MAX = 7

    def __init__(self, **kw: Any) -> None:
        super().__init__(**kw)
        self._events: list[ActivityEvent] = []

    def begin(self) -> None:
        self._events = []
        self._render()

    def add(self, category: ActivityCategory, message: str, detail: str = "") -> None:
        self._events.append(
            ActivityEvent(datetime.now(), category, message, detail)
        )
        self._render()

    def clear_feed(self) -> None:
        self._events = []
        self._render()

    def _render(self) -> None:
        if not self._events:
            self.update(Text("idle", style=FAINT))
            return
        lines: list[Text] = []
        for ev in self._events[-self.MAX :]:
            color = _ACTIVITY_COLOR.get(ev.category, INK)
            glyph = _ACTIVITY_GLYPH.get(ev.category, "•")
            line = Text.assemble(
                (f"{glyph} ", color),
                (ev.message, INK),
            )
            if ev.detail:
                line.append(Text(f"\n   {ev.detail}", style=MUTED))
            lines.append(line)
        hidden = len(self._events) - self.MAX
        if hidden > 0:
            lines.insert(0, Text(f"  +{hidden} earlier…", style=FAINT))
        self.update(Group(*lines))


class TodoTracker(Static):
    """EXECUTE-phase todo list rendered in the side-rail."""

    def render_state(self, todos: list[TodoItem], visible: bool) -> None:
        if not visible or not todos:
            self.update(Text("no tasks", style=FAINT))
            return
        done = sum(1 for t in todos if t.status == TodoStatus.COMPLETED)
        lines: list[Text] = [
            Text.assemble((f"tasks {done}/{len(todos)}", f"bold {INK}"))
        ]
        for t in todos:
            if t.status == TodoStatus.COMPLETED:
                glyph, color = "●", EXEC_HUE
            elif t.status == TodoStatus.IN_PROGRESS:
                glyph, color = "◐", WARN_HUE
            else:
                glyph, color = "○", FAINT
            lines.append(Text.assemble((f"{glyph} ", color), (t.content, INK)))
        self.update(Group(*lines))


# ======================================================================
# Composer — multi-line input with inverted Enter semantics
# ======================================================================


class Composer(TextArea):
    """Multi-line prompt. Enter submits; Shift/Alt+Enter / Ctrl+J insert a
    newline. Tab toggles phase / Ctrl+Y approves a plan when the buffer is
    empty. 1/0 rate the last turn when empty and a rating is pending.
    """

    class Submit(Message):
        def __init__(self, value: str) -> None:
            self.value = value
            super().__init__()

    class TogglePhase(Message):
        pass

    class ApprovePlan(Message):
        pass

    class CancelTurn(Message):
        pass

    class Rate(Message):
        def __init__(self, value: int) -> None:
            self.value = value
            super().__init__()

    # Set by the app so empty-buffer 1/0 only intercept when a rating is live.
    feedback_pending: bool = False

    async def _on_key(self, event: events.Key) -> None:  # noqa: D401
        key = event.key
        empty = not self.text.strip()

        if key == "enter":
            event.prevent_default()
            event.stop()
            value = self.text
            self.clear()
            self.post_message(self.Submit(value))
            return

        if key in ("ctrl+j", "shift+enter", "alt+enter"):
            event.prevent_default()
            event.stop()
            self.insert("\n")
            return

        if key == "escape":
            event.prevent_default()
            event.stop()
            self.post_message(self.CancelTurn())
            return

        if key == "tab" and empty:
            event.prevent_default()
            event.stop()
            self.post_message(self.TogglePhase())
            return

        if key == "ctrl+y" and empty:
            event.prevent_default()
            event.stop()
            self.post_message(self.ApprovePlan())
            return

        if key in ("1", "0") and empty and self.feedback_pending:
            event.prevent_default()
            event.stop()
            self.post_message(self.Rate(1 if key == "1" else -1))
            return

        await super()._on_key(event)


# ======================================================================
# The Textual application
# ======================================================================


class IDFCApp(App):
    """Single interactive session rendered with Textual."""

    CSS = f"""
    Screen {{
        background: #0c0e15;
        color: {INK};
        layers: base;
    }}

    #brandbar {{
        height: 3;
        padding: 0 2;
        background: #11131d;
        border-bottom: tall #1d2030;
        content-align: left middle;
    }}

    #body {{
        height: 1fr;
    }}

    #transcript {{
        width: 1fr;
        padding: 1 2;
        background: #0c0e15;
        scrollbar-size-vertical: 1;
    }}

    #sidebar {{
        width: 38;
        background: #0f1119;
        border-left: tall #1d2030;
        padding: 1 2;
    }}

    .rail-title {{
        color: {MUTED};
        text-style: bold;
        margin: 1 0 0 0;
    }}

    #phasecard, #ctxgauge, #feed, #todos {{
        margin: 0 0 1 0;
    }}

    #livewrap {{
        height: auto;
        max-height: 4;
        padding: 0 2;
        background: #0c0e15;
    }}

    #live {{
        height: auto;
        color: {INK};
    }}

    #composer-wrap {{
        height: auto;
        padding: 0 2 1 2;
        background: #0c0e15;
    }}

    Composer {{
        height: auto;
        max-height: 10;
        min-height: 3;
        border: round {FAINT};
        background: #11131d;
        padding: 0 1;
    }}

    Composer:focus {{
        border: round {PLAN_HUE};
    }}

    #statusbar {{
        height: 1;
        background: #11131d;
        color: {MUTED};
        padding: 0 2;
        border-top: tall #1d2030;
    }}
    """

    BINDINGS = [
        Binding("ctrl+c", "interrupt", "Cancel / Quit", show=False, priority=True),
        Binding("ctrl+b", "toggle_sidebar", "Sidebar", show=False),
    ]

    phase: reactive[Phase] = reactive(Phase.PLAN)

    def __init__(
        self,
        agent: CodingAgent,
        todo_manager: TodoManager,
        mcp_tools: list | None = None,
        session_id: str | None = None,
        jira_connected: bool = False,
        gocd_connected: bool = False,
        update_available: str | None = None,
        resume_session_id: str | None = None,
    ) -> None:
        super().__init__()
        self.agent = agent
        self.todo_manager = todo_manager
        self.mcp_tools = mcp_tools or []

        from idfc_coder.tool_selector import get_tool_selector

        get_tool_selector().set_mcp_tools(self.mcp_tools)

        self.phase = Phase.PLAN
        self.last_plan: str = ""
        self.token_count: int = 0
        self.jira_connected = jira_connected
        self.gocd_connected = gocd_connected
        self.update_available = update_available
        self._resume_on_mount = resume_session_id

        self._session_id = session_id
        self._session_created_at: str | None = None
        self._pending: tuple[str, list] | None = None  # (kind, items) picker state
        self._baseline_snapshot_taken = False
        self._last_user_message = ""
        self._current_snapshot_id: str | None = None

        # per-turn live state
        self._busy = False
        self._cancel_event: asyncio.Event | None = None
        self._turn_started_at = 0.0
        self._turn_token_count = 0
        self._turn_input_tokens = 0
        self._tools_this_turn = 0
        self._cur_step = 0
        self._thinking = ""
        self._live_mode = "idle"  # idle|thinking|tool|retry|cancelled
        self._tool_name = ""
        self._tool_summary = ""
        self._retry = (0, 0)

        # feedback
        self._last_trace_id: str | None = None
        self._feedback_hint_pending = False

    # ------------------------------------------------------------------
    # Layout

    def compose(self) -> ComposeResult:
        yield Static(self._brand_text(), id="brandbar")
        with Horizontal(id="body"):
            yield RichLog(
                id="transcript", wrap=True, markup=False, highlight=False, min_width=20
            )
            with VerticalScroll(id="sidebar"):
                yield Label("SESSION", classes="rail-title")
                yield PhaseCard(id="phasecard")
                yield ContextGauge(id="ctxgauge")
                yield Label("ACTIVITY", classes="rail-title")
                yield ActivityFeed(id="feed")
                yield Label("TASKS", classes="rail-title")
                yield TodoTracker(id="todos")
        with Vertical(id="livewrap"):
            yield Static(Text("", style=MUTED), id="live")
        with Vertical(id="composer-wrap"):
            yield Composer(id="composer")
        yield Static(id="statusbar")

    def on_mount(self) -> None:
        self._log = self.query_one("#transcript", RichLog)
        self._live = self.query_one("#live", Static)
        self._composer = self.query_one("#composer", Composer)
        self._phasecard = self.query_one("#phasecard", PhaseCard)
        self._ctxgauge = self.query_one("#ctxgauge", ContextGauge)
        self._feed = self.query_one("#feed", ActivityFeed)
        self._todos = self.query_one("#todos", TodoTracker)
        self._statusbar = self.query_one("#statusbar", Static)

        self.todo_manager._on_change = self._on_todos_changed

        self._log.write(_welcome_banner())
        self.token_count = self._estimate_tokens()
        self._refresh_chrome()
        self._composer.focus()
        self.set_interval(0.1, self._tick)

        if self._resume_on_mount:
            self.call_after_refresh(
                lambda: self.run_worker(
                    self._restore_session(self._resume_on_mount), exclusive=False
                )
            )

    # ------------------------------------------------------------------
    # Chrome rendering

    def _brand_text(self) -> Text:
        t = Text()
        t.append("◆ ", style=BRAND)
        t.append("idfc", style=f"bold {INK}")
        t.append("·coder", style=f"bold {BRAND_SOFT}")
        t.append("   ", style="")
        t.append("agentic coding session", style=MUTED)
        return t

    def _model_label(self) -> str:
        try:
            from idfc_coder.llm import DEFAULT_MODEL_NAME
            from idfc_coder.models import display_name, resolve_model_name

            return display_name(resolve_model_name(DEFAULT_MODEL_NAME))
        except Exception:
            return "model"

    def _refresh_chrome(self) -> None:
        self._phasecard.render_state(
            phase=self.phase,
            model_label=self._model_label(),
            jira=self.jira_connected,
            gocd=self.gocd_connected,
            update_available=self.update_available,
        )
        self._ctxgauge.render_state(self.token_count, self.agent.token_limit)
        self._todos.render_state(
            self.todo_manager.todos, visible=self.phase == Phase.EXECUTE
        )
        self._refresh_status()

    def _refresh_status(self) -> None:
        hue = phase_hue(self.phase)
        hints: list[tuple[str, str]] = []
        if self.phase == Phase.PLAN and self.last_plan:
            hints.append(("Tab/Ctrl+Y", "approve plan"))
        hints += [
            ("Enter", "send"),
            ("Alt+Enter", "newline"),
            ("Tab", "phase"),
            ("Esc", "cancel"),
            ("Ctrl+B", "rail"),
        ]
        t = Text()
        for i, (k, v) in enumerate(hints):
            if i:
                t.append("   ", style="")
            t.append(k, style=hue)
            t.append(f" {v}", style=MUTED)
        if self._busy:
            t.append("    ● working", style=WARN_HUE)
        self._statusbar.update(t)

    def watch_phase(self, _old: Phase, _new: Phase) -> None:
        # Recolor the composer border via inline style.
        try:
            composer = self.query_one("#composer", Composer)
        except Exception:
            return
        composer.styles.border = ("round", phase_hue(_new))

    # ------------------------------------------------------------------
    # Live "now" line

    def _render_live(self) -> Text:
        if self._live_mode == "idle":
            return Text("", style=MUTED)

        import time

        spin = _SPINNER_FRAMES[int(time.monotonic() * 10) % len(_SPINNER_FRAMES)]
        hue = phase_hue(self.phase)
        elapsed = _format_elapsed(time.monotonic() - self._turn_started_at)

        if self._live_mode == "cancelled":
            return Text("✗ cancelled", style=WARN_HUE)

        if self._live_mode == "retry":
            a, m = self._retry
            t = Text.assemble((f"{spin} ", WARN_HUE), (f"retrying {a}/{m}", WARN_HUE))
        elif self._live_mode == "tool":
            t = Text.assemble(
                (f"{spin} ", hue),
                (self._tool_name, f"bold {hue}"),
            )
            if self._tool_summary:
                t.append(f" {self._tool_summary}", style=MUTED)
        else:  # thinking
            tail = _tail(self._thinking)
            t = Text.assemble((f"{spin} ", BRAND), ("thinking", f"bold {INK}"))
            if tail:
                t.append(f"  {tail}", style=MUTED)

        # progress fragment
        frag: list[str] = []
        if self._cur_step > 0:
            frag.append(f"step {self._cur_step}")
        if self._tools_this_turn > 0:
            frag.append(f"tools {self._tools_this_turn}")
        if self._turn_token_count:
            frag.append(f"~{self._turn_token_count:,} tok")
        frag.append(elapsed)
        t.append(f"  · {' · '.join(frag)}", style=FAINT)
        return t

    def _update_live(self) -> None:
        self._live.update(self._render_live())

    def _tick(self) -> None:
        if self._busy:
            self._update_live()

    # ------------------------------------------------------------------
    # Input handling

    @on(Composer.Submit)
    async def _on_submit(self, msg: Composer.Submit) -> None:
        text = msg.value
        if self._busy:
            return
        if text is None:
            return

        # Picker state — a bare integer selects.
        if self._pending is not None:
            kind, items = self._pending
            self._pending = None
            stripped = text.strip().rstrip(". ,);")
            try:
                idx = int(stripped)
            except ValueError:
                idx = -1
            if 1 <= idx <= len(items):
                await self._handle_pick(kind, items[idx - 1])
                return
            # fall through to normal processing otherwise

        if not text.strip():
            return

        if text.startswith("/"):
            await self._dispatch_command(text)
            return

        await self._run_agent_turn(text)

    @on(Composer.TogglePhase)
    async def _on_toggle(self) -> None:
        if not self._busy:
            await self._toggle_phase(auto_run=False)

    @on(Composer.ApprovePlan)
    async def _on_approve(self) -> None:
        if self._busy:
            return
        if self.phase == Phase.PLAN and self.last_plan:
            await self._toggle_phase(auto_run=True)

    @on(Composer.CancelTurn)
    def _on_cancel(self) -> None:
        self._cancel_running_turn()

    @on(Composer.Rate)
    async def _on_rate(self, msg: Composer.Rate) -> None:
        if self._feedback_hint_pending and self._last_trace_id:
            await self._submit_feedback(value=msg.value, comment="")

    def action_interrupt(self) -> None:
        if self._busy:
            self._cancel_running_turn()
        else:
            self.exit()

    def action_toggle_sidebar(self) -> None:
        rail = self.query_one("#sidebar")
        rail.display = not rail.display

    def _cancel_running_turn(self) -> None:
        if self._cancel_event is not None:
            self._cancel_event.set()
        for w in self.workers:
            if w.group == "turn":
                w.cancel()

    # ------------------------------------------------------------------
    # Agent turn

    async def _run_agent_turn(self, user_text: str) -> None:
        self._log.write(_user_message(user_text))
        self._last_user_message = user_text
        self.agent.messages.append(HumanMessage(content=user_text))
        self.run_worker(
            self._stream_agent_response(user_text), exclusive=True, group="turn"
        )

    async def _stream_agent_response(self, user_text: str = "") -> None:
        import time

        from idfc_coder.tool_selector import get_tool_selector
        from idfc_coder.tools import ALL_TOOLS, PLAN_TOOLS

        base_tools = PLAN_TOOLS if self.phase == Phase.PLAN else ALL_TOOLS
        all_tools = list(base_tools) + list(self.mcp_tools)
        tools = get_tool_selector().select_tools(self._last_user_message, all_tools)
        self.agent.tool_count = len(tools)
        system_prompt = (
            PLAN_SYSTEM_PROMPT if self.phase == Phase.PLAN else EXECUTE_SYSTEM_PROMPT
        )

        # reset per-turn state
        self._busy = True
        self._cancel_event = asyncio.Event()
        self._turn_started_at = time.monotonic()
        self._turn_token_count = 0
        self._turn_input_tokens = 0
        self._tools_this_turn = 0
        self._cur_step = 0
        self._thinking = ""
        self._live_mode = "thinking"
        self._feedback_hint_pending = False
        self._last_trace_id = None
        final_content = ""
        cancelled = False
        tool_call_count = 0
        _redraw = 0

        self._feed.begin()
        if user_text:
            m, d = _generate_initial_activity(user_text)
            self._feed.add(ActivityCategory.PLANNING, m, d)
        else:
            self._feed.add(ActivityCategory.PLANNING, "Initializing task", "preparing agent")
        self._refresh_status()
        self._update_live()

        stream = self.agent.run_streaming(
            tools, system_prompt, cancellation=self._cancel_event
        )
        try:
            while True:
                try:
                    event = await stream.__anext__()
                except StopAsyncIteration:
                    break

                etype = event.get("type")
                if etype == "trace_started":
                    self._last_trace_id = event.get("trace_id")
                elif etype == "step_start":
                    self._cur_step = event.get("step", self._cur_step + 1)
                    self._live_mode = "thinking"
                    self._update_live()
                elif etype == "token":
                    chunk = event.get("content", "")
                    if not chunk:
                        continue
                    self._thinking += chunk
                    self._turn_token_count += max(1, len(chunk) // 4)
                    self._live_mode = "thinking"
                    _redraw += 1
                    if _redraw % 6 == 0:
                        self._update_live()
                elif etype == "tool_start":
                    self._thinking = ""
                    tool_call_count += 1
                    self._tools_this_turn = tool_call_count
                    self._tool_name = event.get("name", "?")
                    self._tool_summary = _summarize_tool_input(event.get("input", {}))
                    self._live_mode = "tool"
                    self._update_live()
                elif etype == "tool_end":
                    self._live_mode = "thinking"
                    self._update_live()
                elif etype == "retry":
                    self._retry = (event.get("attempt", "?"), event.get("max", "?"))
                    self._live_mode = "retry"
                    self._update_live()
                elif etype == "error":
                    self._log.write(_error_panel(event.get("error", "unknown error")))
                    self._busy = False
                    self._live_mode = "idle"
                    self._update_live()
                    self._refresh_status()
                    return
                elif etype == "plan_ready":
                    plan_text = event.get("plan", "")
                    if plan_text:
                        self.last_plan = plan_text
                        final_content = plan_text
                elif etype == "activity":
                    cat_str = event.get("category", "planning")
                    try:
                        cat = ActivityCategory(cat_str)
                    except ValueError:
                        cat = ActivityCategory.PLANNING
                    self._feed.add(
                        cat,
                        event.get("message", "Processing..."),
                        event.get("detail", ""),
                    )
                elif etype == "done":
                    final_content = event.get("content", "") or final_content or self._thinking
                    usage = event.get("usage")
                    if usage:
                        self._turn_input_tokens = usage.get("input_tokens", 0)
                        self._turn_token_count = usage.get(
                            "output_tokens", self._turn_token_count
                        )
        except asyncio.CancelledError:
            cancelled = True
            try:
                await stream.aclose()
            except Exception:
                pass
        except Exception as e:  # noqa: BLE001
            logger.exception("agent turn failed")
            self._log.write(_error_panel(str(e)))
            self._feed.add(ActivityCategory.COMPLETION, "Task failed", str(e)[:60])
            self._busy = False
            self._live_mode = "idle"
            self._update_live()
            self._refresh_status()
            return

        # ---- finalize ----
        self._busy = False
        self._live_mode = "cancelled" if cancelled else "idle"
        self._update_live()

        if cancelled:
            self._log.write(Text("(cancelled)", style=f"italic {WARN_HUE}"))
            self._feed.add(ActivityCategory.COMPLETION, "Cancelled", "")
        else:
            self._feed.add(ActivityCategory.COMPLETION, "Completed", "")

        if final_content:
            final_content = _strip_think_tags(final_content)
            self._log.write(Markdown(final_content))

        if self.phase == Phase.EXECUTE and self.todo_manager.todos:
            table = self._render_todo_table()
            if table is not None:
                self._log.write(table)

        if self.phase == Phase.PLAN and self.last_plan:
            plan_file = self.agent.cwd / "PLAN.md" if self.agent.cwd else None
            if plan_file and plan_file.exists():
                self._log.write(_plan_hint_with_file())
            else:
                self._log.write(_plan_hint())

        # token + timing footers
        tok_parts: list[str] = []
        if self._turn_input_tokens:
            tok_parts.append(f"in {self._turn_input_tokens:,}")
        if self._turn_token_count:
            tok_parts.append(f"out ~{self._turn_token_count:,}")
        if tok_parts:
            self._log.write(Text(f"tokens · {' · '.join(tok_parts)}", style=FAINT))

        elapsed = time.monotonic() - self._turn_started_at
        meta = [f"took {_format_elapsed(elapsed)}"]
        added = self.agent._lines_added
        removed = self.agent._lines_removed
        if added or removed:
            loc = []
            if added:
                loc.append(f"+{added}")
            if removed:
                loc.append(f"-{removed}")
            meta.append(f"lines {' / '.join(loc)}")
        self._log.write(Text(" · ".join(meta), style=FAINT))

        if (
            self.phase == Phase.EXECUTE
            and self.agent
            and self.agent._recent_edits
            and (self.agent._lines_added or self.agent._lines_removed)
        ):
            edits = self.agent._recent_edits
            if len(edits) <= 5:
                files_text = ", ".join(Path(f).name for f in edits)
            else:
                files_text = (
                    ", ".join(Path(f).name for f in edits[:4])
                    + f" +{len(edits) - 4} more"
                )
            self._log.write(Text(f"files · {files_text}", style=FAINT))

        if final_content and self._last_trace_id:
            self._feedback_hint_pending = True
            self._composer.feedback_pending = True
            self._log.write(
                Text.assemble(
                    ("rate  ", MUTED),
                    ("[1]", f"bold {EXEC_HUE}"),
                    (" good   ", MUTED),
                    ("[0]", f"bold {ERR_HUE}"),
                    (" bad   ", MUTED),
                    ("/feedback", BRAND_SOFT),
                    (" for a comment", MUTED),
                )
            )

        self._log.write(Rule(style="#1d2030", characters="─"))

        self.token_count = self._estimate_tokens()
        self._refresh_chrome()
        self._auto_save_session()

    # ------------------------------------------------------------------
    # Phase switching

    async def _toggle_phase(self, *, auto_run: bool) -> None:
        if self.phase == Phase.PLAN:
            if not self.last_plan:
                self._log.write(
                    Text(
                        "no plan yet — ask the agent for an implementation plan first",
                        style=MUTED,
                    )
                )
                return
            self.phase = Phase.EXECUTE
            self.agent._active_plan = self.last_plan
            self.agent.messages.append(
                HumanMessage(content=f"Here is the plan to execute:\n\n{self.last_plan}")
            )
            self._log.write(_phase_transition(Phase.EXECUTE))
            if not self._baseline_snapshot_taken:
                try:
                    from idfc_coder.snapshot.core.snapshot_engine import (
                        SNAPSHOT_DIR,
                        SnapshotEngine,
                    )

                    if self._session_id:
                        engine = SnapshotEngine(
                            project_root=Path.cwd(),
                            storage_root=SNAPSHOT_DIR,
                            session_id=self._session_id,
                        )
                        engine.create_snapshot(
                            action_type="baseline",
                            prompt_context="Initial state before execution",
                            affected_files=[],
                        )
                        self._baseline_snapshot_taken = True
                except Exception:
                    pass
        else:
            self.phase = Phase.PLAN
            self.agent._active_plan = None
            self._log.write(_phase_transition(Phase.PLAN))

        self._refresh_chrome()

        if auto_run and self.phase == Phase.EXECUTE:
            self.run_worker(self._stream_agent_response(), exclusive=True, group="turn")

    # ------------------------------------------------------------------
    # Todos

    def _on_todos_changed(self) -> None:
        # TodoManager fires this from the agent stream, which runs inside the
        # Textual event loop (a worker), so a direct widget update is safe.
        self._safe_refresh_todos()

    def _safe_refresh_todos(self) -> None:
        try:
            self._todos.render_state(
                self.todo_manager.todos, visible=self.phase == Phase.EXECUTE
            )
        except Exception:
            pass

    def _render_todo_table(self):
        if self.phase != Phase.EXECUTE or not self.todo_manager.todos:
            return None
        lines: list[Text] = [Text("Tasks", style=f"bold {INK}")]
        for todo in self.todo_manager.todos:
            if todo.status == TodoStatus.COMPLETED:
                glyph, color = "●", EXEC_HUE
            elif todo.status == TodoStatus.IN_PROGRESS:
                glyph, color = "◐", WARN_HUE
            else:
                glyph, color = "○", FAINT
            lines.append(Text.assemble((f"  {glyph} ", color), (todo.content, INK)))
        return Group(*lines)

    # ------------------------------------------------------------------
    # Picker dispatch (resume / search / models / snapshots)

    async def _handle_pick(self, kind: str, item: Any) -> None:
        if kind in ("resume", "search"):
            await self._restore_session(item["session_id"])
        elif kind == "model":
            await self._switch_model(item)
        elif kind == "snapshot":
            from idfc_coder.snapshot.core.snapshot_engine import (
                SNAPSHOT_DIR,
                SnapshotEngine,
            )

            engine = SnapshotEngine(
                project_root=Path.cwd(),
                storage_root=SNAPSHOT_DIR,
                session_id=self._session_id,
            )
            sid = item["id"]
            if engine.restore_snapshot(sid):
                self._current_snapshot_id = sid
                self._log.write(Text(f"Restored snapshot {sid}", style=EXEC_HUE))
            else:
                self._log.write(Text(f"Failed to restore {sid}", style=ERR_HUE))

    # ------------------------------------------------------------------
    # Slash commands

    _COMMANDS = {
        "help": "Show available commands",
        "clear": "Clear chat and reset agent",
        "init": "Generate or refresh project context file",
        "resume": "Resume a previous session",
        "snapshots": "List, apply, or navigate snapshots",
        "search": "Search past sessions by keyword",
        "models": "List and switch the active LLM model",
        "info": "Show session and connection information",
        "context": "Show context window usage breakdown",
        "history": "Show tool call history for this session",
        "copy": "Copy last assistant message to clipboard",
        "export": "Export session to HTML",
        "feedback": "Send feedback on the last response — /feedback <comment>",
    }

    async def _dispatch_command(self, text: str) -> None:
        parts = text[1:].split(maxsplit=1)
        name = parts[0] if parts else ""
        args = parts[1] if len(parts) > 1 else ""

        builtin = {
            "help": self._cmd_help,
            "clear": self._cmd_clear,
            "init": self._cmd_init,
            "resume": self._cmd_resume,
            "snapshots": self._cmd_snapshots,
            "search": self._cmd_search,
            "models": self._cmd_models,
            "info": self._cmd_info,
            "context": self._cmd_context,
            "history": self._cmd_history,
            "copy": self._cmd_copy,
            "export": self._cmd_export,
            "feedback": self._cmd_feedback,
        }
        if name in builtin:
            await builtin[name](args)
            return

        # skills
        try:
            from idfc_coder.skills import get_skill

            if get_skill(name):
                await self.run_skill(name)
                return
        except Exception:
            pass

        self._log.write(Text(f"unknown command: /{name}", style=WARN_HUE))

    async def _cmd_help(self, args: str) -> None:
        lines = ["**Available commands**", ""]
        for n, h in self._COMMANDS.items():
            lines.append(f"  `/{n}` — {h}")
        try:
            from idfc_coder.skills import get_invocable_skills

            skills = get_invocable_skills()
            if skills:
                lines += ["", "**Skills**", ""]
                for s in skills:
                    lines.append(f"  `/{s.name}` — {s.description}")
        except Exception:
            pass
        self._log.write(Markdown("\n".join(lines)))

    async def _cmd_clear(self, args: str) -> None:
        self._log.clear()
        self.agent.reset()
        self.last_plan = ""
        self.token_count = self._estimate_tokens()
        self._log.write(_welcome_banner())
        self._feed.clear_feed()
        self._refresh_chrome()
        self._log.write(Text("Chat cleared and agent reset.", style=MUTED))

    async def _cmd_init(self, args: str) -> None:
        from idfc_coder.agent import CONTEXT_FILES
        from idfc_coder.init import INIT_SYSTEM_PROMPT, INIT_USER_PROMPT, extract_context
        from idfc_coder.llm import get_llm
        from idfc_coder.tools import READ_ONLY_TOOLS

        self._log.write(Text("Analyzing project and generating context…", style=MUTED))
        cwd = Path.cwd()
        try:
            agent = CodingAgent(get_llm(), max_steps=30, cwd=cwd)
            agent.messages.append(HumanMessage(content=INIT_USER_PROMPT))
            final_content = ""
            count = 0
            async for event in agent.run_streaming(
                tools=list(READ_ONLY_TOOLS), system_prompt=INIT_SYSTEM_PROMPT
            ):
                if event["type"] == "tool_start":
                    count += 1
                    self._tool_name = event["name"]
                    self._tool_summary = _summarize_tool_input(event.get("input", {}))
                    self._tools_this_turn = count
                    self._live_mode = "tool"
                    self._update_live()
                elif event["type"] == "done":
                    final_content = event.get("content", "")
                elif event["type"] == "error":
                    self._log.write(_error_panel(event["error"]))
                    self._live_mode = "idle"
                    self._update_live()
                    return
            self._live_mode = "idle"
            self._update_live()

            context = extract_context(final_content)
            if not context:
                self._log.write(
                    _error_panel("Failed to generate context — no valid output.")
                )
                return
            target_file = cwd / "context.md"
            for filename in CONTEXT_FILES:
                candidate = cwd / filename
                if candidate.exists():
                    target_file = candidate
                    break
            target_file.write_text(context + "\n")
            self._log.write(
                Markdown(f"Created **{target_file.name}**. Review and edit as needed.")
            )
        except Exception as e:  # noqa: BLE001
            logger.exception("/init failed")
            self._log.write(_error_panel(str(e)))

    async def _cmd_resume(self, args: str) -> None:
        from idfc_coder.session import list_sessions

        sessions = list_sessions(project_path=str(Path.cwd()))
        if not sessions:
            self._log.write(Text("No saved sessions for this project.", style=MUTED))
            return
        rows: list[Text] = [Text("Saved sessions", style=f"bold {INK}"), Text("")]
        for i, s in enumerate(sessions[:10], 1):
            phase = "PLAN" if s["phase"] == "plan" else "EXEC"
            hue = PLAN_HUE if s["phase"] == "plan" else EXEC_HUE
            updated = s["updated_at"][:16].replace("T", " ") if s["updated_at"] else ""
            rows.append(
                Text.assemble(
                    (f"  {i:>2}. ", f"bold {INK}"),
                    (f"{phase} ", hue),
                    (s["title"], f"bold {INK}"),
                    (f"  · {s['message_count']} msgs · {updated}", MUTED),
                )
            )
        rows.append(Text(""))
        rows.append(Text("Type the number to restore, or anything else to cancel.", style=MUTED))
        self._log.write(Group(*rows))
        self._pending = ("resume", sessions[:10])

    async def _cmd_snapshots(self, args: str) -> None:
        from idfc_coder.snapshot.core.snapshot_engine import SNAPSHOT_DIR, SnapshotEngine

        parts = args.strip().split()
        command = parts[0] if parts else "list"
        engine = SnapshotEngine(
            project_root=Path.cwd(),
            storage_root=SNAPSHOT_DIR,
            session_id=self._session_id,
        )

        if command == "list":
            snapshots = engine.list_snapshots(limit=20)
            if not snapshots:
                self._log.write(Text("No snapshots found.", style=MUTED))
                return
            rows: list[Text] = [Text("Snapshots", style=f"bold {INK}"), Text("")]
            for i, snap in enumerate(snapshots, 1):
                ts = snap.get("timestamp", "")
                rows.append(
                    Text.assemble(
                        (f"  {i:>2}. ", f"bold {INK}"),
                        (f"{ts[:19] if ts else '?'} ", MUTED),
                        (f"{snap.get('action_type', '?')} ", PLAN_HUE),
                        (snap.get("prompt_context", "")[:40], INK),
                    )
                )
            rows.append(Text(""))
            rows.append(Text("Type a number to restore, or anything else to cancel.", style=MUTED))
            self._log.write(Group(*rows))
            self._pending = ("snapshot", snapshots)
            return

        if command == "apply" and len(parts) >= 2:
            snapshot_id = parts[1]
            if snapshot_id.isdigit():
                snapshots = engine.list_snapshots(limit=20)
                idx = int(snapshot_id) - 1
                if 0 <= idx < len(snapshots):
                    snapshot_id = snapshots[idx]["id"]
                else:
                    self._log.write(Text(f"Invalid number: {snapshot_id}", style=ERR_HUE))
                    return
            if engine.restore_snapshot(snapshot_id):
                self._current_snapshot_id = snapshot_id
                self._log.write(Text(f"Restored snapshot {snapshot_id}", style=EXEC_HUE))
            else:
                self._log.write(Text(f"Failed to restore {snapshot_id}", style=ERR_HUE))
            return

        if command in ("prev", "next"):
            reference_id = self._current_snapshot_id
            latest = engine.list_snapshots(limit=1)
            if not latest:
                self._log.write(Text("No snapshots found.", style=MUTED))
                return
            if reference_id is None:
                reference_id = latest[0]["id"]
            nearest = engine.get_nearest_snapshots(reference_id)
            if nearest and command in nearest:
                target = nearest[command]
                engine.restore_snapshot(target)
                self._current_snapshot_id = target
                self._log.write(Text(f"Restored {command} snapshot: {target[:12]}", style=EXEC_HUE))
            else:
                self._log.write(Text(f"No {command} snapshot available.", style=MUTED))
            return

        self._log.write(
            Text("Usage: /snapshots [list|apply <id|number>|prev|next]", style=WARN_HUE)
        )

    async def _cmd_search(self, args: str) -> None:
        import shlex

        from idfc_coder.session import SESSION_DIR
        from idfc_coder.session_index import get_session_index

        if not args.strip():
            usage = [
                Text("Session search", style=f"bold {INK}"),
                Text(""),
                Text("  /search <keywords>", style=MUTED),
                Text("  /search --after YYYY-MM-DD <kw>", style=MUTED),
                Text("  /search --before YYYY-MM-DD <kw>", style=MUTED),
            ]
            self._log.write(Group(*usage))
            return

        try:
            tokens = shlex.split(args)
        except ValueError:
            tokens = args.split()
        date_after = date_before = None
        clean: list[str] = []
        i = 0
        while i < len(tokens):
            tok = tokens[i]
            if tok == "--after" and i + 1 < len(tokens):
                date_after = tokens[i + 1] + "T00:00:00+00:00"
                i += 2
            elif tok == "--before" and i + 1 < len(tokens):
                date_before = tokens[i + 1] + "T23:59:59+00:00"
                i += 2
            else:
                clean.append(tok)
                i += 1
        query = " ".join(clean)
        if not query:
            self._log.write(Text("No search terms after parsing flags.", style=MUTED))
            return

        try:
            index = get_session_index(str(Path.cwd()))
        except Exception as e:  # noqa: BLE001
            self._log.write(_error_panel(f"Failed to load search index: {e}"))
            return
        if not index.has_indexed_anything():
            self._log.write(Text("Indexing session history for the first time…", style=MUTED))
            try:
                n = index.backfill(SESSION_DIR)
                self._log.write(Text(f"Indexed {n} session(s).", style=MUTED))
            except Exception as e:  # noqa: BLE001
                self._log.write(Text(f"Warning: could not index: {e}", style=WARN_HUE))
        try:
            results = index.search(
                query, limit=8, date_after=date_after, date_before=date_before
            )
        except Exception as e:  # noqa: BLE001
            self._log.write(_error_panel(f"Search failed: {e}"))
            return
        if not results:
            self._log.write(Text("No matching sessions. Try /resume.", style=MUTED))
            return

        rows: list[Text] = [Text("Search results", style=f"bold {INK}"), Text("")]
        for i, r in enumerate(results, 1):
            phase = "PLAN" if r["phase"] == "plan" else "EXEC"
            hue = PLAN_HUE if r["phase"] == "plan" else EXEC_HUE
            updated = r["updated_at"][:16].replace("T", " ") if r["updated_at"] else ""
            snippet = r.get("snippet", "")[:80].replace("\n", " ")
            rows.append(
                Text.assemble(
                    (f"  {i:>2}. ", f"bold {INK}"),
                    (f"{phase} ", hue),
                    (r["title"][:50], f"bold {INK}"),
                )
            )
            if snippet:
                rows.append(Text(f"       {snippet}", style=MUTED))
            rows.append(Text(f"       · {r['message_count']} msgs · {updated}", style=FAINT))
        rows.append(Text(""))
        rows.append(Text("Type the number to open, or anything else to cancel.", style=MUTED))
        self._log.write(Group(*rows))
        self._pending = ("search", results)

    async def _cmd_models(self, args: str) -> None:
        from idfc_coder.models import (
            display_name,
            fetch_models,
            format_model_list,
            get_active_model,
        )

        models = [m for m in fetch_models(refresh=True) if m.is_chat]
        if not models:
            self._log.write(_error_panel("No chat-capable models available."))
            return
        active = get_active_model()

        if args.strip():
            selected = self._parse_model_selection(models, args.strip(), active)
            if selected:
                await self._switch_model(selected)
            else:
                self._log.write(Text(f"Invalid model selection: {args.strip()}", style=WARN_HUE))
            return

        self._log.write(Markdown("# Available Models"))
        self._log.write(format_model_list(models, active))
        self._log.write(Text("Type the number to switch, or anything else to cancel.", style=MUTED))
        self._pending = ("model", models)

    def _parse_model_selection(self, models, input_str, active_model):
        try:
            if input_str.isdigit():
                idx = int(input_str) - 1
                return models[idx] if 0 <= idx < len(models) else None
            from idfc_coder.models import display_name

            low = input_str.lower()
            for m in models:
                if low in m.name.lower() or low in display_name(m.name).lower():
                    return m
            for m in models:
                if low == m.category.lower():
                    return m
            return None
        except Exception:
            return None

    async def _switch_model(self, model) -> None:
        from idfc_coder.models import apply_active_model, display_name, get_active_model

        active = get_active_model()
        if active and active.name == model.name:
            self._log.write(Markdown(f"Already using **{display_name(model.name)}**"))
            return
        try:
            apply_active_model(self.agent, model)
            self._log.write(Markdown(f"Switched to **{display_name(model.name)}**"))
            self._refresh_chrome()
        except Exception as e:  # noqa: BLE001
            self._log.write(_error_panel(f"Failed to switch model: {e}"))

    async def _cmd_copy(self, args: str) -> None:
        import pyperclip

        last_msg = None
        for msg in reversed(self.agent.messages):
            if msg.type == "ai":
                content = msg.content
                if isinstance(content, str):
                    last_msg = content
                elif isinstance(content, list):
                    parts = []
                    for part in content:
                        if isinstance(part, dict) and part.get("type") == "text":
                            parts.append(part.get("text", ""))
                        elif isinstance(part, str):
                            parts.append(part)
                    last_msg = "".join(parts)
                else:
                    last_msg = str(content)
                break
        if not last_msg:
            self._log.write(Text("No assistant message to copy.", style=ERR_HUE))
            return
        clean = re.sub(r"<think>.*?</think>\s*", "", last_msg, flags=re.DOTALL)
        try:
            pyperclip.copy(clean)
            self._log.write(Text("Copied last assistant message to clipboard.", style=EXEC_HUE))
        except Exception as e:  # noqa: BLE001
            logger.error("copy failed: %s", e)
            self._log.write(Text(f"Failed to copy: {e}", style=ERR_HUE))

    async def _cmd_export(self, args: str) -> None:
        from datetime import timezone

        from idfc_coder.commands import _generate_session_html
        from idfc_coder.session import get_sessions_dir

        sessions_dir = get_sessions_dir(str(Path.cwd()))
        if args.strip():
            output_path = Path(args.strip())
            if not output_path.is_absolute():
                output_path = sessions_dir / output_path
        else:
            ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            output_path = sessions_dir / f"session_{ts}.html"
        html = _generate_session_html(self.agent.messages, project_path=str(Path.cwd()))
        try:
            output_path.write_text(html, encoding="utf-8")
            self._log.write(Text(f"Session exported to: {output_path}", style=EXEC_HUE))
        except Exception as e:  # noqa: BLE001
            logger.error("export failed: %s", e)
            self._log.write(Text(f"Failed to export: {e}", style=ERR_HUE))

    async def _cmd_context(self, args: str) -> None:
        from langchain_core.messages import (
            AIMessage,
            HumanMessage as HM,
            SystemMessage,
            ToolMessage,
        )

        from idfc_coder.tokens import count_tokens

        token_limit = self.agent.token_limit
        messages = self.agent.messages
        system_t = human_t = ai_t = tool_t = 0
        tool_def_t = self.agent._tool_definition_tokens
        for msg in messages:
            content = msg.content if isinstance(msg.content, str) else str(msg.content)
            tokens = count_tokens(content) + 4
            if isinstance(msg, AIMessage):
                for tc in getattr(msg, "tool_calls", []) or []:
                    tokens += count_tokens(tc.get("name", "")) + 4
                    a = tc.get("args", {})
                    if a:
                        try:
                            tokens += count_tokens(
                                json.dumps(a, default=str, allow_nan=False)
                            )
                        except (ValueError, TypeError):
                            tokens += 50
            if isinstance(msg, SystemMessage):
                system_t += tokens
            elif isinstance(msg, HM):
                human_t += tokens
            elif isinstance(msg, AIMessage):
                ai_t += tokens
            elif isinstance(msg, ToolMessage):
                tool_t += tokens
        total = system_t + human_t + ai_t + tool_t + tool_def_t
        pct = lambda t: f"{t / token_limit * 100:.0f}%" if token_limit else "?"
        lines = [
            f"Context Window: {total:,} / {token_limit:,} tokens ({pct(total)})",
            "",
            f"  System prompt:   {system_t:>7,}  ({pct(system_t)})",
            f"  Tool schemas:    {tool_def_t:>7,}  ({pct(tool_def_t)})",
            f"  Conversation:    {human_t:>7,}  ({pct(human_t)})",
            f"  AI responses:    {ai_t:>7,}  ({pct(ai_t)})",
            f"  Tool results:    {tool_t:>7,}  ({pct(tool_t)})",
            "",
            f"  Messages: {len(messages)}  |  Compaction at {int(token_limit * 0.75):,}",
        ]
        self._log.write(Text("\n".join(lines), style=INK))

    async def _cmd_info(self, args: str) -> None:
        lines = ["## Session Information", ""]
        if self._session_id:
            lines.append(f"**Session ID:** `{self._session_id}`")
        else:
            lines.append("**Session ID:** Not started yet")
        lines.append(f"**Tokens used:** {self.token_count}")
        if self._session_created_at:
            lines.append(f"**Created at:** {self._session_created_at}")
        self._log.write(Markdown("\n".join(lines)))

    async def _cmd_history(self, args: str) -> None:
        from langchain_core.messages import AIMessage

        tool_calls = []
        for msg in self.agent.messages:
            if isinstance(msg, AIMessage):
                for tc in getattr(msg, "tool_calls", []):
                    name = tc.get("name", "?")
                    a = tc.get("args", {})
                    path = a.get("path") or a.get("file_path") or a.get("command", "")
                    if isinstance(path, str) and len(path) > 60:
                        path = "..." + path[-57:]
                    tool_calls.append((name, path))
        if not tool_calls:
            self._log.write(Text("No tool calls in this session.", style=MUTED))
            return
        lines = [f"Tool call history ({len(tool_calls)} calls):"]
        if len(tool_calls) > 50:
            lines.append(f"  (showing last 50 of {len(tool_calls)})")
        for i, (name, arg) in enumerate(tool_calls[-50:], 1):
            arg_str = f"  {arg}" if arg else ""
            lines.append(f"  {i:>3}. {name:<20}{arg_str}")
        self._log.write(Text("\n".join(lines), style=INK))

    async def _cmd_feedback(self, args: str) -> None:
        comment = (args or "").strip()
        if not comment:
            self._log.write(Text("Usage: /feedback <comment>", style=MUTED))
            return
        await self._submit_feedback(value=0, comment=comment)

    # ------------------------------------------------------------------
    # Feedback

    async def _submit_feedback(self, value: int, comment: str) -> None:
        trace_id = self._last_trace_id
        if not trace_id:
            self._log.write(
                Text("No trace available to score — telemetry was off.", style=MUTED)
            )
            return
        from idfc_coder.telemetry import flush as _flush_langfuse, get_langfuse_client

        client = get_langfuse_client()
        if client is None:
            self._log.write(
                Text("Langfuse not configured — feedback can't be sent.", style=MUTED)
            )
            return
        try:
            client.create_score(
                trace_id=trace_id,
                name="user_feedback",
                value=value,
                comment=comment or None,
            )
        except Exception as e:  # noqa: BLE001
            logger.warning("Feedback score post failed: %s", e)
            self._log.write(_error_panel(f"Couldn't send feedback: {e}"))
            return
        self._post_feedback_trace(
            client, value=value, comment=comment, original_trace_id=trace_id
        )
        try:
            _flush_langfuse()
        except Exception:
            pass
        self._feedback_hint_pending = False
        self._composer.feedback_pending = False
        self._last_trace_id = None
        glyph = "👍" if value > 0 else "👎" if value < 0 else "📝"
        suffix = f" — {comment}" if comment else ""
        self._log.write(Text(f"{glyph} feedback recorded{suffix}", style=MUTED))

    def _post_feedback_trace(
        self, client, *, value: int, comment: str, original_trace_id: str
    ) -> str | None:
        from langchain_core.messages import AIMessage, HumanMessage as HM

        from idfc_coder.telemetry import get_session_metadata

        polarity = "good" if value > 0 else "bad" if value < 0 else "comment-only"
        last_user = last_ai = ""
        for msg in reversed(self.agent.messages):
            content = msg.content if isinstance(msg.content, str) else str(msg.content)
            if isinstance(msg, AIMessage) and not last_ai and content.strip():
                last_ai = content[:2000]
            elif isinstance(msg, HM) and not last_user and content.strip():
                last_user = content[:2000]
            if last_user and last_ai:
                break
        from idfc_coder.llm import get_model_info

        model_info = get_model_info()
        session_meta = get_session_metadata()
        log_tail = _read_log_tail(lines=50, max_chars=8000)
        try:
            span = client.start_observation(
                name="user_feedback",
                as_type="event",
                input={"comment": comment, "polarity": polarity, "value": value},
                metadata={
                    "original_trace_id": original_trace_id,
                    "session_id": self._session_id,
                    "phase": self.phase.value,
                    "model": model_info.get("model"),
                    "provider": model_info.get("provider"),
                    "idfc_coder_version": session_meta.get("version"),
                    "git_url": session_meta.get("git_url"),
                    "last_user_message": last_user,
                    "last_assistant_response": last_ai,
                    "log_tail": log_tail,
                },
            )
            try:
                span.update_trace(
                    user_id=session_meta.get("user_id"),
                    session_id=self._session_id,
                    tags=[f"feedback:{polarity}", f"phase:{self.phase.value}"],
                )
            except Exception:
                pass
            new_trace_id = getattr(span, "trace_id", None)
            try:
                span.end()
            except Exception:
                pass
            return new_trace_id
        except Exception as e:  # noqa: BLE001
            logger.warning("Feedback trace creation failed: %s", e)
            return None

    # ------------------------------------------------------------------
    # Session save / restore

    def _auto_save_session(self) -> None:
        if not self._session_id:
            return
        try:
            from datetime import timezone

            from idfc_coder.models import get_active_model
            from idfc_coder.session import save_session

            if not self._session_created_at:
                self._session_created_at = datetime.now(timezone.utc).isoformat()
            active = get_active_model()
            save_session(
                session_id=self._session_id,
                project_path=str(Path.cwd()),
                messages=self.agent.messages,
                phase=self.phase.value,
                last_plan=self.last_plan or "",
                todos=self.todo_manager.todos,
                created_at=self._session_created_at,
                active_model=active.name if active else None,
            )
        except Exception as e:  # noqa: BLE001
            logger.warning("session auto-save failed: %s", e)

    async def _restore_session(self, session_id: str) -> None:
        from idfc_coder.session import load_session

        try:
            project_path = str(Path.cwd())
            data = load_session(session_id)
            for msg in data["messages"]:
                msg_type = type(msg).__name__
                if msg_type == "HumanMessage":
                    content = msg.content if hasattr(msg, "content") else str(msg)
                    self._log.write(_user_message(content))
                elif msg_type == "AIMessage":
                    content = msg.content if hasattr(msg, "content") else str(msg)
                    if content:
                        self._log.write(Markdown(content))
                        self._log.write(Rule(style="#1d2030", characters="─"))
            self._log.write(
                Text(f"─── Restored: {data.get('title', session_id)} ───", style=MUTED)
            )

            self.agent.messages = list(data["messages"])
            phase_str = data.get("phase", "plan")
            self.phase = (
                Phase(phase_str) if phase_str in ("plan", "execute") else Phase.PLAN
            )
            self.last_plan = data.get("last_plan", "")
            self._session_id = session_id
            self.agent.session_id = session_id
            self._session_created_at = data.get("created_at")

            if data.get("todos"):
                restored: list[TodoItem] = []
                for item in data["todos"]:
                    if isinstance(item, TodoItem):
                        restored.append(item)
                        continue
                    try:
                        status = TodoStatus(item.get("status", "pending"))
                    except ValueError:
                        status = TodoStatus.PENDING
                    restored.append(
                        TodoItem(
                            content=item.get("content", ""),
                            status=status,
                            priority=item.get("priority", "medium"),
                            id=item.get("id") or TodoItem(content="").id,
                        )
                    )
                self.todo_manager.todos = restored

            saved_model_name = data.get("active_model")
            if saved_model_name:
                from idfc_coder.models import apply_active_model, fetch_models

                match = next(
                    (
                        m
                        for m in fetch_models(refresh=False)
                        if m.name == saved_model_name and m.is_chat
                    ),
                    None,
                )
                if match:
                    apply_active_model(self.agent, match)
                else:
                    logger.warning(
                        "Saved active_model %s not in discovery — using default",
                        saved_model_name,
                    )

            self.token_count = self._estimate_tokens()
            self.todo_manager._project_path = project_path
            self.todo_manager.set_session_id(session_id, project_path)
            self._refresh_chrome()
            self._log.write(
                Text(
                    f"Session restored: {data.get('title', session_id)} "
                    f"({len(self.agent.messages)} messages, {self.phase.value} mode)",
                    style=MUTED,
                )
            )
        except Exception as e:  # noqa: BLE001
            logger.exception("restore failed")
            self._log.write(_error_panel(f"Restore failed: {e}"))

    # ------------------------------------------------------------------
    # Skills

    async def run_skill(self, skill_name: str) -> None:
        from idfc_coder.skills import get_skill

        skill = get_skill(skill_name)
        if not skill:
            return
        self._log.write(_user_message(f"Execute the /{skill.name} skill."))
        prompt = (
            f"Execute the /{skill.name} skill. Follow the instructions below "
            f"exactly.\n\n--- SKILL: {skill.name} ---\n{skill.content}"
        )
        self.agent.messages.append(HumanMessage(content=prompt))
        if self.phase == Phase.PLAN:
            self.phase = Phase.EXECUTE
            self._log.write(_phase_transition(Phase.EXECUTE))
            self._refresh_chrome()
        self.run_worker(self._stream_agent_response(), exclusive=True, group="turn")

    def _estimate_tokens(self) -> int:
        try:
            return int(self.agent._estimate_tokens()) if self.agent else 0
        except Exception:
            return 0


# ======================================================================
# Compatibility shim — preserves the original public API.
# ======================================================================


class IDFCUI:
    """Drop-in replacement for the prior ``IDFCUI``: same constructor + ``run``,
    now backed by a Textual app.
    """

    def __init__(
        self,
        agent: CodingAgent,
        todo_manager: TodoManager,
        mcp_tools: list | None = None,
        session_id: str | None = None,
        jira_connected: bool = False,
        gocd_connected: bool = False,
        update_available: str | None = None,
    ) -> None:
        self._kwargs = dict(
            agent=agent,
            todo_manager=todo_manager,
            mcp_tools=mcp_tools,
            session_id=session_id,
            jira_connected=jira_connected,
            gocd_connected=gocd_connected,
            update_available=update_available,
        )
        self.app: IDFCApp | None = None

    async def run(self, resume_session_id: str | None = None) -> None:
        self.app = IDFCApp(resume_session_id=resume_session_id, **self._kwargs)
        await self.app.run_async()


# ======================================================================
# Pure render/format helpers (logic preserved from the original).
# ======================================================================

_USER_MSG_MAX_VISIBLE_LINES = 3
_THINK_TAG_RE = re.compile(r"<think>.*?</think>\s*", flags=re.DOTALL)


def _user_message(text: str) -> Group:
    """A committed user turn — accent caret + indented continuation, with a
    summary for long pastes."""
    lines = text.splitlines() or [text]
    visible = lines[:_USER_MSG_MAX_VISIBLE_LINES]
    hidden = lines[_USER_MSG_MAX_VISIBLE_LINES:]
    rendered: list[Text] = [
        Text.assemble(("▌ ", f"bold {BRAND}"), ("you  ", BRAND_SOFT), (visible[0], f"bold {INK}"))
    ]
    for ln in visible[1:]:
        rendered.append(Text.assemble(("     ", ""), (ln, INK)))
    if hidden:
        chars = sum(len(ln) for ln in hidden) + len(hidden)
        rendered.append(
            Text(
                f"     … +{len(hidden)} more "
                f"{'line' if len(hidden) == 1 else 'lines'} ({chars:,} chars)",
                style=f"italic {FAINT}",
            )
        )
    return Group(*rendered)


def _tail(buffer: str, max_len: int = 64) -> str:
    cleaned = buffer.replace("<think>", "").replace("</think>", "")
    tail = cleaned.replace("\n", " ").strip()
    if len(tail) > max_len:
        tail = "…" + tail[-(max_len - 1) :]
    return tail


def _read_log_tail(lines: int = 50, max_chars: int = 8000) -> str:
    try:
        from idfc_coder.logging_config import LOG_DIR

        log_path = LOG_DIR / "idfc-coder.log"
        if not log_path.exists():
            return ""
        with open(log_path, "rb") as f:
            try:
                f.seek(-65536, 2)
            except OSError:
                f.seek(0)
            tail_bytes = f.read()
        text = tail_bytes.decode("utf-8", errors="replace")
        joined = "\n".join(text.splitlines()[-lines:])
        if len(joined) > max_chars:
            joined = "…" + joined[-(max_chars - 1) :]
        return joined
    except Exception:
        return ""


def _format_elapsed(seconds: float) -> str:
    if seconds < 60:
        return f"{int(seconds)}s"
    if seconds < 3600:
        m, s = divmod(int(seconds), 60)
        return f"{m}m {s}s"
    h, rem = divmod(int(seconds), 3600)
    return f"{h}h {rem // 60}m"


def _phase_transition(to: Phase) -> Text:
    hue = EXEC_HUE if to == Phase.EXECUTE else PLAN_HUE
    return Text.assemble(
        ("\n", ""),
        (f"  ▸ {to.value.upper()} MODE  ", f"bold black on {hue}"),
        ("\n", ""),
    )


def _plan_hint() -> Text:
    return Text.assemble(
        ("\n▸ ", f"bold {PLAN_HUE}"),
        ("Tab", f"bold {INK}"),
        (" or ", MUTED),
        ("Ctrl+Y", f"bold {INK}"),
        (" to approve and run this plan  ·  keep chatting to refine it first\n", MUTED),
    )


def _plan_hint_with_file() -> Text:
    return Text(
        "Review the plan in PLAN.md, then approve to execute changes.",
        style=MUTED,
    )


def _error_panel(message: str) -> Panel:
    return Panel(
        Text(message, style=ERR_HUE),
        title="error",
        title_align="left",
        border_style=ERR_HUE,
        padding=(0, 1),
    )


def _welcome_banner() -> Panel:
    body = Text()
    body.append("◆ idfc·coder\n", style=f"bold {BRAND}")
    body.append("agentic coding, planned then executed.\n\n", style=INK)
    body.append("Enter ", style=PLAN_HUE)
    body.append("send   ", style=MUTED)
    body.append("Tab ", style=PLAN_HUE)
    body.append("switch phase   ", style=MUTED)
    body.append("/help ", style=PLAN_HUE)
    body.append("commands", style=MUTED)
    return Panel(body, border_style=BRAND, padding=(0, 2))


def _strip_think_tags(text: str) -> str:
    return _THINK_TAG_RE.sub("", text).strip()


def _summarize_tool_input(args: dict) -> str:
    if not args:
        return ""
    for key in ("path", "file_path", "command", "query", "url", "pattern"):
        if key in args and args[key]:
            val = str(args[key])
            if key in ("path", "file_path"):
                val = val.rsplit("/", 1)[-1]
            return val[:60]
    for v in args.values():
        return str(v)[:60]
    return ""


def _generate_initial_activity(user_text: str) -> tuple[str, str]:
    text = user_text.lower().strip()
    if any(kw in text for kw in ["add", "new", "create", "implement", "build"]):
        return ("Analyzing implementation requirements", "understanding what to build")
    if any(kw in text for kw in ["fix", "bug", "error", "issue", "problem"]):
        return ("Investigating the issue", "understanding the problem scope")
    if any(kw in text for kw in ["refactor", "improve", "clean", "optimize"]):
        return ("Evaluating current implementation", "understanding code structure")
    if any(kw in text for kw in ["explain", "how", "what is", "why"]):
        return ("Researching the request", "gathering context")
    if any(kw in text for kw in ["test", "verify", "check"]):
        return ("Understanding test requirements", "analyzing validation needs")
    if any(kw in text for kw in ["remove", "delete", "clean up"]):
        return ("Analyzing deletion scope", "identifying affected components")
    if any(kw in text for kw in ["update", "change", "modify", "edit"]):
        return ("Understanding modification scope", "analyzing changes needed")
    return ("Analyzing your request", "understanding intent and context")
