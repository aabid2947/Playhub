"""idfc-coder UI — a thin adapter over agentic_tui, styled after Claude Code.

Agent events → Turn segments:
  - token          → live status-line tail; the final answer commits at turn end
  - tool_start     → committed "⏺ Tool(arg)" call line in scrollback
  - tool_end       → committed "  ⎿  result" line under its call line
  - retry          → live yellow "Retrying…" status line
  - error          → committed red "⏺ Error:" block
  - done           → committed "⏺" answer block + dim stats footer (+ plan hint)

Docks:
  - status toolbar: ⏸ plan / ⏵⏵ execute mode + model + context + connectivity
  - activity (auto): dim per-turn activity trail, hidden between turns
"""
from __future__ import annotations

import asyncio
import logging
import os
import random
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Optional

from agentic_tui import Session

# Import the kitty parser eagerly so its synthetic keys (s-enter, c-s-*)
# are registered in prompt_toolkit's Keys enum before our keybindings
# reference them. Without this the parser only loads when a Session
# actually enters its kitty branch at runtime, which is too late.
import agentic_tui._kitty_parser  # noqa: F401

from langchain_core.messages import HumanMessage
from rich import box
from rich.console import Group
from rich.markdown import Markdown
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from idfc_coder.agent import (
    EXECUTE_SYSTEM_PROMPT,
    PLAN_SYSTEM_PROMPT,
    CodingAgent,
    Phase,
)
from idfc_coder.todo import TodoItem, TodoManager, TodoStatus

logger = logging.getLogger("idfc_coder.ui")


# ----------------------------------------------------------------------
# Theme — Claude Code-inspired look: warm accent spark, ⏺/⎿ scrollback
# glyphs, dim secondary text, rounded panels.

ACCENT = "#d77757"        # warm coral — spinner spark, welcome border
PLAN_COLOR = "#5fb4b4"    # teal — plan-mode marker
EXEC_COLOR = "#e0af68"    # amber — execute-mode marker
DIM_STYLE = "bright_black"

# prompt_toolkit equivalents for the toolbar. `noreverse bg:default` strips
# prompt_toolkit's default reversed toolbar bar so the line sits flat on the
# terminal background like Claude Code's.
_PT_RESET = "noreverse bg:default "
_PT_DIM = _PT_RESET + "fg:#7f7f7f"
_PT_ACCENT = _PT_RESET + "fg:#d77757"
_PT_PLAN = _PT_RESET + "fg:#5fb4b4"
_PT_EXEC = _PT_RESET + "fg:#e0af68"

# Spark spinner frames + one whimsical gerund per turn for the status line.
_SPARK_FRAMES = ("·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢")
_TURN_VERBS = (
    "Thinking", "Pondering", "Cogitating", "Brewing", "Percolating",
    "Noodling", "Mulling", "Scheming", "Synthesizing", "Crunching",
    "Conjuring", "Distilling", "Marinating", "Simmering", "Ruminating",
    "Reticulating", "Forging", "Whirring", "Crafting", "Working",
)


# ----------------------------------------------------------------------
# Agent Activity Panel — real-time progress updates during agent execution


class ActivityCategory(str, Enum):
    """Categories for agent activity events."""

    ANALYSIS = "analysis"
    PLANNING = "planning"
    MODIFICATION = "modification"
    VALIDATION = "validation"
    COMPLETION = "completion"


# Icon mapping for activity categories — a small colored bullet; the
# category color (below) does the differentiating, Claude Code keeps
# glyph noise to a minimum.
ACTIVITY_ICONS: dict[ActivityCategory, str] = {
    ActivityCategory.ANALYSIS: "•",
    ActivityCategory.PLANNING: "•",
    ActivityCategory.MODIFICATION: "•",
    ActivityCategory.VALIDATION: "•",
    ActivityCategory.COMPLETION: "•",
}

# Color mapping for activity categories
ACTIVITY_COLORS: dict[ActivityCategory, str] = {
    ActivityCategory.ANALYSIS: "cyan",
    ActivityCategory.PLANNING: EXEC_COLOR,
    ActivityCategory.MODIFICATION: "green",
    ActivityCategory.VALIDATION: "blue",
    ActivityCategory.COMPLETION: DIM_STYLE,
}


@dataclass
class ActivityEvent:
    """A single activity event in the agent's execution."""

    timestamp: datetime
    category: ActivityCategory
    message: str
    detail: str = ""


class ActivityPanel:
    """Manages the agent activity panel with real-time updates."""

    def __init__(self, ui: Session) -> None:
        self._ui = ui
        self._dock = ui.dock("activity", position="bottom", height="auto", max_height=8)
        self._events: list[ActivityEvent] = []
        self._collapsed = False
        self._turn_started_at: datetime | None = None
        self._visible = False  # Only show during active turns

    def begin_turn(self) -> None:
        """Start a new turn — clear events and prepare for new activities."""
        self._events = []
        self._turn_started_at = datetime.now()
        self._visible = True
        self._render()

    def add_event(self, event: ActivityEvent) -> None:
        """Add a new activity event."""
        self._events.append(event)
        self._render()

    def add_activity(
        self, category: ActivityCategory, message: str, detail: str = ""
    ) -> None:
        """Convenience method to create and add an activity event."""
        self.add_event(
            ActivityEvent(
                timestamp=datetime.now(),
                category=category,
                message=message,
                detail=detail,
            )
        )

    def _render(self) -> None:
        if not self._visible or not self._events:
            self._dock.set(Text(""))
            return

        lines: list[Text] = []

        # Dim header — the trail is secondary to the scrollback record.
        lines.append(
            Text.assemble(
                ("  activity", f"bold {DIM_STYLE}"),
                (f" · {len(self._events)}", DIM_STYLE),
            )
        )

        # Activity lines (show last 6 max to avoid panel bloat)
        max_display = 6
        display_events = self._events[-max_display:]
        for event in display_events:
            icon = ACTIVITY_ICONS.get(event.category, "•")
            color = ACTIVITY_COLORS.get(event.category, "white")
            time_str = event.timestamp.strftime("%H:%M:%S")

            line = Text.assemble(
                ("  ", ""),
                (f"{time_str}  ", DIM_STYLE),
                (f"{icon} ", color),
                (event.message, ""),
            )
            if event.detail:
                line.append_text(Text(f" — {event.detail}", style=DIM_STYLE))

            lines.append(line)

        # Show indicator if more events exist
        if len(self._events) > max_display:
            lines.append(
                Text(f"  … +{len(self._events) - max_display} earlier", style=DIM_STYLE)
            )

        # Render as a Group (no panel border, just lines)
        self._dock.set(Group(*lines))

    def end_turn(
        self, success: bool = True, error_message: str | None = None
    ) -> None:
        """Finalize the turn with a summary event."""
        if not self._visible:
            return

        # Add completion event
        if error_message:
            self.add_event(
                ActivityEvent(
                    timestamp=datetime.now(),
                    category=ActivityCategory.COMPLETION,
                    message="Task failed",
                    detail=error_message,
                )
            )
        elif self._events:
            duration = ""
            if self._turn_started_at:
                elapsed = datetime.now() - self._turn_started_at
                if elapsed.total_seconds() < 60:
                    duration = f"{int(elapsed.total_seconds())}s"
                else:
                    duration = f"{int(elapsed.total_seconds() // 60)}m"
            count = len(self._events)
            self.add_event(
                ActivityEvent(
                    timestamp=datetime.now(),
                    category=ActivityCategory.COMPLETION,
                    message="Done",
                    detail=f"{count} steps · {duration}",
                )
            )

        # Keep visible for a moment, then hide
        self._render()

    def hide(self) -> None:
        """Hide the activity panel."""
        self._visible = False
        self._events = []
        self._dock.set(Text(""))


class IDFCUI:
    """Orchestrates a single interactive session: prompt → agent turn → repeat."""

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
        self.agent = agent
        self.todo_manager = todo_manager
        self.mcp_tools = mcp_tools or []
        # Register MCP tools with tool selector - uses allowlist if no real MCP connection
        from idfc_coder.tool_selector import get_tool_selector
        tool_selector = get_tool_selector()
        tool_selector.set_mcp_tools(self.mcp_tools)
        
        self.active_phase: Phase = Phase.PLAN
        self.last_plan: str = ""
        self.token_count: int = 0
        self.jira_connected = jira_connected
        self.gocd_connected = gocd_connected
        self.update_available = update_available


        self._turn_token_count: int = 0      # output tokens for current turn only; reset each turn
        self._turn_input_tokens: int = 0     # input tokens reported by API (if available)


        self._session_id = session_id
        self._session_created_at: str | None = None
        self._pending_resume_sessions: list | None = None
        self._pending_search_results: list | None = None
        self._active_skill = None
        self._current_snapshot_id: str | None = None  # Track active snapshot for prev/next navigation
        self._baseline_snapshot_taken: bool = False  # Track if baseline snapshot was created
        self._last_user_message: str = ""  # Store user message for tool selection

        # agentic_tui primitives — set in run()
        self._ui: Session | None = None
        # In-turn ephemeral for live todo updates. Created per-turn; None
        # between turns (todos don't churn when no agent is running).
        self._todo_ephemeral: Any = None
# Activity panel for real-time progress updates (created in run())
        self._activity_panel: ActivityPanel | None = None
        # Tool-use counter for the current turn. Bumped on every tool_start
        # event, reset at the start of each turn. Read by the status
        # toolbar so users see "tools: N" growing during long thinking.
        self._tools_this_turn: int = 0
        # Last Langfuse trace id of a completed turn. Set when the agent
        # yields a `trace_started` event, cleared once the user submits a
        # rating (so accidental repeat keypresses don't re-score the same
        # turn). Used by the [1]/[0] keys and `/feedback`.
        self._last_trace_id: str | None = None
        # Whether to show the "rate · [1] good · [0] bad" hint after the
        # next idle prompt. Set when a turn completes; cleared on rating.
        self._feedback_hint_pending: bool = False

    # ------------------------------------------------------------------
    # Top-level loop

    async def run(self, resume_session_id: str | None = None) -> None:
        from prompt_toolkit.filters import has_focus
        from prompt_toolkit.key_binding import KeyBindings

        kb = KeyBindings()

        # In multiline mode prompt_toolkit's default is Enter = newline,
        # Meta+Enter = submit. Invert it: Enter submits, Alt+Enter / Ctrl+J /
        # Shift+Enter (under Kitty) insert a newline. Matches the banner hint
        # and users' expectations.
        @kb.add("enter")
        def _submit(event):
            event.current_buffer.validate_and_handle()

        @kb.add("escape", "enter")
        @kb.add("c-j")
        @kb.add("s-enter")
        def _newline(event):
            event.current_buffer.insert_text("\n")

        @kb.add("escape")
        def _cancel(event):
            # ESC key cancels the current operation (Ctrl+C alternative)
            self._ui.request_cancel()

        @kb.add("tab")
        def _tab(event):
            # Only react when the input buffer is empty — tab in mid-text is
            # completion, not phase switch.
            if event.app.current_buffer.text.strip():
                return
            if self.active_phase == Phase.PLAN and self.last_plan:
                # There's a plan ready — approve & switch to execute.
                self._ui.request_cancel_prompt(return_value="/__approve__")
            else:
                self._ui.request_cancel_prompt(return_value="/__toggle__")

        @kb.add("c-y")
        def _approve(event):
            if self.active_phase == Phase.PLAN and self.last_plan:
                self._ui.request_cancel_prompt(return_value="/__approve__")

        @kb.add("1")
        def _rate_good(event):
            # Only treat "1" as a thumbs-up when the buffer is empty AND a
            # turn has just finished with a Langfuse trace to score against.
            # In every other case, fall through to normal text input.
            if event.app.current_buffer.text:
                event.current_buffer.insert_text("1")
                return
            if not self._feedback_hint_pending or not self._last_trace_id:
                event.current_buffer.insert_text("1")
                return
            self._ui.request_cancel_prompt(return_value="/__rate_good__")

        @kb.add("0")
        def _rate_bad(event):
            if event.app.current_buffer.text:
                event.current_buffer.insert_text("0")
                return
            if not self._feedback_hint_pending or not self._last_trace_id:
                event.current_buffer.insert_text("0")
                return
            self._ui.request_cancel_prompt(return_value="/__rate_bad__")

        @kb.add("?")
        def _shortcuts(event):
            # "?" on an empty input opens the shortcuts panel; mid-text it's
            # just a question mark.
            if event.app.current_buffer.text:
                event.current_buffer.insert_text("?")
                return
            self._ui.request_cancel_prompt(return_value="/__shortcuts__")

        async with Session(
            multiline_input=True,
            key_bindings=kb,
            kitty_protocol="auto",
        ) as ui:
            self._ui = ui
            self._activity_panel = ActivityPanel(ui)
            self._register_commands(ui)

            # Todo changes print an updated snapshot to scrollback.
            self.todo_manager._on_change = self._refresh_todos

            ui.print(_welcome_banner())

            if resume_session_id:
                await self._restore_session(resume_session_id)

            while True:
                try:
                    text = await ui.prompt(
                        self._input_prompt(),  # type: ignore[arg-type]
                        prompt_continuation=self._input_continuation,
                        bottom_toolbar=self._status_toolbar,
                        refresh_interval=0.5,
                    )
                except (EOFError, KeyboardInterrupt):
                    return

                if text is None:
                    continue

                if text == "/__shortcuts__":
                    ui.print(_shortcuts_panel())
                    continue

                if text == "/__rate_good__":
                    await self._submit_feedback(value=1, comment="")
                    continue
                if text == "/__rate_bad__":
                    await self._submit_feedback(value=-1, comment="")
                    continue

                if text == "/__approve__" or text == "/__toggle__":
                    await self._toggle_phase(auto_run=(text == "/__approve__"))
                    continue

                if not text.strip():
                    continue

                # Pending resume picker — a bare integer restores.
                if self._pending_resume_sessions is not None:
                    sessions = self._pending_resume_sessions
                    self._pending_resume_sessions = None
                    try:
                        idx = int(text.strip().rstrip(". ,);"))
                        if 1 <= idx <= len(sessions):
                            await self._restore_session(sessions[idx - 1]["session_id"])
                            continue
                    except ValueError:
                        pass
                    # Fall through to normal processing

                # Pending search picker — a bare integer restores.
                if self._pending_search_results is not None:
                    results = self._pending_search_results
                    self._pending_search_results = None
                    try:
                        idx = int(text.strip().rstrip(". ,);"))
                        if 1 <= idx <= len(results):
                            await self._restore_session(results[idx - 1]["session_id"])
                            continue
                    except ValueError:
                        pass
                    # Fall through to normal processing

                if text.startswith("/"):
                    await ui.handle_command(text)
                    continue

                await self._run_agent_turn(text)

    def _input_prompt(self):
        """Live input prompt — a Claude Code-style ``> `` chevron.

        The mode (plan/execute) lives in the status toolbar below the input,
        so the prompt itself stays minimal. prompt_toolkit renders
        FormattedText prompts inline with user input.
        """
        from prompt_toolkit.formatted_text import FormattedText

        return FormattedText([("bold", "> ")])

    def _input_continuation(self, width, line_number, is_soft_wrap):
        """Rendered on every line after the first in multiline input.

        Two spaces keep continuation lines aligned under the first line's
        text, so Shift/Alt+Enter feels like growing a block.
        """
        from prompt_toolkit.formatted_text import FormattedText

        return FormattedText([("", "  ")])

    # ------------------------------------------------------------------
    # Agent turn

    async def _run_agent_turn(self, user_text: str) -> None:
        self._ui.print(_user_message(user_text))
        self._last_user_message = user_text  # Store for tool selection
        self.agent.messages.append(HumanMessage(content=user_text))
        await self._stream_agent_response(user_text)

    async def _stream_agent_response(self, user_text: str = "") -> None:
        from idfc_coder.tools import ALL_TOOLS, PLAN_TOOLS

        base_tools = PLAN_TOOLS if self.active_phase == Phase.PLAN else ALL_TOOLS
        all_tools = list(base_tools) + list(self.mcp_tools)

        # Use ToolSelector to select relevant tools based on query (reduces token usage)
        from idfc_coder.tool_selector import get_tool_selector
        tool_selector = get_tool_selector()
        tools = tool_selector.select_tools(self._last_user_message, all_tools)

        # Update agent's tool_count to reflect selected tools (not all available)
        self.agent.tool_count = len(tools)
        system_prompt = (
            PLAN_SYSTEM_PROMPT if self.active_phase == Phase.PLAN else EXECUTE_SYSTEM_PROMPT
        )

        import time

        turn_started_at = time.monotonic()
        final_content = ""
        tool_call_count = 0
        tool_started_at: float | None = None  # start time of the running tool
        current_step = 0  # bumped by `step_start` events from the agent loop
        # One whimsical gerund per turn for the status line, Claude Code style.
        turn_verb = random.choice(_TURN_VERBS)
        self._tools_this_turn = 0
        # New turn supersedes the previous one for feedback purposes.
        self._feedback_hint_pending = False
        self._last_trace_id = None
        thinking = ""  # intermediate tokens between tool calls — shown live, never committed


        self._turn_token_count = 0
        self._turn_input_tokens = 0

        # Initialize activity panel for this turn
        if self._activity_panel:
            self._activity_panel.begin_turn()
            # Generate dynamic initial activity based on user request
            if user_text:
                init_msg, init_detail = _generate_initial_activity(user_text)
                self._activity_panel.add_activity(
                    ActivityCategory.PLANNING, init_msg, init_detail
                )
            else:
                self._activity_panel.add_activity(
                    ActivityCategory.PLANNING, "Initializing task", "preparing agent"
                )

        async with self._ui.assistant_turn() as turn:
            # One live ephemeral per turn: the "✻ Verb…" status line (with
            # retry/tool states). It vanishes on turn commit — scrollback
            # keeps only the committed ⏺ tool calls, ⎿ results and the final
            # answer, Claude Code style. Todo state is a terminal snapshot —
            # we want to see it evolve live, not stack copies in scrollback.
            activity = turn.ephemeral(_thinking_line("", verb=turn_verb))
            # In EXECUTE mode, we now include todos inline in the activity line
            # instead of using a separate ephemeral. Having two ephemerals
            # caused them to stack vertically in a Group, breaking in-place
            # updates for the thinking line.
            self._todo_turn = turn
            if self.active_phase == Phase.EXECUTE:
                self._todo_ephemeral = None  # Will be handled via activity updates
                self._refresh_todos()
            else:
                self._todo_ephemeral = None

            # Activity line is rebuilt by a closure so the spinner-tick
            # task can re-render it with a fresh frame between events.
            # Each branch below replaces ``activity_builder`` instead of
            # calling ``activity.set`` directly. The tick task appends the
            # dim "(elapsed · … · esc to interrupt)" suffix to whatever the
            # builder returned — Claude Code's status-line shape.
            activity_builder: Any = lambda: _thinking_line(thinking, verb=turn_verb)

            def _render_activity() -> Text:
                base = activity_builder()
                parts: list[str] = [_format_elapsed(time.monotonic() - turn_started_at)]
                if current_step > 0:
                    parts.append(f"step {current_step}")
                if tool_call_count > 0:
                    parts.append(f"{tool_call_count} tool{'s' if tool_call_count != 1 else ''}")
                if self._turn_token_count:
                    parts.append(f"~{_abbrev(self._turn_token_count)} tokens")
                parts.append("esc to interrupt")
                line = Text.assemble(
                    base,
                    Text(f" ({' · '.join(parts)})", style=DIM_STYLE),
                )
                # In EXECUTE mode, append a one-line todo summary so progress
                # is visible without a second ephemeral (two would stack and
                # break in-place updates).
                if self.active_phase == Phase.EXECUTE:
                    todo_summary = self._render_todo_summary()
                    if todo_summary:
                        line.append_text(Text.from_markup(" " + todo_summary))
                return line

            activity.set(_render_activity())

            async def _spinner_tick() -> None:
                try:
                    while True:
                        await asyncio.sleep(0.1)
                        activity.set(_render_activity())
                except asyncio.CancelledError:
                    pass

            tick_task = asyncio.create_task(_spinner_tick())

            # Run the agent stream with cancellation support.
            # Ctrl+C (which sets turn.cancellation via Session's SIGINT handler)
            # is now propagated to the agent so it stops LLM streaming and tool
            # execution immediately, not just between events.
            stream = self.agent.run_streaming(tools, system_prompt, cancellation=turn.cancellation)
            # prompt_toolkit's @kb.add("escape") only fires while the input
            # prompt is open. While the agent is streaming, prompt_toolkit
            # has released stdin — so we read it ourselves and route a bare
            # ESC into the same cancellation event Ctrl+C uses.
            esc_watcher = _EscWatcher(turn.cancellation)
            esc_watcher.start()
            cancelled = False
            try:
                while True:
                    try:
                        event = await stream.__anext__()
                    except StopAsyncIteration:
                        break

                    etype = event.get("type")
                    if etype == "trace_started":
                        # Stash the Langfuse trace id so [1]/[0]/`/feedback`
                        # can attach a score to this specific turn.
                        self._last_trace_id = event.get("trace_id")
                        continue
                    if etype == "step_start":
                        # Heartbeat from the agent loop — fires before any
                        # token, so the status suffix shows progress during
                        # the silent pre-first-token gap.
                        current_step = event.get("step", current_step + 1)
                        activity.set(_render_activity())
                    elif etype == "token":
                        chunk = event.get("content", "")
                        if not chunk:
                            continue
                        thinking += chunk
                        self._turn_token_count += max(1, len(chunk) // 4)  # ~4 chars per token
                        # No explicit redraw — the builder reads `thinking`
                        # live and the 0.1s spinner tick repaints the line.
                        activity_builder = lambda: _thinking_line(thinking, verb=turn_verb)
                    elif etype == "tool_start":
                        thinking = ""
                        tool_call_count += 1
                        self._tools_this_turn = tool_call_count
                        name = event.get("name", "?")
                        summary = _summarize_tool_input(event.get("input", {}))
                        tool_started_at = time.monotonic()
                        # Commit the call to scrollback immediately — Claude
                        # Code's "⏺ Tool(arg)"; the "⎿" result line follows
                        # on tool_end.
                        self._ui.print(Text(""))
                        self._ui.print(_tool_call_line(name, summary))
                        activity_builder = lambda n=name, s=summary: (
                            _tool_activity_line(n, s, self.active_phase, tool_call_count)
                        )
                        activity.set(_render_activity())
                    elif etype == "tool_end":
                        took = (
                            time.monotonic() - tool_started_at
                            if tool_started_at is not None
                            else None
                        )
                        tool_started_at = None
                        self._ui.print(_tool_result_line(event, took))
                        activity_builder = lambda: _thinking_line(thinking, verb=turn_verb)
                        activity.set(_render_activity())
                    elif etype == "retry":
                        attempt = event.get("attempt", "?")
                        max_attempts = event.get("max", "?")
                        activity_builder = lambda a=attempt, m=max_attempts: (
                            Text.from_markup(
                                f"[bold yellow]{_spinner_frame()}[/bold yellow] "
                                f"[yellow]Retrying… attempt {a}/{m}[/yellow]"
                            )
                        )
                        activity.set(_render_activity())
                    elif etype == "error":
                        final_content = ""
                        self._ui.print(_error_panel(event.get("error", "unknown error")))
                        return
                    elif etype == "plan_ready":
                        plan_text = event.get("plan", "")
                        if plan_text:
                            self.last_plan = plan_text
                            final_content = plan_text
                    elif etype == "activity":
                        # Handle activity events from agent
                        if self._activity_panel:
                            category_str = event.get("category", "planning")
                            message = event.get("message", "Processing...")
                            detail = event.get("detail", "")
                            # Map string category to enum
                            try:
                                category = ActivityCategory(category_str)
                            except ValueError:
                                category = ActivityCategory.PLANNING
                            self._activity_panel.add_activity(category, message, detail)
                    elif etype == "done":
                        final_content = event.get("content", "") or final_content or thinking
                        usage = event.get("usage")
                        if usage:
                            self._turn_input_tokens = usage.get("input_tokens", 0)
                            self._turn_token_count = usage.get("output_tokens", self._turn_token_count)
            except asyncio.CancelledError:
                cancelled = True
                # Close the stream to stop the agent
                try:
                    await stream.aclose()
                except Exception:
                    pass
            except Exception as e:
                logger.exception("agent turn failed")
                self._ui.print(_error_panel(str(e)))
                # Finalize activity panel with error status
                if self._activity_panel:
                    self._activity_panel.end_turn(success=False, error_message=str(e))
                    await asyncio.sleep(0.3)
                    self._activity_panel.hide()
                return
            finally:
                esc_watcher.stop()
                tick_task.cancel()
                try:
                    await tick_task
                except (asyncio.CancelledError, Exception):
                    pass

            if cancelled:
                self._ui.print(Text("  ⎿  Interrupted by user", style="red"))

            if final_content:
                final_content = _strip_think_tags(final_content)

            # Snapshot final todo state while we're still inside the turn —
            # we'll print it to scrollback below if the turn made any
            # changes, so the user has a record of what happened.
            final_todos = self._render_todo_table() if (
                self.active_phase == Phase.EXECUTE and self.todo_manager.todos
            ) else None

        # Turn has now exited — ephemerals (activity + todos live view) are
        # gone from scrollback. Drop the ephemeral handle.
        self._todo_ephemeral = None

        # Finalize activity panel with summary
        if self._activity_panel:
            if cancelled:
                self._activity_panel.end_turn(
                    success=False, error_message="Task was cancelled"
                )
            else:
                self._activity_panel.end_turn(success=True)
            # Keep panel visible briefly, then hide
            await asyncio.sleep(0.5)
            self._activity_panel.hide()

        # Print the final answer directly to scrollback as a single atomic
        # Rich render. We avoid ``turn.append_markdown`` here because its
        # streaming rewrite path interacts badly with terminal scroll when
        # the output is taller than the remaining screen rows.
        if final_content:
            self._ui.print(Text(""))
            self._ui.print(_assistant_message(final_content))

        # Commit the final todo snapshot to scrollback so the user retains
        # a record after the live view goes away.
        if final_todos is not None:
            self._ui.print(Text(""))
            self._ui.print(final_todos)

        # Plan handoff hint — last_plan is set by the plan_ready event when
        # the model calls exit_plan_mode.
        if self.active_phase == Phase.PLAN and self.last_plan:
            # Check if PLAN.md exists for editing
            plan_file = self.agent.cwd / "PLAN.md" if self.agent.cwd else None
            has_plan_file = plan_file and plan_file.exists()

            if has_plan_file:
                self._ui.print(_plan_hint_with_file())
            else:
                self._ui.print(_plan_hint())


        # One dim stats footer line: duration · tokens · lines changed.
        elapsed = time.monotonic() - turn_started_at
        stat_parts = [_format_elapsed(elapsed)]
        tok_parts: list[str] = []
        if self._turn_input_tokens:
            tok_parts.append(f"{_abbrev(self._turn_input_tokens)} in")
        if self._turn_token_count:
            tok_parts.append(f"~{_abbrev(self._turn_token_count)} out")
        if tok_parts:
            stat_parts.append("tokens " + " / ".join(tok_parts))
        # Lines-of-code stats if the agent wrote code this turn
        added = self.agent._lines_added
        removed = self.agent._lines_removed
        if added or removed:
            loc_parts = []
            if added:
                loc_parts.append(f"+{added}")
            if removed:
                loc_parts.append(f"-{removed}")
            stat_parts.append(f"{' '.join(loc_parts)} lines")
        self._ui.print(Text("  " + " · ".join(stat_parts), style=DIM_STYLE))

        # Show files modified summary in EXECUTE phase
        if (
            self.active_phase == Phase.EXECUTE
            and self.agent
            and self.agent._recent_edits
            and (self.agent._lines_added or self.agent._lines_removed)
        ):
            edits = self.agent._recent_edits
            if len(edits) <= 5:
                files_text = ", ".join(Path(f).name for f in edits)
            else:
                files_text = ", ".join(Path(f).name for f in edits[:4]) + f" +{len(edits) - 4} more"
            self._ui.print(Text("  files: " + files_text, style=DIM_STYLE))

        # Rate-this-turn hint. Only printed when we have a trace id to
        # attach the score to; otherwise the keystroke would have nothing
        # to do. Cleared after a rating or when the user submits a new
        # prompt — see the [1]/[0] keybindings and the prompt-loop guard.
        if final_content and self._last_trace_id:
            self._feedback_hint_pending = True
            self._ui.print(
                Text.assemble(
                    ("  rate ", DIM_STYLE),
                    ("[1]", "bold"),
                    (" good · ", DIM_STYLE),
                    ("[0]", "bold"),
                    (" bad · /feedback <comment>", DIM_STYLE),
                )
            )

        # Breathing room between turns — Claude Code separates with
        # whitespace, not horizontal rules.
        self._ui.print(Text(""))

        self.token_count = self._estimate_tokens()
        self._refresh_status()
        self._auto_save_session()

    # ------------------------------------------------------------------
    # Phase switching

    async def _toggle_phase(self, *, auto_run: bool) -> None:
        if self.active_phase == Phase.PLAN:
            if not self.last_plan:
                self._ui.print(
                    Text(
                        "(no plan yet — ask the agent for an implementation plan first)",
                        style="dim",
                    )
                )
                return
            self.active_phase = Phase.EXECUTE
            self.agent._active_plan = self.last_plan
            self.agent.messages.append(
                HumanMessage(content=f"Here is the plan to execute:\n\n{self.last_plan}")
            )
            self._ui.print(_phase_transition(Phase.EXECUTE))

            # Create baseline snapshot on first switch to EXECUTE mode
            if not self._baseline_snapshot_taken:
                try:
                    from idfc_coder.snapshot.core.snapshot_engine import SnapshotEngine, SNAPSHOT_DIR
                    if self._session_id:
                        engine = SnapshotEngine(
                            project_root=Path.cwd(),
                            storage_root=SNAPSHOT_DIR,
                            session_id=self._session_id
                        )
                        engine.create_snapshot(
                            action_type="baseline",
                            prompt_context="Initial state before execution",
                            affected_files=[]
                        )
                        self._baseline_snapshot_taken = True
                except Exception:
                    pass  # Ignore snapshot errors
        else:
            self.active_phase = Phase.PLAN
            self.agent._active_plan = None
            self._ui.print(_phase_transition(Phase.PLAN))

        self._refresh_status()
        self._refresh_todos()

        if auto_run and self.active_phase == Phase.EXECUTE:
            await self._stream_agent_response()

    # ------------------------------------------------------------------
    # Docks

    def _status_toolbar(self):
        """prompt_toolkit bottom toolbar — the line under the input box.

        Claude Code style: no background bar; a dim "? for shortcuts" on the
        left, the mode marker (⏸ plan / ⏵⏵ execute), then dim session badges
        (model · context · tools · integrations · update).
        """
        from prompt_toolkit.formatted_text import FormattedText

        segs: list[tuple[str, str]] = [(_PT_DIM, " ? for shortcuts")]

        if self.active_phase == Phase.PLAN:
            if self.last_plan:
                segs.append((_PT_PLAN + " bold", "   ⏸ plan ready"))
                segs.append((_PT_DIM, " (tab or ctrl+y to approve)"))
            else:
                segs.append((_PT_PLAN, "   ⏸ plan mode on"))
                segs.append((_PT_DIM, " (tab to cycle)"))
        else:
            segs.append((_PT_EXEC, "   ⏵⏵ execute mode on"))
            segs.append((_PT_DIM, " (tab to cycle)"))

        # `display_name` strips the internal `/app/models/` prefix; we feed
        # it the active-or-env-default name so both paths share one stripper.
        from idfc_coder.llm import DEFAULT_MODEL_NAME
        from idfc_coder.models import display_name, resolve_model_name
        model_label = display_name(resolve_model_name(DEFAULT_MODEL_NAME))
        segs.append((_PT_DIM, f"   {model_label}"))

        # Context usage with a color-coded warning as it nears compaction.
        token_limit = self.agent.token_limit
        usage_pct = int(self.token_count / token_limit * 100) if token_limit else 0
        if usage_pct >= 75:
            ctx_style = _PT_RESET + "fg:ansired bold"
        elif usage_pct >= 50:
            ctx_style = _PT_RESET + "fg:ansiyellow"
        else:
            ctx_style = _PT_DIM
        segs.append((
            ctx_style,
            f"   ctx {self.token_count // 1000}k/{token_limit // 1000}k ({usage_pct}%)",
        ))

        # Per-turn tool counter — visible only while a turn is using tools.
        # Reset to 0 between turns; populated by the tool_start event handler.
        if self._tools_this_turn > 0:
            segs.append((_PT_ACCENT, f"   ⚒ {self._tools_this_turn} tools"))

        segs.append((
            _PT_RESET + "fg:ansigreen" if self.jira_connected else _PT_DIM,
            "   jira " + ("✓" if self.jira_connected else "✗"),
        ))
        segs.append((
            _PT_RESET + "fg:ansigreen" if self.gocd_connected else _PT_DIM,
            "   gocd " + ("✓" if self.gocd_connected else "✗"),
        ))

        if self.update_available:
            from idfc_coder import __version__

            segs.append((
                _PT_RESET + "fg:ansiyellow bold",
                f"   ↑ update {__version__} → {self.update_available}",
            ))

        return FormattedText(segs)

    def _refresh_status(self) -> None:
        # No-op — the bottom_toolbar callable pulls fresh state on each refresh.
        # Kept as a stub so existing call-sites (after turn, on phase switch)
        # don't need to be re-wired.
        pass

    def _refresh_todos(self) -> None:
        """Update the in-turn live todo view by triggering activity re-render.

        Called whenever TodoManager signals a change. Since we now include
        todos inline in the activity line (to avoid two ephemerals stacking
        vertically), we trigger a re-render of the activity instead.
        """
        # Trigger activity re-render if we're in a turn
        # The todo summary will be included via _render_activity
        pass  # Activity re-renders automatically via the spinner tick

    def _render_todo_summary(self):
        """One-line in-turn todo summary (a Rich markup string) appended to
        the live status line. Keeps the live region a single line so it
        never gets pushed past the terminal-height cap and flushed mid-turn
        into scrollback.
        """
        if self.active_phase != Phase.EXECUTE or not self.todo_manager.todos:
            return None
        todos = self.todo_manager.todos
        done = sum(1 for t in todos if t.status == TodoStatus.COMPLETED)
        current = next(
            (t for t in todos if t.status == TodoStatus.IN_PROGRESS), None
        )
        summary = f"[{DIM_STYLE}]· tasks {done}/{len(todos)}[/{DIM_STYLE}]"
        if current:
            content = current.content
            if len(content) > 40:
                content = content[:39] + "…"
            summary += f" [{DIM_STYLE}]☐ {_escape_markup(content)}[/{DIM_STYLE}]"
        return summary

    def _render_todo_table(self):
        """Build the committed end-of-turn task checklist, Claude Code style:
        an "⏺ Tasks" header with a ⎿-attached ☒/☐ list.

        Returns None if todos are empty or we're in PLAN phase.
        """
        if self.active_phase != Phase.EXECUTE or not self.todo_manager.todos:
            return None
        lines: list[Text] = [Text.assemble(("⏺ ", "green"), ("Tasks", "bold"))]
        for i, todo in enumerate(self.todo_manager.todos):
            prefix = "  ⎿  " if i == 0 else "     "
            if todo.status == TodoStatus.COMPLETED:
                glyph, glyph_style, text_style = "☒ ", "green", f"{DIM_STYLE} strike"
            elif todo.status == TodoStatus.IN_PROGRESS:
                glyph, glyph_style, text_style = "☐ ", "bold", "bold"
            else:
                glyph, glyph_style, text_style = "☐ ", DIM_STYLE, DIM_STYLE
            lines.append(
                Text.assemble(
                    (prefix, DIM_STYLE),
                    (glyph, glyph_style),
                    (todo.content, text_style),
                )
            )
        return Group(*lines)

    # ------------------------------------------------------------------
    # Slash commands

    def _register_commands(self, ui: Session) -> None:
        ui.register_command(
            "help", _wrap(self._cmd_help), help_text="Show available commands"
        )
        ui.register_command(
            "clear", _wrap(self._cmd_clear), help_text="Clear chat and reset agent"
        )
        ui.register_command(
            "init",
            _wrap(self._cmd_init),
            help_text="Generate or refresh project context file",
        )
        ui.register_command(
            "resume", _wrap(self._cmd_resume), help_text="Resume a previous session"
        )
        # Snapshot commands
        ui.register_command(
            "snapshots",
            _wrap(self._cmd_snapshots),
            help_text="List, apply, or navigate snapshots",
        )
        ui.register_command(
            "search", _wrap(self._cmd_search), help_text="Search past sessions by keyword"
        )
        ui.register_command(
            "models",
            _wrap(self._cmd_models),
            help_text="List and switch the active LLM model",
        )
        ui.register_command(
            "info", _wrap(self._cmd_info), help_text="Show session and connection information"
        )
        ui.register_command(
            "context",
            _wrap(self._cmd_context),
            help_text="Show context window usage breakdown",
        )
        ui.register_command(
            "history",
            _wrap(self._cmd_history),
            help_text="Show tool call history for this session",
        )
        ui.register_command(
            "copy", _wrap(self._cmd_copy), help_text="Copy last assistant message to clipboard"
        )
        ui.register_command(
            "export", _wrap(self._cmd_export), help_text="Export session to HTML"
        )
        ui.register_command(
            "feedback",
            _wrap(self._cmd_feedback),
            help_text="Send feedback on the last response — usage: /feedback <comment>",
        )
        from idfc_coder.skills import get_invocable_skills

        for skill in get_invocable_skills():
            ui.register_command(
                skill.name,
                _wrap(_make_skill_handler(self, skill.name)),
                help_text=skill.description,
            )

    async def _cmd_help(self, args: str) -> None:
        lines = ["**Available commands:**", ""]
        for entry in self._ui._commands.entries():
            lines.append(f"  `/{entry.name}` — {entry.help_text}")
        self._ui.print(Markdown("\n".join(lines)))

    async def _cmd_clear(self, args: str) -> None:
        self._ui.console.clear()
        self.agent.reset()
        self.last_plan = ""
        self.token_count = self._estimate_tokens()
        self._refresh_status()
        self._refresh_todos()
        self._ui.print(Text("Chat cleared and agent reset.", style="dim"))

    async def _cmd_init(self, args: str) -> None:
        from idfc_coder.agent import CONTEXT_FILES
        from idfc_coder.init import INIT_SYSTEM_PROMPT, INIT_USER_PROMPT, extract_context
        from idfc_coder.llm import get_llm
        from idfc_coder.tools import READ_ONLY_TOOLS

        self._ui.print(Text("Analyzing project and generating context...", style="dim"))

        cwd = Path.cwd()
        try:
            agent = CodingAgent(get_llm(), max_steps=30, cwd=cwd)
            agent.messages.append(HumanMessage(content=INIT_USER_PROMPT))

            final_content = ""
            async with self._ui.assistant_turn() as turn:
                activity = turn.ephemeral_context()
                count = 0
                async with activity as act:
                    async for event in agent.run_streaming(
                        tools=list(READ_ONLY_TOOLS), system_prompt=INIT_SYSTEM_PROMPT
                    ):
                        if event["type"] == "tool_start":
                            count += 1
                            act.set(
                                _tool_activity_line(
                                    event["name"],
                                    _summarize_tool_input(event.get("input", {})),
                                    Phase.PLAN,
                                    count,
                                )
                            )
                        elif event["type"] == "done":
                            final_content = event.get("content", "")
                        elif event["type"] == "error":
                            self._ui.print(_error_panel(event["error"]))
                            return

            context = extract_context(final_content)
            if not context:
                self._ui.print(
                    _error_panel("Failed to generate context — agent did not produce valid output.")
                )
                return

            target_file = cwd / "context.md"
            for filename in CONTEXT_FILES:
                candidate = cwd / filename
                if candidate.exists():
                    target_file = candidate
                    break
            target_file.write_text(context + "\n")
            self._ui.print(
                Markdown(f"Created **{target_file.name}**. Review and edit as needed.")
            )
        except Exception as e:
            logger.exception("/init failed")
            self._ui.print(_error_panel(str(e)))

    async def _cmd_resume(self, args: str) -> None:
        from idfc_coder.session import list_sessions

        sessions = list_sessions(project_path=str(Path.cwd()))
        if not sessions:
            self._ui.print(Text("No saved sessions for this project.", style="dim"))
            return
        renderables: list = [Text.from_markup("[bold]Saved sessions:[/bold]"), Text("")]
        for i, s in enumerate(sessions[:10], 1):
            phase = "PLAN" if s["phase"] == "plan" else "EXEC"
            phase_color = "cyan" if s["phase"] == "plan" else "green"
            updated = s["updated_at"][:16].replace("T", " ") if s["updated_at"] else ""
            title = s["title"].replace("[", r"\[")
            renderables.append(
                Text.from_markup(
                    f"  [bold]{i:>2}.[/bold]  "
                    f"[{phase_color}]{phase}[/{phase_color}]  "
                    f"[bold]{title}[/bold]  "
                    f"[dim]· {s['message_count']} msgs · {updated}[/dim]"
                )
            )
        renderables.append(Text(""))
        renderables.append(
            Text.from_markup(
                "[dim]Type a number to restore, anything else to cancel · "
                "fallback: [/dim][bold]idfc-coder --resume <id>[/bold]"
            )
        )
        self._ui.print(Group(*renderables))
        self._pending_resume_sessions = sessions[:10]

    async def _cmd_snapshots(self, args: str) -> None:
        """Handle /snapshots command - list, apply, or navigate snapshots."""
        from pathlib import Path
        from idfc_coder.index import INDEX_DIR
        from idfc_coder.snapshot.core.snapshot_engine import SnapshotEngine, SNAPSHOT_DIR

        # Parse command
        parts = args.strip().split()
        command = parts[0] if parts else "list"

        engine = SnapshotEngine(project_root=Path.cwd(), storage_root=SNAPSHOT_DIR, session_id=self._session_id)

        if command == "list":
            # List all snapshots
            snapshots = engine.list_snapshots(limit=20)
            if not snapshots:
                self._ui.print(Text("No snapshots found.", style="dim"))
                return

            lines = [Text.from_markup("[bold]Available snapshots:[/bold]"), Text("")]
            for i, snap in enumerate(snapshots, 1):
                ts = snap.get("timestamp", "")
                action = snap.get("action_type", "?")
                context = snap.get("prompt_context", "")[:40]
                sid = snap.get("id", "")
                lines.append(
                    Text.from_markup(
                        f"  [bold]{i:>2}.[/bold]  {ts[:19] if ts else '?'}  "
                        f"[cyan]{action}[/cyan]  {context}...  [dim]{sid}[/dim]"
                    )
                )
            lines.append(Text(""))
            lines.append(Text.from_markup(
                "[dim]Use /snapshots apply <id or number> to restore, or /snapshots prev/next to navigate.[/dim]"
            ))
            self._ui.print(Group(*lines))

        elif command == "apply":
            # Apply specific snapshot by ID or list number
            if len(parts) < 2:
                self._ui.print(Text("Usage: /snapshots apply <snapshot_id or list_number>", style="yellow"))
                return

            snapshot_id = parts[1]

            # Support list number as alternative to snapshot ID
            if snapshot_id.isdigit():
                index = int(snapshot_id) - 1  # Convert 1-based to 0-based
                snapshots = engine.list_snapshots(limit=20)
                if 0 <= index < len(snapshots):
                    snapshot_id = snapshots[index]["id"]
                    self._ui.print(Text(f"Restoring snapshot {index + 1}: {snapshot_id}", style="dim"))
                else:
                    self._ui.print(Text(f"Invalid snapshot number: {snapshot_id}. Available: 1-{len(snapshots)}", style="red"))
                    return

            restored = engine.restore_snapshot(snapshot_id)
            if restored:
                self._current_snapshot_id = snapshot_id
                self._ui.print(Text(f"Restored snapshot {snapshot_id}", style="green"))
            else:
                self._ui.print(Text(f"Failed to restore snapshot {snapshot_id}", style="red"))

        elif command == "prev":
            # Navigate to previous (older) snapshot
            # Use current snapshot as reference, or fall back to latest
            reference_id = self._current_snapshot_id
            snapshots = engine.list_snapshots(limit=1)
            if not snapshots:
                self._ui.print(Text("No snapshots found.", style="dim"))
                return

            # If no current snapshot tracked, use latest
            if reference_id is None:
                reference_id = snapshots[0]["id"]

            nearest = engine.get_nearest_snapshots(reference_id)
            if nearest and "prev" in nearest:
                restored = engine.restore_snapshot(nearest["prev"])
                self._current_snapshot_id = nearest["prev"]
                self._ui.print(Text(f"Restored previous snapshot: {nearest['prev'][:12]}", style="green"))
            else:
                self._ui.print(Text("No previous snapshot available.", style="dim"))

        elif command == "next":
            # Navigate to next (newer) snapshot
            # Use current snapshot as reference, or fall back to latest
            reference_id = self._current_snapshot_id
            snapshots = engine.list_snapshots(limit=1)
            if not snapshots:
                self._ui.print(Text("No snapshots found.", style="dim"))
                return

            # If no current snapshot tracked, use latest
            if reference_id is None:
                reference_id = snapshots[0]["id"]

            nearest = engine.get_nearest_snapshots(reference_id)
            if nearest and "next" in nearest:
                restored = engine.restore_snapshot(nearest["next"])
                self._current_snapshot_id = nearest["next"]
                self._ui.print(Text(f"Restored next snapshot: {nearest['next'][:12]}", style="green"))
            else:
                self._ui.print(Text("No next snapshot available (already at newest).", style="dim"))

        else:
            self._ui.print(Text("Usage: /snapshots [list|apply <id or number>|prev|next]", style="yellow"))

    async def _cmd_search(self, args: str) -> None:
        import shlex
        from idfc_coder.session_index import get_session_index
        from idfc_coder.session import SESSION_DIR

        # 1. Empty args = usage
        if not args.strip():
            usage = [
                Text.from_markup("[bold]Session search:[/bold]"),
                Text(""),
                Text.from_markup("  [dim]/search <keywords>[/dim]          Search all sessions"),
                Text.from_markup("  [dim]/search --after YYYY-MM-DD <kw>[/dim]  Filter by date"),
                Text.from_markup("  [dim]/search --before YYYY-MM-DD <kw>[/dim]"),
                Text(""),
                Text.from_markup("[dim]Examples:[/dim]"),
                Text.from_markup("  [dim]/search code refactor[/dim]"),
                Text.from_markup("  [dim]/search --after 2025-06-01 session[/dim]"),
                Text.from_markup("  [dim]/search --before 2025-12-31 bug[/dim]"),
            ]
            self._ui.print(Group(*usage))
            return

        # 2. Parse --after/--before flags
        try:
            tokens = shlex.split(args)
        except ValueError:
            tokens = args.split()

        date_after = None
        date_before = None
        clean_query_parts = []

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
                clean_query_parts.append(tok)
                i += 1

        clean_query = " ".join(clean_query_parts)
        if not clean_query:
            self._ui.print(Text("No search terms after parsing flags.", style="dim"))
            return

        # 3. Get search index
        try:
            index = get_session_index(str(Path.cwd()))
        except Exception as e:
            self._ui.print(_error_panel(f"Failed to load search index: {e}"))
            return

        # 4. Auto-backfill if first time
        if not index.has_indexed_anything():
            self._ui.print(Text.from_markup("[dim]Indexing your session history for the first time...[/dim]"))
            try:
                count = index.backfill(SESSION_DIR)
                self._ui.print(Text.from_markup(f"[dim]Indexed {count} session(s). Search is ready.[/dim]"))
            except Exception as e:
                self._ui.print(Text.from_markup(f"[yellow]Warning: could not index existing sessions: {e}[/yellow]"))

        # 5. Search
        try:
            results = index.search(clean_query, limit=8, date_after=date_after, date_before=date_before)
        except Exception as e:
            self._ui.print(_error_panel(f"Search failed: {e}"))
            return

        # 6. No results
        if not results:
            self._ui.print(Text("No matching sessions found. Try /resume to list all.", style="dim"))
            return

        # 7. Render results
        renderables = [Text.from_markup("[bold]Search results:[/bold]"), Text("")]
        for i, r in enumerate(results, 1):
            phase = "PLAN" if r["phase"] == "plan" else "EXEC"
            phase_color = "cyan" if r["phase"] == "plan" else "green"
            updated = r["updated_at"][:16].replace("T", " ") if r["updated_at"] else ""
            title = r["title"].replace("[", r"\[")
            snippet = r.get("snippet", "")[:80].replace("\n", " ").replace("[", r"\[")
            session_id_short = r.get("session_id", "")[:12]
            renderables.append(Text.assemble(
                (f"  {i:>2}.  ", "bold"),
                (phase, phase_color),
                ("  ", ""),
                (title[:50], "bold"),
                ("  ", "dim"),
                (f"({session_id_short})", "dim"),
            ))
            if snippet:
                renderables.append(Text.from_markup(f"       [dim]{snippet}[/dim]"))
            renderables.append(Text.from_markup(f"       [dim]· {r['message_count']} msgs · {updated}[/dim]"))

        renderables.append(Text(""))
        renderables.append(
            Text.from_markup(
                "[dim]Type a number to open, anything else to cancel · "
                "fallback: [/dim][bold]idfc-coder --resume <id>[/bold]"
            )
        )
        self._ui.print(Group(*renderables))
        self._pending_search_results = results
    async def _cmd_models(self, args: str) -> None:
        """Interactive picker — switch the active LLM model.

        Conversation history is preserved across the swap; the next turn
        runs against the new model with full context. The agent's
        ``token_limit`` is also updated to the new model's reported context
        window so summarization triggers at the right point.
        """
        from idfc_coder.models import (
            apply_active_model,
            fetch_models,
            get_active_model,
            format_model_list,
            short_label,
            display_name,
        )

        # `fetch_models` already falls back to the cache on network failure,
        # so a single `refresh=True` call gets fresh data when possible and
        # the cached list otherwise.
        models = [m for m in fetch_models(refresh=True) if m.is_chat]
        if not models:
            self._ui.print(
                _error_panel(
                    "No chat-capable models available — discovery API unreachable and cache empty."
                )
            )
            return

        # Get the currently active model
        active_model = get_active_model()
        
        # Show available models
        self._ui.print(Markdown("# Available Models"))
        self._ui.print(format_model_list(models, active_model))
        
        # If arguments provided, try to parse them as a model selector
        if args.strip():
            selected_model = self._parse_model_selection(models, args.strip(), active_model)
            if selected_model:
                await self._switch_model(selected_model)
                return
            else:
                self._ui.print(Markdown(f"**Invalid model selection:** `{args.strip()}`"))
                self._ui.print(Markdown("Use `/models` to see available models, or `/models <number>` to select one."))
                return
        
        # Interactive model selection
        self._ui.print(Markdown("\n## Select a model"))
        self._ui.print(Markdown("Enter the number of the model you'd like to switch to, or 'q' to quit."))
        
        # Get user input interactively
        try:
            user_input = await self._ui.input("Select model (number or 'q'): ")
            user_input = user_input.strip()
            
            if user_input.lower() in ('q', 'quit'):
                self._ui.print(Markdown("Model selection cancelled."))
                return
                
            selected_model = self._parse_model_selection(models, user_input, active_model)
            if selected_model:
                await self._switch_model(selected_model)
            else:
                self._ui.print(Markdown(f"**Invalid model selection:** `{user_input}`"))
                self._ui.print(Markdown("Please enter a valid model number from the list above."))
                
        except Exception as e:
            self._ui.print(Markdown(f"Error during model selection: {str(e)}"))

    def _parse_model_selection(self, models, input_str, active_model):
        """Parse user input to select a model."""
        try:
            # Try to parse as a number
            if input_str.isdigit():
                index = int(input_str) - 1
                if 0 <= index < len(models):
                    return models[index]
                else:
                    return None
            
            # Try to match by name
            input_str_lower = input_str.lower()
            for model in models:
                from idfc_coder.models import display_name
                if (input_str_lower in model.name.lower() or 
                    input_str_lower in display_name(model.name).lower()):
                    return model
                    
            # Try to match by category
            for model in models:
                if input_str_lower == model.category.lower():
                    return model
                    
            return None
        except Exception:
            return None

    async def _switch_model(self, model):
        """Switch to the specified model."""
        from idfc_coder.models import apply_active_model, get_active_model
        
        # Import display_name here to avoid circular import issues
        from idfc_coder.models import display_name
        
        active_model = get_active_model()
        if active_model and active_model.name == model.name:
            self._ui.print(Markdown(f"Already using model: **{display_name(model.name)}**"))
            return
            
        try:
            apply_active_model(self.agent, model)
            self._ui.print(Markdown(f"Switched to model: **{display_name(model.name)}**"))
            self._refresh_status()
        except Exception as e:
            self._ui.print(_error_panel(f"Failed to switch model: {str(e)}"))

    async def _cmd_copy(self, args: str) -> None:
        """Copy the last assistant message to clipboard."""
        import re

        import pyperclip

        # Find last assistant message
        last_msg = None
        for msg in reversed(self.agent.messages):
            if msg.type == "ai":
                content = msg.content
                if isinstance(content, str):
                    last_msg = content
                elif isinstance(content, list):
                    text_parts = []
                    for part in content:
                        if isinstance(part, dict) and part.get("type") == "text":
                            text_parts.append(part.get("text", ""))
                        elif isinstance(part, str):
                            text_parts.append(part)
                    last_msg = "".join(text_parts)
                else:
                    last_msg = str(content)
                break

        if not last_msg:
            self._ui.print("[bold red]No assistant message found to copy.[/bold red]")
            return

        # Strip think tags for cleaner copy
        clean_text = re.sub(r"<think>.*?</think>\s*", "", last_msg, flags=re.DOTALL)

        try:
            pyperclip.copy(clean_text)
            self._ui.print("[bold green]Copied last assistant message to clipboard.[/bold green]")
        except Exception as e:
            logger.error(f"Failed to copy to clipboard: {e}")
            self._ui.print(f"[bold red]Failed to copy: {e}[/bold red]")

    async def _cmd_export(self, args: str) -> None:
        """Export the session to HTML."""
        from datetime import datetime, timezone

        from idfc_coder.commands import _generate_session_html
        from idfc_coder.session import get_sessions_dir

        sessions_dir = get_sessions_dir(str(Path.cwd()))
        
        # Determine output path
        if args.strip():
            # User specified a file path
            output_path = Path(args.strip())
            if not output_path.is_absolute():
                output_path = sessions_dir / output_path
        else:
            # Default: save to sessions directory
            timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            output_path = sessions_dir / f"session_{timestamp}.html"

        # Generate HTML content
        html_content = _generate_session_html(
            self.agent.messages, project_path=str(Path.cwd())
        )

        try:
            output_path.write_text(html_content, encoding="utf-8")
            self._ui.print(f"[bold green]Session exported to: {output_path}[/bold green]")
        except Exception as e:
            logger.error(f"Failed to export session: {e}")
            self._ui.print(f"[bold red]Failed to export: {e}[/bold red]")

    # ------------------------------------------------------------------
    async def _cmd_context(self, args: str) -> None:
        """Show context window usage breakdown."""
        if not self.agent:
            self._ui.print(Text("No active agent.", style="dim"))
            return

        import json
        from idfc_coder.tokens import count_tokens
        from langchain_core.messages import SystemMessage, HumanMessage, AIMessage, ToolMessage

        token_limit = self.agent.token_limit
        messages = self.agent.messages

        system_tokens = 0
        human_tokens = 0
        ai_tokens = 0
        tool_tokens = 0
        tool_def_tokens = self.agent._tool_definition_tokens

        for msg in messages:
            content = msg.content if isinstance(msg.content, str) else str(msg.content)
            tokens = count_tokens(content) + 4
            # Match _estimate_tokens: AIMessages can carry tool_calls whose
            # name + serialized args contribute to the real on-the-wire size.
            # Without this the totals diverge from the status bar by the
            # tool-call args (typically 50–500 tokens per call).
            if isinstance(msg, AIMessage):
                for tc in getattr(msg, "tool_calls", []) or []:
                    tokens += count_tokens(tc.get("name", "")) + 4
                    args = tc.get("args", {})
                    if args:
                        try:
                            tokens += count_tokens(json.dumps(args, default=str, allow_nan=False))
                        except (ValueError, TypeError):
                            tokens += 50
            if isinstance(msg, SystemMessage):
                system_tokens += tokens
            elif isinstance(msg, HumanMessage):
                human_tokens += tokens
            elif isinstance(msg, AIMessage):
                ai_tokens += tokens
            elif isinstance(msg, ToolMessage):
                tool_tokens += tokens

        total_used = system_tokens + human_tokens + ai_tokens + tool_tokens + tool_def_tokens
        pct = lambda t: f"{t / token_limit * 100:.0f}%" if token_limit else "?"

        lines = [
            f"Context Window: {total_used:,} / {token_limit:,} tokens ({pct(total_used)})",
            f"",
            f"  System prompt:   {system_tokens:>7,}  ({pct(system_tokens)})",
            f"  Tool schemas:    {tool_def_tokens:>7,}  ({pct(tool_def_tokens)})",
            f"  Conversation:    {human_tokens:>7,}  ({pct(human_tokens)})",
            f"  AI responses:    {ai_tokens:>7,}  ({pct(ai_tokens)})",
            f"  Tool results:    {tool_tokens:>7,}  ({pct(tool_tokens)})",
            f"",
            f"  Messages: {len(messages)}  |  Compaction triggers at {int(token_limit * 0.75):,}",
        ]
        self._ui.print(Text("\n".join(lines)))

    async def _cmd_info(self, args: str) -> None:
        """Display current session and connection information."""
        lines = ["## Session Information", ""]

        # Session ID
        if self._session_id:
            lines.append(f"**Session ID:** `{self._session_id}`")
        else:
            lines.append("**Session ID:** Not started yet")

        # Token usage
        lines.append(f"**Tokens used:** {self.token_count}")

        # Additional helpful information
        if hasattr(self, '_session_created_at') and self._session_created_at:
            lines.append(f"**Created at:** {self._session_created_at}")

        self._ui.print(Markdown("\n".join(lines)))

    async def _cmd_history(self, args: str) -> None:
        """Show tool call history for this session."""
        if not self.agent:
            self._ui.print(Text("No active agent.", style="dim"))
            return

        from langchain_core.messages import AIMessage

        tool_calls = []
        for msg in self.agent.messages:
            if isinstance(msg, AIMessage):
                for tc in getattr(msg, "tool_calls", []):
                    name = tc.get("name", "?")
                    tc_args = tc.get("args", {})
                    path = tc_args.get("path") or tc_args.get("file_path") or tc_args.get("command", "")
                    if isinstance(path, str) and len(path) > 60:
                        path = "..." + path[-57:]
                    tool_calls.append((name, path))

        if not tool_calls:
            self._ui.print(Text("No tool calls in this session.", style="dim"))
            return

        lines = [f"Tool call history ({len(tool_calls)} calls):"]
        for i, (name, arg) in enumerate(tool_calls[-50:], 1):
            arg_str = f"  {arg}" if arg else ""
            lines.append(f"  {i:>3}. {name:<20}{arg_str}")

        if len(tool_calls) > 50:
            lines.insert(1, f"  (showing last 50 of {len(tool_calls)})")

        self._ui.print(Text("\n".join(lines)))

    # ------------------------------------------------------------------
    # Feedback (👍 / 👎 / /feedback)

    async def _submit_feedback(self, value: int, comment: str) -> None:
        """Post a Langfuse score against the most recent turn's trace.

        ``value`` is +1 for good, -1 for bad. ``comment`` is free-form
        (empty for keystroke ratings, populated for ``/feedback``).
        Clears the rate-prompt state so accidental repeat keypresses
        don't double-score the same turn.
        """
        trace_id = self._last_trace_id
        if not trace_id:
            self._ui.print(
                Text(
                    "No trace available to score — the last turn didn't run "
                    "with telemetry enabled.",
                    style="dim",
                )
            )
            return

        from idfc_coder.telemetry import get_langfuse_client, flush as _flush_langfuse

        client = get_langfuse_client()
        if client is None:
            self._ui.print(
                Text(
                    "Langfuse is not configured — feedback can't be sent. "
                    "Check LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY.",
                    style="dim",
                )
            )
            return

        # 1) Score on the existing turn-trace — keeps the rating linked to
        #    the actual conversation in Langfuse's score view.
        try:
            client.create_score(
                trace_id=trace_id,
                name="user_feedback",
                value=value,
                comment=comment or None,
            )
        except Exception as e:
            logger.warning("Feedback score post failed: %s", e)
            self._ui.print(
                _error_panel(f"Couldn't send feedback: {e}")
            )
            return

        # 2) Standalone feedback trace — a separate, easily-listed entry
        #    that triagers can scan without opening every agent run.
        feedback_trace_id = self._post_feedback_trace(
            client, value=value, comment=comment, original_trace_id=trace_id
        )

        # Best-effort flush so both the score and the new trace land
        # quickly even if the session ends right after.
        try:
            _flush_langfuse()
        except Exception:
            pass

        # Consume the rating so a second keypress doesn't re-score.
        self._feedback_hint_pending = False
        self._last_trace_id = None

        if value > 0:
            glyph = "👍"
        elif value < 0:
            glyph = "👎"
        else:
            glyph = "📝"  # comment-only (/feedback without explicit polarity)
        suffix = f" — {comment}" if comment else ""
        self._ui.print(
            Text.from_markup(f"[dim]{glyph} feedback recorded{_escape_markup(suffix)}[/dim]")
        )

    def _post_feedback_trace(
        self, client, *, value: int, comment: str, original_trace_id: str
    ) -> str | None:
        """Open a fresh Langfuse trace dedicated to this feedback report.

        The agent's normal turn-trace already carries full message + tool
        history; this duplicates the *summary* into an independent trace so
        triagers can scan a feedback inbox without opening every agent run.
        Failure here is non-fatal — the score-on-existing-trace from
        ``_submit_feedback`` is the authoritative record.
        """
        from langchain_core.messages import AIMessage, HumanMessage
        from idfc_coder.telemetry import get_session_metadata

        polarity = (
            "good" if value > 0
            else "bad" if value < 0
            else "comment-only"
        )

        # Last user input + last assistant response (truncated). Skip
        # synthetic injected messages from compaction / forced-continuation.
        last_user = ""
        last_ai = ""
        for msg in reversed(self.agent.messages):
            content = msg.content if isinstance(msg.content, str) else str(msg.content)
            if isinstance(msg, AIMessage) and not last_ai and content.strip():
                last_ai = content[:2000]
            elif isinstance(msg, HumanMessage) and not last_user and content.strip():
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
                input={
                    "comment": comment,
                    "polarity": polarity,
                    "value": value,
                },
                metadata={
                    "original_trace_id": original_trace_id,
                    "session_id": self._session_id,
                    "phase": self.active_phase.value,
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
                    tags=[f"feedback:{polarity}", f"phase:{self.active_phase.value}"],
                )
            except Exception:
                pass
            new_trace_id = getattr(span, "trace_id", None)
            try:
                span.end()
            except Exception:
                pass
            logger.info(
                "Feedback trace created: polarity=%s trace_id=%s original=%s",
                polarity, new_trace_id, original_trace_id,
            )
            return new_trace_id
        except Exception as e:
            logger.warning("Feedback trace creation failed: %s", e)
            return None

    async def _cmd_feedback(self, args: str) -> None:
        comment = (args or "").strip()
        if not comment:
            self._ui.print(
                Text(
                    "Usage: /feedback <comment>",
                    style="dim",
                )
            )
            return
        # /feedback without an explicit polarity → treated as a "neutral
        # but with detail" report. Langfuse scores are numeric, so we use
        # 0 to mean "comment-only, no thumb." Triagers see it in the same
        # user_feedback score view.
        await self._submit_feedback(value=0, comment=comment)

    # ------------------------------------------------------------------
    # Session save/restore

    def _auto_save_session(self) -> None:
        if not self._session_id:
            return
        try:
            from datetime import datetime, timezone

            from idfc_coder.models import get_active_model
            from idfc_coder.session import save_session

            if not self._session_created_at:
                self._session_created_at = datetime.now(timezone.utc).isoformat()
            active = get_active_model()
            save_session(
                session_id=self._session_id,
                project_path=str(Path.cwd()),
                messages=self.agent.messages,
                phase=self.active_phase.value,
                last_plan=self.last_plan or "",
                todos=self.todo_manager.todos,
                created_at=self._session_created_at,
                active_model=active.name if active else None,
            )
        except Exception as e:
            logger.warning(f"session auto-save failed: {e}")

    async def _restore_session(self, session_id: str) -> None:
        from langchain_core.messages import HumanMessage, AIMessage

        try:
            from idfc_coder.session import load_session

            project_path = str(Path.cwd())
            data = load_session(session_id)
            
            # --- Replay ALL messages to scrollback (Bug B fix) ---
            for msg in data["messages"]:
                msg_type = type(msg).__name__
                if msg_type == "HumanMessage":
                    # Render user message
                    content = msg.content if hasattr(msg, "content") else str(msg)
                    self._ui.print(_user_message(content))
                elif msg_type == "AIMessage":
                    # Render AI response - get content and commit to scrollback
                    content = msg.content if hasattr(msg, "content") else str(msg)
                    if content:
                        # Same "⏺" answer block the live path commits
                        self._ui.print(_assistant_message(content))
                        self._ui.print(Text(""))
                # Skip tool messages - don't display them in replay
            
            # --- Separator ---
            self._ui.print(
                Text.from_markup(
                    f"─── Restored: {data.get('title', session_id)} ───",
                    style="dim",
                )
            )
            
            # --- Load rest of session state ---
            self.agent.messages = list(data["messages"])
            phase_str = data.get("phase", "plan")
            self.active_phase = (
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
            # Restore the active model if one was saved. If it's no longer
            # offered by the gateway, log a warning and fall through to the
            # env-var default — the session still loads.
            saved_model_name = data.get("active_model")
            if saved_model_name:
                from idfc_coder.models import apply_active_model, fetch_models
                match = next(
                    (m for m in fetch_models(refresh=False)
                     if m.name == saved_model_name and m.is_chat),
                    None,
                )
                if match:
                    apply_active_model(self.agent, match)
                else:
                    logger.warning(
                        "Saved active_model %s not in current discovery "
                        "list — using default",
                        saved_model_name,
                    )

            self.token_count = self._estimate_tokens()
            self._refresh_status()
            self._refresh_todos()
            
            # Set project path for todo manager persistence
            self.todo_manager._project_path = project_path
            self.todo_manager.set_session_id(session_id, project_path)
            
            self._ui.print(
                Text(
                    f"Session restored: {data.get('title', session_id)} "
                    f"({len(self.agent.messages)} messages, {self.active_phase.value} mode)",
                    style="dim",
                )
            )
        except Exception as e:
            logger.exception("restore failed")
            self._ui.print(_error_panel(f"Restore failed: {e}"))

    # ------------------------------------------------------------------
    # Skill invocation (called by skill slash commands)

    async def run_skill(self, skill_name: str) -> None:
        from idfc_coder.skills import get_skill

        skill = get_skill(skill_name)
        if not skill:
            return
        display = f"Execute the /{skill.name} skill."
        self._ui.print(_user_message(display))
        prompt = (
            f"Execute the /{skill.name} skill. Follow the instructions below "
            f"exactly.\n\n--- SKILL: {skill.name} ---\n{skill.content}"
        )
        self.agent.messages.append(HumanMessage(content=prompt))
        if self.active_phase == Phase.PLAN:
            self.active_phase = Phase.EXECUTE
            self._ui.print(_phase_transition(Phase.EXECUTE))
            self._refresh_status()
            self._refresh_todos()
        await self._stream_agent_response()

    def _estimate_tokens(self) -> int:
        try:
            return int(self.agent._estimate_tokens()) if self.agent else 0
        except Exception:
            return 0


# ----------------------------------------------------------------------
# Renderers

_USER_MSG_MAX_VISIBLE_LINES = 3


def _user_message(text: str) -> Group:
    """Committed user-turn message: dim ``> text``, Claude Code style.

    For multi-line input past the visibility cap, show the first few lines and
    a ``… +N more lines`` summary so long pastes don't pollute scrollback.
    Dimmed so history recedes and the assistant's ⏺ blocks carry the weight.
    """
    lines = text.splitlines() or [text]
    visible = lines[:_USER_MSG_MAX_VISIBLE_LINES]
    hidden = lines[_USER_MSG_MAX_VISIBLE_LINES:]

    rendered: list[Text] = [
        Text.assemble(
            ("> ", f"bold {DIM_STYLE}"),
            (visible[0], DIM_STYLE),
        )
    ]
    for ln in visible[1:]:
        rendered.append(Text("  " + ln, style=DIM_STYLE))

    if hidden:
        hidden_chars = sum(len(ln) for ln in hidden) + len(hidden)  # +newlines
        rendered.append(
            Text(
                f"  … +{len(hidden)} more "
                f"{'line' if len(hidden) == 1 else 'lines'} "
                f"({hidden_chars:,} chars)",
                style="dim italic",
            )
        )
    return Group(*rendered)


def _assistant_message(markdown_text: str) -> Table:
    """Committed assistant answer: ``⏺`` bullet + markdown body.

    A two-column grid keeps wrapped and multi-block markdown aligned under
    the first text column, matching Claude Code's answer blocks.
    """
    grid = Table.grid(padding=(0, 1), expand=True)
    grid.add_column(width=1, no_wrap=True)
    grid.add_column(ratio=1, overflow="fold")
    grid.add_row(Text("⏺", style="bold"), Markdown(markdown_text))
    return grid


_THINK_OPEN_TAG = "<think>"
_THINK_CLOSE_TAG = "</think>"


def _thinking_line(
    buffer: str,
    turn_tokens: int = 0,
    step: int = 0,
    tools_count: int = 0,
    verb: str = "Thinking",
) -> Text:
    """Live status line: ``✻ Verb…`` plus a dim italic tail of the stream.

    Strips ``<think>`` / ``</think>`` tags so they don't leak into the live
    indicator — the committed path already strips them for scrollback output.
    The dim ``(elapsed · step · tools · tokens · esc to interrupt)`` suffix is
    appended by the turn's ``_render_activity`` closure; ``turn_tokens`` /
    ``step`` / ``tools_count`` are accepted for call-site compatibility but
    now render in that suffix instead.
    """
    cleaned = buffer.replace(_THINK_OPEN_TAG, "").replace(_THINK_CLOSE_TAG, "")
    tail = cleaned.replace("\n", " ").strip()
    max_len = 48
    if len(tail) > max_len:
        tail = "…" + tail[-(max_len - 1):]
    line = Text.assemble(
        (f"{_spinner_frame()} ", f"bold {ACCENT}"),
        (f"{verb}…", "bold"),
    )
    if tail:
        line.append_text(Text(f" {tail}", style="dim italic"))
    return line


def _escape_markup(text: str) -> str:
    """Escape `[...]` so Rich doesn't parse it as markup."""
    return text.replace("[", r"\[")


# Friendly display names for common agent tools, Claude Code style. Unknown
# names fall back to title-cased words ("run_tests" → "Run Tests").
_TOOL_LABELS: dict[str, str] = {
    "read_file": "Read",
    "read": "Read",
    "write_file": "Write",
    "write": "Write",
    "create_file": "Write",
    "edit_file": "Update",
    "edit": "Update",
    "apply_patch": "Update",
    "bash": "Bash",
    "shell": "Bash",
    "run_command": "Bash",
    "execute_command": "Bash",
    "run_shell_command": "Bash",
    "grep": "Search",
    "search": "Search",
    "search_files": "Search",
    "code_search": "Search",
    "glob": "Glob",
    "find_files": "Glob",
    "list_dir": "List",
    "list_directory": "List",
    "ls": "List",
    "web_search": "WebSearch",
    "fetch_url": "Fetch",
    "todo_write": "Update Todos",
    "todo_read": "Read Todos",
    "update_todos": "Update Todos",
    "exit_plan_mode": "Exit Plan Mode",
}


def _tool_display_name(name: str) -> str:
    key = name.strip().lower()
    if key in _TOOL_LABELS:
        return _TOOL_LABELS[key]
    return name.replace("_", " ").strip().title() or "?"


def _tool_call_line(name: str, summary: str) -> Text:
    """Committed tool-call record: green-dot ``⏺ Read(ui.py)``."""
    line = Text.assemble(("⏺ ", "green"), (_tool_display_name(name), "bold"))
    if summary:
        line.append_text(Text(f"({summary})", style=DIM_STYLE))
    return line


def _tool_result_line(event: dict, took: float | None) -> Text:
    """Committed tool-result record: dim ``  ⎿  …`` under its call line.

    The agent's tool_end event may or may not carry output — summarize the
    first line when it does, otherwise fall back to ``Done in Ns``.
    """
    err = event.get("error")
    if isinstance(err, str) and err.strip():
        first = err.strip().splitlines()[0][:90]
        return Text("  ⎿  Error: " + first, style="red")

    out = event.get("output") or event.get("result") or event.get("content")
    if isinstance(out, str) and out.strip():
        out_lines = out.strip().splitlines()
        first = out_lines[0].strip()
        if len(first) > 90:
            first = first[:89] + "…"
        more = len(out_lines) - 1
        if more > 0:
            first += f" … +{more} line{'s' if more != 1 else ''}"
        return Text("  ⎿  " + first, style=DIM_STYLE)

    label = "Done"
    if took is not None and took >= 0.1:
        pretty = f"{took:.1f}s" if took < 10 else _format_elapsed(took)
        label += f" in {pretty}"
    return Text("  ⎿  " + label, style=DIM_STYLE)


def _tool_activity_line(
    name: str,
    summary: str,
    phase: Phase | None = None,
    count: int = 0,
    turn_tokens: int = 0,
    step: int = 0,
) -> Text:
    """Live status line while a tool runs: ``✻ Read(ui.py)…``.

    The committed ⏺/⎿ record is printed separately on tool_start/tool_end;
    this is only the spinner fragment. ``phase`` / ``count`` / ``turn_tokens``
    / ``step`` are accepted for call-site compatibility — progress renders in
    the dim suffix appended by ``_render_activity``.
    """
    line = Text.assemble(
        (f"{_spinner_frame()} ", f"bold {ACCENT}"),
        (_tool_display_name(name), "bold"),
    )
    if summary:
        line.append_text(Text(f"({summary})", style=DIM_STYLE))
    line.append_text(Text("…", style=DIM_STYLE))
    return line


def _read_log_tail(lines: int = 50, max_chars: int = 8000) -> str:
    """Return the tail of ``~/.idfc-coder/logs/idfc-coder.log``.

    Best-effort: returns an empty string if the file is missing or
    unreadable (don't crash feedback over a stat failure). The cap is
    char-based, not line-based, because a single multi-line traceback
    can blow the budget — so we trim from the front after concatenation.
    """
    try:
        from idfc_coder.logging_config import LOG_DIR
        log_path = LOG_DIR / "idfc-coder.log"
        if not log_path.exists():
            return ""
        # Read end-of-file: 64KB is plenty to find 50 lines on a chatty
        # session and short enough to be cheap on a 5MB log.
        with open(log_path, "rb") as f:
            try:
                f.seek(-65536, 2)
            except OSError:
                f.seek(0)
            tail_bytes = f.read()
        text = tail_bytes.decode("utf-8", errors="replace")
        last_lines = text.splitlines()[-lines:]
        joined = "\n".join(last_lines)
        if len(joined) > max_chars:
            joined = "…" + joined[-(max_chars - 1):]
        return joined
    except Exception:
        return ""


def _format_elapsed(seconds: float) -> str:
    """Format ``seconds`` as ``5s``, ``1m 20s``, ``2h 3m``."""
    if seconds < 60:
        return f"{int(seconds)}s"
    if seconds < 3600:
        m, s = divmod(int(seconds), 60)
        return f"{m}m {s}s"
    h, rem = divmod(int(seconds), 3600)
    m = rem // 60
    return f"{h}h {m}m"


def _abbrev(n: int) -> str:
    """1234 → ``1.2k`` — compact counts for status and footer lines."""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


def _spinner_frame() -> str:
    """Pick a spark frame based on wall clock so live re-renders animate."""
    import time

    idx = int(time.monotonic() * 10) % len(_SPARK_FRAMES)
    return _SPARK_FRAMES[idx]


def _phase_transition(to: Phase) -> Text:
    if to == Phase.EXECUTE:
        return Text.assemble(
            ("\n⏵⏵ execute mode on", f"bold {EXEC_COLOR}"),
            (" — the agent may edit files and run commands\n", DIM_STYLE),
        )
    return Text.assemble(
        ("\n⏸ plan mode on", f"bold {PLAN_COLOR}"),
        (" — read-only: explore and shape a plan first\n", DIM_STYLE),
    )


def _plan_hint() -> Text:
    return Text.assemble(
        ("\n⏸ ", f"bold {PLAN_COLOR}"),
        ("Plan ready", "bold"),
        (" — press ", DIM_STYLE),
        ("tab", "bold"),
        (" or ", DIM_STYLE),
        ("ctrl+y", "bold"),
        (" to approve and execute · keep chatting to refine\n", DIM_STYLE),
    )


def _plan_hint_with_file() -> Text:
    """Plan-ready hint when a PLAN.md exists to review first."""
    return Text.assemble(
        ("\n⏸ ", f"bold {PLAN_COLOR}"),
        ("Plan ready", "bold"),
        (" — review ", DIM_STYLE),
        ("PLAN.md", "bold"),
        (", then press ", DIM_STYLE),
        ("tab", "bold"),
        (" or ", DIM_STYLE),
        ("ctrl+y", "bold"),
        (" to approve and execute\n", DIM_STYLE),
    )


def _error_panel(message: str) -> Group:
    """Red ``⏺ Error:`` block (name kept for call-site compatibility)."""
    lines = str(message).splitlines() or [""]
    rendered: list[Text] = [
        Text.assemble(("⏺ Error: ", "bold red"), (lines[0], "red"))
    ]
    for ln in lines[1:]:
        rendered.append(Text("  " + ln, style="red"))
    return Group(*rendered)


def _welcome_banner() -> Group:
    """Claude Code-style welcome: a rounded accent box + dim starter tips."""
    try:
        from idfc_coder import __version__

        version_suffix = f" v{__version__}"
    except Exception:
        version_suffix = ""

    body = Group(
        Text.assemble(
            ("✻ ", f"bold {ACCENT}"),
            ("Welcome to IDFC Coder!", "bold"),
            (version_suffix, DIM_STYLE),
        ),
        Text(""),
        Text("  /help for help, /info for your current setup", style=DIM_STYLE),
        Text(""),
        Text(f"  cwd: {Path.cwd()}", style=DIM_STYLE),
    )
    panel = Panel(
        body,
        box=box.ROUNDED,
        border_style=ACCENT,
        padding=(0, 1),
        expand=False,
    )
    return Group(
        panel,
        Text(""),
        Text(" Tips for getting started:", style=DIM_STYLE),
        Text(""),
        Text(" 1. Describe a task to get a plan — tab approves and executes it", style=DIM_STYLE),
        Text(" 2. Run /init to generate a project context file", style=DIM_STYLE),
        Text(" 3. Be as specific as you would with another engineer", style=DIM_STYLE),
        Text(""),
        Text(" Press ? for shortcuts · esc interrupts a running turn", style=DIM_STYLE),
    )


def _shortcuts_panel() -> Panel:
    """The ``?`` cheat-sheet: every keybinding the prompt understands."""
    grid = Table.grid(padding=(0, 3))
    grid.add_column(style="bold", no_wrap=True)
    grid.add_column(style=DIM_STYLE)
    for keys, action in (
        ("enter", "send message"),
        ("shift+enter / alt+enter / ctrl+j", "insert newline"),
        ("tab", "switch plan ⇄ execute · approve a ready plan (empty input)"),
        ("ctrl+y", "approve the plan"),
        ("esc", "interrupt the running turn"),
        ("ctrl+c", "cancel / exit"),
        ("1 / 0", "rate the last response (after the rate hint)"),
        ("/", "slash commands — /help lists them"),
    ):
        grid.add_row(keys, action)
    return Panel(
        grid,
        title="Shortcuts",
        title_align="left",
        box=box.ROUNDED,
        border_style=DIM_STYLE,
        padding=(0, 1),
        expand=False,
    )


_THINK_TAG_RE = re.compile(r"<think>.*?</think>\s*", flags=re.DOTALL)


def _strip_think_tags(text: str) -> str:
    """Remove <think>...</think> blocks so reasoning doesn't leak into scrollback."""
    return _THINK_TAG_RE.sub("", text).strip()


def _summarize_tool_input(args: dict) -> str:
    if not args:
        return ""
    for key in ("path", "file_path", "command", "query", "url", "pattern"):
        if key in args and args[key]:
            val = str(args[key])
            if key in ("path", "file_path"):
                val = val.replace("\\", "/").rsplit("/", 1)[-1]
            return val[:60]
    for v in args.values():
        return str(v)[:60]
    return ""


def _generate_initial_activity(user_text: str) -> tuple[str, str]:
    """Generate initial activity message based on user request analysis.

    Returns (message, detail) with meaningful, context-aware descriptions.
    Never exposes raw chain-of-thought.
    """
    text = user_text.lower().strip()

    # Analyze request type and generate appropriate message
    if any(kw in text for kw in ["add", "new", "create", "implement", "build"]):
        return ("Analyzing implementation requirements", "understanding what to build")
    elif any(kw in text for kw in ["fix", "bug", "error", "issue", "problem"]):
        return ("Investigating the issue", "understanding the problem scope")
    elif any(kw in text for kw in ["refactor", "improve", "clean", "optimize"]):
        return ("Evaluating current implementation", "understanding code structure")
    elif any(kw in text for kw in ["explain", "how", "what is", "why"]):
        return ("Researching the request", "gathering context")
    elif any(kw in text for kw in ["test", "verify", "check"]):
        return ("Understanding test requirements", "analyzing validation needs")
    elif any(kw in text for kw in ["remove", "delete", "clean up"]):
        return ("Analyzing deletion scope", "identifying affected components")
    elif any(kw in text for kw in ["update", "change", "modify", "edit"]):
        return ("Understanding modification scope", "analyzing changes needed")
    else:
        return ("Analyzing your request", "understanding intent and context")


# ----------------------------------------------------------------------
# Command-registry glue: session.register_command wants (session, args);
# our handlers take just args and use self. Wrap them.


def _wrap(handler):
    async def _w(session, args):
        await handler(args)

    return _w


def _make_skill_handler(ui: IDFCUI, skill_name: str):
    async def _h(args):
        await ui.run_skill(skill_name)

    return _h


# Kitty keyboard protocol ESC: CSI 27 u, optionally CSI 27;<mods> u.
_KITTY_ESC_RE = re.compile(rb"\x1b\[27(?:;\d+)?u")


class _EscWatcher:
    """Watch stdin for an ESC press during agent streaming.

    prompt_toolkit's escape binding only fires while a prompt is open. While
    the agent is generating, prompt_toolkit isn't reading stdin — so we put
    the tty into cbreak mode and route ESC into the turn's cancellation
    event. Handles both legacy bare ``\\x1b`` and Kitty CSI-u ``\\x1b[27u``
    encodings (kitty mode is enabled in iTerm2 / Kitty / WezTerm).
    Original tty attrs are restored on stop.
    """

    def __init__(self, cancellation: asyncio.Event) -> None:
        self._cancellation = cancellation
        self._loop: asyncio.AbstractEventLoop | None = None
        self._fd: int | None = None
        self._old_attrs: Any = None
        self._reader_attached = False

    def start(self) -> None:
        if not sys.stdin.isatty():
            return
        try:
            import termios
            import tty
        except ImportError:
            return
        try:
            fd = sys.stdin.fileno()
        except (ValueError, OSError):
            return
        try:
            self._old_attrs = termios.tcgetattr(fd)
        except termios.error:
            return
        try:
            tty.setcbreak(fd)
        except termios.error:
            self._old_attrs = None
            return
        self._fd = fd
        try:
            self._loop = asyncio.get_running_loop()
            self._loop.add_reader(fd, self._on_readable)
            self._reader_attached = True
        except (NotImplementedError, RuntimeError):
            self._restore_tty()

    def _on_readable(self) -> None:
        if self._fd is None:
            return
        try:
            data = os.read(self._fd, 64)
        except (BlockingIOError, OSError):
            return
        if not data:
            return
        # Bare ESC (legacy terminals) or kitty CSI-u ``\x1b[27u``
        # (iTerm2/Kitty/WezTerm with the keyboard protocol enabled).
        if data == b"\x1b" or _KITTY_ESC_RE.search(data):
            self._cancellation.set()

    def stop(self) -> None:
        if self._reader_attached and self._loop is not None and self._fd is not None:
            try:
                self._loop.remove_reader(self._fd)
            except (NotImplementedError, RuntimeError, ValueError):
                pass
            self._reader_attached = False
        self._restore_tty()

    def _restore_tty(self) -> None:
        if self._fd is not None and self._old_attrs is not None:
            try:
                import termios

                termios.tcsetattr(self._fd, termios.TCSADRAIN, self._old_attrs)
            except Exception:
                pass
        self._fd = None
        self._old_attrs = None