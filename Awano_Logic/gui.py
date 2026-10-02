import os, queue, threading
import tkinter as tk
from tkinter import filedialog, messagebox
from .editors import BinEditor, ShopEditor, StringTableEditor, shorten_path_smart
from .par_batch import PAR_MAX_WORKERS, run_par_batch_unpack
from .shop_bin import SHOP_GAME_Y0, SHOP_GAME_Y3
from .widgets import (
    ACCENT,
    FIELD_BG,
    GOLD_FG,
    MUTED_FG,
    PANEL_BG,
    FloatingPanel,
    make_button,
    make_scrollbar,
)

WIDTH = 900
HEIGHT = 460

BG_COLOR = "#1a1a1a"
INACTIVE = "#444"
STRIP = "#666"
TEXT = "white"

PANEL_2 = "#555555"
PANEL_3 = "#ffffff"

TITLE = "Awano's Easy Life Tools"

MAIN_BUTTONS = ["Tools", "Guide"]

SUB_OPTIONS = {
    "Tools": ["BIN Editor", "Shop BINs", "String Table", "PAR Unpack"],
    "Guide": ["BIN Guide", "Usage Docs"],
}

SUB_SUB_OPTIONS = {
    "BIN Editor": ["Open", "Close"],
    "Shop BINs": ["Y0", "Y3", "Close"],
    "String Table": ["Open", "Close"],
    "PAR Unpack": ["Batch Unpack"],
    "BIN Guide": ["Info", "Credits"],
    "Usage Docs": ["Usage", "Explanations"],
}

PAR_PANEL_WIDTH = 640
PAR_PANEL_HEIGHT = 480
GUIDE_PANEL_WIDTH = 600
GUIDE_PANEL_HEIGHT = 480
PANEL_X = 540
PAR_LOG_LIMIT = 120
PAR_POLL_MS = 100

GUIDE_CONTENT = {
    ("BIN Guide", "Info"): (
        "BIN Guide, Info",
        "Awano has two BIN editors because the files arent the same format.\n\n"
        "BIN Editor opens the older 20070319 files, usually named .bin_c, .bin_j, "
        "or .bin_k. They're table style files with entries and named parameter fields. "
        "Shop BINs opens Y0 and Y3 shop tables. They use separate binary layouts. \n\n"
        "String Table opens string_tbl.bin. Its a list of groups, each group holding "
        "pointers to text. Saving rebuilds every pointer so strings can grow or shrink.",
    ),
    ("BIN Guide", "Credits"): (
        "BIN Guide, Credits",
        "2007 BIN editor source reference: SlowpokeVG's JavaScript BIN work.\n\n"
        "Shop BIN binary template references: Violet's Y0 and Y3 shop BIN 010 templates.\n\n",
    ),
    ("Usage Docs", "Usage"): (
        "Usage Docs, Usage",
        "BIN Editor opens 20070319 .bin_c, .bin_j, and .bin_k files. Use Open to pick a "
        "file and Close to unload it.\n\n"
        "2007 BIN buttons: UTF-8 or CP932 changes the save encoding. S applies the Value "
        "box to the selected entry and field. RA reloads all values from the original "
        "file. E duplicates the current entry for expansion work. C saves a new BIN. "
        "R restores only the selected value from the original load.\n\n"
        "Shop BINs opens Y0 and Y3 shop tables. Press Y0 or Y3 to pick a file for that "
        "game. Close unloads the current shop BIN.\n\n"
        "Shop buttons: S applies the Value box. RA reloads all values from the original "
        "shop BIN. C saves a new shop BIN. R restores only the selected field from the "
        "original load.\n\n"
        "String Table opens string_tbl.bin. Pick a group on the left and a string on the "
        "right. S, RA, C, and R work the same as in Shop BINs.\n\n"
        "Search: every editor has a search bar that looks through every value in the "
        "file. Exact only matches whole values, Aa makes it case sensitive. Enter "
        "jumps to the next result, Shift+Enter to the previous one, Esc clears it, and "
        "Ctrl+F focuses it. Clicking a result opens that entry and field.\n\n"
        "Panels: drag the title bar to move a panel anywhere on screen, drag the corner "
        "grip to resize it, and drag the gaps between lists or above the Value box to "
        "give any section more room. Picking an editor in the Tools menu brings its "
        "panel back if a file is still loaded.",
    ),
    ("Usage Docs", "Explanations"): (
        "Usage Docs, Explanations",
        "Entries are the rows in the loaded table. Fields are the values stored for the "
        "selected row.\n\n"
        "Text fields can be longer than the visible area, scroll as needed. The line "
        "above the Value box shows the character and byte count of the value andd how "
        "many bytes it changed since it was loaded.\n\n"
        "The 2007 BIN editor has an E button because those tables can be expanded by "
        "duplicating an entry.\n\n"
        "Shop BIN numeric edits should keep the table compact. Description edits may grow "
        "the file because the save path rewrites the string area and updates pointers.\n\n"
        "String Table strings marked (null) have no text at all. They stay null unless "
        "you type something and press S.",
    ),
}

EDITOR_SUBS = {"BIN Editor", "Shop BINs", "String Table"}

class AwanoApp:
    def __init__(self):
        self.ui_state = {
            "main": None,
            "sub": None,
        }
        self.par_state = {
            "root_path": None,
            "output_root": None,
            "status": "Select a folder to batch unpack PAR archives.",
            "summary": "Idle.",
            "progress": 0.0,
            "running": False,
            "cancel_requested": False,
            "top_level_jobs": 0,
            "nested_jobs": 0,
            "total_jobs": 0,
            "completed_jobs": 0,
            "active_jobs": 0,
            "queued_jobs": 0,
            "error_count": 0,
            "thread": None,
            "update_queue": None,
            "cancel_event": None,
        }

        self.main_btns = []
        self.sub_btns = []
        self.sub_sub_btns = []
        self.drag_data = {"x": 0, "y": 0}
        self.topmost = True
        self.panels = []
        self.exclusive_panels = []

        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.geometry(f"{WIDTH}x{HEIGHT}+300+200")
        self.root.wm_attributes("-transparentcolor", BG_COLOR)
        self.root.attributes("-topmost", True)

        self.canvas = tk.Canvas(
            self.root,
            width=WIDTH,
            height=HEIGHT,
            bg=BG_COLOR,
            highlightthickness=0,
        )
        self.canvas.pack()

        self.bin_editor = BinEditor(self)
        self.shop_editor = ShopEditor(self)
        self.string_tbl_editor = StringTableEditor(self)
        self.editors = {
            "BIN Editor": self.bin_editor,
            "Shop BINs": self.shop_editor,
            "String Table": self.string_tbl_editor,
        }
        self.create_par_panel()
        self.create_guide_panel()
        self.exclusive_panels = [
            self.bin_editor.panel,
            self.shop_editor.panel,
            self.string_tbl_editor.panel,
            self.guide_panel,
        ]

        self.bind_events()
        self.redraw()

    def bind_events(self):
        self.canvas.bind("<Button-1>", self.on_left_click)

        self.root.bind("<Button-3>", self.start_drag)
        self.root.bind("<B3-Motion>", self.do_drag)
        self.root.bind(
            "<ButtonRelease-3>",
            lambda event: self.drag_data.update({"x": 0, "y": 0}),
        )
        self.root.bind("<Escape>", self.close_app)
        self.root.bind("<F1>", self.toggle_topmost)

    def register_panel(self, panel):
        self.panels.append(panel)
        panel.window.bind("<Escape>", self.close_app)
        panel.window.bind("<F1>", self.toggle_topmost)

    def show_exclusive(self, panel):
        for other in self.exclusive_panels:
            if other is not panel:
                other.hide()
        panel.show()

    def hide_exclusive(self):
        for panel in self.exclusive_panels:
            panel.hide()

    def create_par_panel(self):
        self.par_panel = FloatingPanel(
            self.root,
            "PAR Unpack",
            PAR_PANEL_WIDTH,
            PAR_PANEL_HEIGHT,
            PANEL_X,
            84,
            self.close_par_panel,
        )
        self.register_panel(self.par_panel)
        panel = self.par_panel.body

        info_var = tk.StringVar(value="No PAR batch running.")
        status_var = tk.StringVar(value=self.par_state["status"])
        summary_var = tk.StringVar(value=self.par_state["summary"])

        info_label = tk.Label(
            panel,
            textvariable=info_var,
            bg=PANEL_BG,
            fg="white",
            anchor="w",
            justify="left",
            font=("Segoe UI", 8, "bold"),
        )
        info_label.pack(fill="x", padx=8, pady=(6, 2))

        status_label = tk.Label(
            panel,
            textvariable=status_var,
            bg=PANEL_BG,
            fg=MUTED_FG,
            anchor="w",
            justify="left",
            font=("Segoe UI", 8),
        )
        status_label.pack(fill="x", padx=8)

        summary_label = tk.Label(
            panel,
            textvariable=summary_var,
            bg=PANEL_BG,
            fg=GOLD_FG,
            anchor="w",
            justify="left",
            font=("Segoe UI", 8, "bold"),
        )
        summary_label.pack(fill="x", padx=8, pady=(2, 6))

        def update_wrap(event):
            for label in (info_label, status_label, summary_label):
                label.configure(wraplength=max(event.width - 24, 120))

        panel.bind("<Configure>", update_wrap)

        progress_canvas = tk.Canvas(
            panel,
            height=12,
            bg=FIELD_BG,
            highlightthickness=0,
            relief="flat",
        )
        progress_canvas.pack(fill="x", padx=8, pady=(0, 6))
        progress_fill = progress_canvas.create_rectangle(0, 0, 0, 12, fill=ACCENT, outline="")
        progress_canvas.bind("<Configure>", lambda event: self.draw_par_progress())

        button_row = tk.Frame(panel, bg=PANEL_BG)
        button_row.pack(side="bottom", fill="x", padx=8, pady=(6, 4))

        cancel_button = make_button(
            button_row,
            "Cancel",
            self.cancel_par_batch,
            "#6a4a4a",
            "#8f6161",
            width=9,
        )
        cancel_button.pack(side="right")

        log_frame = tk.Frame(panel, bg=PANEL_BG)
        log_frame.pack(fill="both", expand=True, padx=8)

        log_text = tk.Text(
            log_frame,
            height=7,
            wrap="word",
            bg=FIELD_BG,
            fg="white",
            relief="flat",
            insertbackground="white",
            font=("Consolas", 8),
            state="disabled",
        )
        log_text.pack(side="left", fill="both", expand=True)

        log_scrollbar = make_scrollbar(log_frame, log_text.yview)
        log_scrollbar.pack(side="left", fill="y")
        log_text.configure(yscrollcommand=log_scrollbar.set)

        self.par_widgets = {
            "info_var": info_var,
            "status_var": status_var,
            "summary_var": summary_var,
            "progress_canvas": progress_canvas,
            "progress_fill": progress_fill,
            "log_text": log_text,
            "cancel_button": cancel_button,
        }

        self.refresh_par_widgets()

    def create_guide_panel(self):
        self.guide_panel = FloatingPanel(
            self.root,
            "Guide",
            GUIDE_PANEL_WIDTH,
            GUIDE_PANEL_HEIGHT,
            PANEL_X,
            76,
            self.guide_panel_hide,
        )
        self.register_panel(self.guide_panel)

        text_frame = tk.Frame(self.guide_panel.body, bg=PANEL_BG)
        text_frame.pack(fill="both", expand=True, padx=8, pady=8)

        body_text = tk.Text(
            text_frame,
            height=13,
            width=40,
            wrap="word",
            bg=FIELD_BG,
            fg="white",
            relief="flat",
            insertbackground="white",
            font=("Segoe UI", 10),
            padx=10,
            pady=8,
            state="disabled",
            cursor="arrow",
        )
        body_text.pack(side="left", fill="both", expand=True)

        body_scrollbar = make_scrollbar(text_frame, body_text.yview)
        body_scrollbar.pack(side="left", fill="y")
        body_text.configure(yscrollcommand=body_scrollbar.set)

        self.guide_body_text = body_text

    def run(self):
        self.root.mainloop()

    @staticmethod
    def point_in_circle(px, py, cx, cy, radius):
        return (px - cx) ** 2 + (py - cy) ** 2 <= radius ** 2

    @staticmethod
    def point_in_rect(px, py, rect):
        x1, y1, x2, y2 = rect
        return x1 <= px <= x2 and y1 <= py <= y2

    def open_guide_panel(self, section, page):
        title, body = GUIDE_CONTENT[(section, page)]
        self.guide_panel.title_var.set(title)
        body_text = self.guide_body_text
        body_text.configure(state="normal")
        body_text.delete("1.0", "end")
        body_text.insert("1.0", body)
        body_text.configure(state="disabled")
        self.show_exclusive(self.guide_panel)

    def guide_panel_hide(self):
        self.guide_panel.hide()

    def start_par_batch_unpack(self):
        if self.par_state["running"]:
            messagebox.showinfo("PAR Unpack", "A PAR batch is already running.", parent=self.par_dialog_parent())
            return

        folder_path = filedialog.askdirectory(parent=self.par_dialog_parent())
        if not folder_path:
            return

        update_queue = queue.Queue()
        cancel_event = threading.Event()
        worker_thread = threading.Thread(
            target=run_par_batch_unpack,
            args=(folder_path, update_queue, cancel_event, PAR_MAX_WORKERS),
            daemon=True,
        )

        self.par_state.update(
            root_path=folder_path,
            output_root=None,
            status="Scanning for PAR archives",
            summary="Preparing batch controller",
            progress=0.0,
            running=True,
            cancel_requested=False,
            top_level_jobs=0,
            nested_jobs=0,
            total_jobs=0,
            completed_jobs=0,
            active_jobs=0,
            queued_jobs=0,
            error_count=0,
            thread=worker_thread,
            update_queue=update_queue,
            cancel_event=cancel_event,
        )
        self.reset_par_log(f"Selected {folder_path} for PAR batch unpack.")
        self.refresh_par_widgets()
        self.par_panel.show()

        worker_thread.start()
        self.root.after(PAR_POLL_MS, self.poll_par_updates)

    def par_dialog_parent(self):
        return self.par_panel.window if self.par_panel.visible else self.root

    def cancel_par_batch(self):
        if not self.par_state["running"]:
            return

        cancel_event = self.par_state["cancel_event"]
        if cancel_event is None or cancel_event.is_set():
            return

        cancel_event.set()
        self.par_state["cancel_requested"] = True
        self.par_state["status"] = "Cancelling PAR batch"
        self.append_par_log("Cancellation requested. Waiting for active workers to stop.")
        self.refresh_par_widgets()

    def close_par_panel(self):
        if self.par_state["running"]:
            should_cancel = messagebox.askyesno(
                "Close PAR Unpack",
                "Cancel the current PAR batch and hide the panel?",
                parent=self.par_dialog_parent(),
            )
            if not should_cancel:
                return
            self.cancel_par_batch()

        self.par_panel.hide()

    def poll_par_updates(self):
        update_queue = self.par_state["update_queue"]
        thread = self.par_state["thread"]

        if update_queue is None:
            return

        while True:
            try:
                event = update_queue.get_nowait()
            except queue.Empty:
                break

            event_type = event.get("type")

            if event_type == "log":
                self.append_par_log(event.get("message", ""))
                continue

            if event_type == "state":
                self.apply_par_state_event(event)
                continue

            if event_type == "error":
                self.par_state["running"] = False
                self.par_state["status"] = event.get("message", "PAR batch failed.")
                self.append_par_log(self.par_state["status"])
                messagebox.showerror(
                    "PAR Batch Error",
                    self.par_state["status"],
                    parent=self.par_dialog_parent(),
                )
                continue

            if event_type == "finished":
                self.par_state["running"] = False
                self.par_state["cancel_requested"] = False
                if self.par_state["error_count"] == 0 and self.par_state["total_jobs"] > 0:
                    self.par_state["status"] = "PAR batch unpack finished."
                self.par_state["thread"] = None
                self.par_state["update_queue"] = None
                self.par_state["cancel_event"] = None
                break

        self.refresh_par_widgets()

        if self.par_state["update_queue"] is None:
            return

        if (thread is not None and thread.is_alive()) or not update_queue.empty():
            self.root.after(PAR_POLL_MS, self.poll_par_updates)
            return

        self.par_state["running"] = False
        self.par_state["cancel_requested"] = False
        self.par_state["status"] = "PAR batch stopped without reporting completion."
        self.append_par_log(self.par_state["status"])
        self.par_state["thread"] = None
        self.par_state["update_queue"] = None
        self.par_state["cancel_event"] = None
        self.refresh_par_widgets()

    def apply_par_state_event(self, event):
        par_state = self.par_state
        top_level_jobs = int(event.get("top_level_jobs", par_state["top_level_jobs"]))
        nested_jobs = int(event.get("nested_jobs", par_state["nested_jobs"]))

        par_state["status"] = event.get("status", par_state["status"])
        par_state["output_root"] = event.get("output_root", par_state["output_root"])
        par_state["summary"] = (
            f"{event.get('completed_jobs', 0)}/{event.get('total_jobs', 0)} archives | "
            f"{top_level_jobs} top-level + {nested_jobs} nested | "
            f"{event.get('active_jobs', 0)} active | {event.get('queued_jobs', 0)} queued | "
            f"{event.get('error_count', 0)} errors"
        )
        par_state["progress"] = float(event.get("progress", par_state["progress"]))
        par_state["running"] = bool(event.get("running", par_state["running"]))
        par_state["top_level_jobs"] = top_level_jobs
        par_state["nested_jobs"] = nested_jobs

        for key in ("total_jobs", "completed_jobs", "active_jobs", "queued_jobs", "error_count"):
            par_state[key] = int(event.get(key, par_state[key]))

    def reset_par_log(self, first_message):
        log_text = self.par_widgets["log_text"]
        log_text.configure(state="normal")
        log_text.delete("1.0", "end")
        log_text.insert("1.0", first_message)
        log_text.configure(state="disabled")

    def append_par_log(self, message):
        if not message:
            return

        log_text = self.par_widgets["log_text"]
        log_text.configure(state="normal")
        if log_text.compare("end-1c", "!=", "1.0"):
            log_text.insert("end", "\n")
        log_text.insert("end", message)

        line_count = int(log_text.index("end-1c").split(".")[0])
        if line_count > PAR_LOG_LIMIT:
            log_text.delete("1.0", f"{line_count - PAR_LOG_LIMIT + 1}.0")

        log_text.see("end")
        log_text.configure(state="disabled")

    def refresh_par_widgets(self):
        root_path = self.par_state["root_path"]
        if root_path:
            output_root = self.par_state["output_root"]
            info_lines = [
                os.path.basename(root_path),
                f"In:  {shorten_path_smart(root_path)}",
            ]
            if output_root:
                info_lines.append(f"Out: {shorten_path_smart(output_root)}")
            self.par_widgets["info_var"].set("\n".join(info_lines))
        else:
            self.par_widgets["info_var"].set("No PAR batch running.")

        self.par_widgets["status_var"].set(self.par_state["status"])
        self.par_widgets["summary_var"].set(self.par_state["summary"])
        self.draw_par_progress()

        self.par_widgets["cancel_button"].configure(
            state="normal" if self.par_state["running"] else "disabled",
            text="Cancel" if self.par_state["running"] else "Done",
        )

    def draw_par_progress(self):
        progress_canvas = self.par_widgets["progress_canvas"]
        bar_width = max(progress_canvas.winfo_width(), 1)
        fill_width = int(max(0.0, min(1.0, self.par_state["progress"])) * bar_width)
        progress_canvas.coords(self.par_widgets["progress_fill"], 0, 0, fill_width, 12)

    def draw_title(self):
        self.canvas.create_text(
            WIDTH // 2,
            25,
            text=TITLE,
            fill="#BF98D9",
            font=("Segoe UI", 14, "bold"),
        )

    def draw_main(self):
        buttons = []
        for index, name in enumerate(MAIN_BUTTONS):
            x, y = 60, 120 + index * 100
            radius = 30

            selected = self.ui_state["main"] == name

            self.canvas.create_oval(
                x - radius,
                y - radius,
                x + radius,
                y + radius,
                fill=ACCENT if selected else INACTIVE,
                outline="",
            )

            self.canvas.create_text(
                x,
                y,
                text=name[0],
                fill=TEXT,
                font=("Segoe UI", 12, "bold"),
            )

            buttons.append((name, (x, y, radius)))

        return buttons

    def draw_strip(self):
        if not self.ui_state["main"]:
            return []

        items = SUB_OPTIONS[self.ui_state["main"]]
        buttons = []

        base_x = 140
        base_y = 100

        self.canvas.create_rectangle(
            base_x - 10,
            base_y - 10,
            base_x + 190,
            base_y + len(items) * 60,
            fill=PANEL_2,
            outline="",
        )

        for index, text in enumerate(items):
            y = base_y + index * 60
            selected = self.ui_state["sub"] == text

            self.canvas.create_rectangle(
                base_x,
                y,
                base_x + 180,
                y + 50,
                fill=ACCENT if selected else STRIP,
                outline="",
            )

            self.canvas.create_text(base_x + 90, y + 25, text=text, fill=TEXT)
            buttons.append((text, (base_x, y, base_x + 180, y + 50)))

        return buttons

    def draw_sub_strip(self):
        if not self.ui_state["sub"]:
            return []

        items = SUB_SUB_OPTIONS.get(self.ui_state["sub"], [])
        buttons = []

        base_x = 340
        base_y = 100

        self.canvas.create_rectangle(
            base_x - 10,
            base_y - 10,
            base_x + 190,
            base_y + len(items) * 60,
            fill=PANEL_3,
            outline="",
        )

        for index, text in enumerate(items):
            y = base_y + index * 60

            self.canvas.create_rectangle(
                base_x,
                y,
                base_x + 180,
                y + 50,
                fill="#dddddd",
                outline="",
            )

            self.canvas.create_text(base_x + 90, y + 25, text=text, fill="black")
            buttons.append((text, (base_x, y, base_x + 180, y + 50)))

        return buttons

    def on_left_click(self, event):
        x, y = event.x, event.y

        if y < 50:
            return

        for name, (cx, cy, radius) in self.main_btns:
            if self.point_in_circle(x, y, cx, cy, radius):
                if self.ui_state["main"] == name:
                    self.ui_state["main"] = None
                    self.ui_state["sub"] = None
                else:
                    self.ui_state["main"] = name
                    self.ui_state["sub"] = None

                self.hide_exclusive()
                self.redraw()
                return

        for name, rect in self.sub_btns:
            if self.point_in_rect(x, y, rect):
                if self.ui_state["sub"] == name:
                    self.ui_state["sub"] = None
                else:
                    self.ui_state["sub"] = name

                self.hide_exclusive()
                if self.ui_state["sub"] in EDITOR_SUBS:
                    self.editors[self.ui_state["sub"]].show_panel()
                self.redraw()
                return

        for name, rect in self.sub_sub_btns:
            if self.point_in_rect(x, y, rect):
                self.run_sub_sub_action(self.ui_state["sub"], name)
                return

    def run_sub_sub_action(self, sub, name):
        if (sub, name) in GUIDE_CONTENT:
            self.open_guide_panel(sub, name)
            return

        actions = {
            ("PAR Unpack", "Batch Unpack"): self.start_par_batch_unpack,
            ("BIN Editor", "Open"): self.bin_editor.open_document,
            ("BIN Editor", "Close"): self.bin_editor.close_document,
            ("Shop BINs", "Y0"): lambda: self.shop_editor.open_for_game(game=SHOP_GAME_Y0),
            ("Shop BINs", "Y3"): lambda: self.shop_editor.open_for_game(game=SHOP_GAME_Y3),
            ("Shop BINs", "Close"): self.shop_editor.close_document,
            ("String Table", "Open"): self.string_tbl_editor.open_document,
            ("String Table", "Close"): self.string_tbl_editor.close_document,
        }
        action = actions.get((sub, name))
        if action is not None:
            action()

    def start_drag(self, event):
        self.drag_data["x"] = event.x_root
        self.drag_data["y"] = event.y_root

    def do_drag(self, event):
        dx = event.x_root - self.drag_data["x"]
        dy = event.y_root - self.drag_data["y"]

        x = self.root.winfo_x() + dx
        y = self.root.winfo_y() + dy

        self.root.geometry(f"+{x}+{y}")
        for panel in self.panels:
            if panel.visible:
                panel.apply_geometry((x, y))

        self.drag_data["x"] = event.x_root
        self.drag_data["y"] = event.y_root

    def close_app(self, event=None):
        if any(editor.state["dirty"] for editor in self.editors.values()):
            should_exit = messagebox.askyesno(
                "Exit",
                "There are unsaved edits. Discard them and exit?",
                parent=self.root,
            )
            if not should_exit:
                return

        if self.par_state["running"]:
            self.cancel_par_batch()
            thread = self.par_state["thread"]
            if thread is not None:
                thread.join(timeout=1.0)
        self.root.destroy()

    def toggle_topmost(self, event=None):
        self.topmost = not self.topmost
        self.root.attributes("-topmost", self.topmost)
        for panel in self.panels:
            panel.set_topmost(self.topmost)

    def redraw(self):
        self.canvas.delete("all")

        self.draw_title()
        self.main_btns = self.draw_main()
        self.sub_btns = self.draw_strip()
        self.sub_sub_btns = self.draw_sub_strip()

def run_app():
    app = AwanoApp()
    app.run()
