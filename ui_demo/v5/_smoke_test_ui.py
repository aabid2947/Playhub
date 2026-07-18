"""Smoke test for the redesigned ui.py renderers — stubs the agent runtime,
imports ui.py, and renders every new element to a recorded console.
Run: python _smoke_test_ui.py   (delete after review)
"""
import sys
import types
from enum import Enum
from types import SimpleNamespace

# --- Stub the runtime modules ui.py imports at module level ---------------
agentic_tui = types.ModuleType("agentic_tui")


class _FakeSession:  # never instantiated in this test
    pass


agentic_tui.Session = _FakeSession
kitty = types.ModuleType("agentic_tui._kitty_parser")
sys.modules["agentic_tui"] = agentic_tui
sys.modules["agentic_tui._kitty_parser"] = kitty

lc = types.ModuleType("langchain_core")
lc_messages = types.ModuleType("langchain_core.messages")


class HumanMessage:
    def __init__(self, content=""):
        self.content = content


lc_messages.HumanMessage = HumanMessage
sys.modules["langchain_core"] = lc
sys.modules["langchain_core.messages"] = lc_messages

idfc = types.ModuleType("idfc_coder")
idfc.__version__ = "1.4.2"
agent_mod = types.ModuleType("idfc_coder.agent")


class Phase(str, Enum):
    PLAN = "plan"
    EXECUTE = "execute"


class CodingAgent:
    pass


agent_mod.Phase = Phase
agent_mod.CodingAgent = CodingAgent
agent_mod.PLAN_SYSTEM_PROMPT = ""
agent_mod.EXECUTE_SYSTEM_PROMPT = ""

todo_mod = types.ModuleType("idfc_coder.todo")


class TodoStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"


class TodoItem:
    def __init__(self, content="", status=TodoStatus.PENDING):
        self.content = content
        self.status = status
        self.id = "x"


class TodoManager:
    pass


todo_mod.TodoStatus = TodoStatus
todo_mod.TodoItem = TodoItem
todo_mod.TodoManager = TodoManager

llm_mod = types.ModuleType("idfc_coder.llm")
llm_mod.DEFAULT_MODEL_NAME = "/app/models/gpt-large"
models_mod = types.ModuleType("idfc_coder.models")
models_mod.display_name = lambda n: n.rsplit("/", 1)[-1]
models_mod.resolve_model_name = lambda n: n

sys.modules["idfc_coder"] = idfc
sys.modules["idfc_coder.agent"] = agent_mod
sys.modules["idfc_coder.todo"] = todo_mod
sys.modules["idfc_coder.llm"] = llm_mod
sys.modules["idfc_coder.models"] = models_mod

# --- Import the module under test ------------------------------------------
import ui  # noqa: E402

from rich.console import Console  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")
console = Console(width=100, force_terminal=True, legacy_windows=False)
P = console.print

P(ui._welcome_banner())
P()
P(ui._user_message("redesign the terminal ui to look like claude code\nkeep the core logic\nline3\nline4\nline5"))
P()
P(ui._tool_call_line("read_file", "ui.py"))
P(ui._tool_result_line({"output": "2388 lines read\nmore\nmore"}, 1.23))
P()
P(ui._tool_call_line("run_command", "pytest -q"))
P(ui._tool_result_line({}, 3.4))
P()
P(ui._tool_call_line("todo_write", ""))
P(ui._tool_result_line({"error": "permission denied: /etc/shadow"}, None))
P()
P(ui._assistant_message(
    "I redesigned the interface. Key changes:\n\n"
    "- **Status line** now uses the spark spinner\n"
    "- Tool calls commit to scrollback\n\n"
    "```python\nprint('hello')\n```"
))
P()
P(ui._thinking_line("considering how the event loop maps onto the renderer closures here", verb="Scheming"))
P(ui._tool_activity_line("run_command", "pytest -q", None, 3))
P()
P(ui._error_panel("API connection lost\nretried 3 times"))
P(ui._phase_transition(Phase.EXECUTE))
P(ui._phase_transition(Phase.PLAN))
P(ui._plan_hint())
P(ui._plan_hint_with_file())
P(ui._shortcuts_panel())

# --- methods that need a faked self ----------------------------------------
fake = object.__new__(ui.IDFCUI)
fake.active_phase = Phase.EXECUTE
fake.todo_manager = SimpleNamespace(todos=[
    TodoItem("Read the existing ui.py", TodoStatus.COMPLETED),
    TodoItem("Redesign the welcome banner", TodoStatus.IN_PROGRESS),
    TodoItem("Restyle the status toolbar", TodoStatus.PENDING),
])
P(fake._render_todo_table())
P()
P("live summary markup:", fake._render_todo_summary())

fake.last_plan = ""
fake.agent = SimpleNamespace(token_limit=200_000)
fake.token_count = 24_000
fake._tools_this_turn = 3
fake.jira_connected = True
fake.gocd_connected = False
fake.update_available = "1.5.0"
toolbar = fake._status_toolbar()
P()
P("toolbar fragments:")
for style, text in toolbar:
    P(f"  [{style!r}] {text!r}")

P()
P("abbrev:", ui._abbrev(950), ui._abbrev(1234), ui._abbrev(2_400_000))
P()
P("ALL RENDERERS OK")
