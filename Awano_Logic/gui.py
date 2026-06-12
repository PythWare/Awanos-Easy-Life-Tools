import io, os, queue, threading
import tkinter as tk
from tkinter import filedialog, messagebox

from .bin import BinFormatError, format_value_for_editor, parse_bin_bytes
from .par_batch import PAR_MAX_WORKERS, run_par_batch_unpack
from .shop_bin import (
    SHOP_GAME_LABELS,
    SHOP_GAME_Y0,
    SHOP_GAME_Y3,
    ShopBinFormatError,
    format_shop_value_for_editor,
    parse_shop_bin_bytes,
)

WIDTH = 900
HEIGHT = 460

BG_COLOR = "#1a1a1a"
ACCENT = "#f4b400"
INACTIVE = "#444"
STRIP = "#666"
TEXT = "white"

PANEL_2 = "#555555"
PANEL_3 = "#ffffff"

TITLE = "Awano's Easy Life Tools"

MAIN_BUTTONS = ["Tools", "Guide"]

SUB_OPTIONS = {
    "Tools": ["BIN Editor", "Shop BINs", "PAR Unpack"],
    "Guide": ["BIN Guide", "Usage Docs"],
}

SUB_SUB_OPTIONS = {
    "BIN Editor": ["Open", "Close"],
    "Shop BINs": ["Y0", "Y3", "Close"],
    "PAR Unpack": ["Batch Unpack"],
    "BIN Guide": ["Info", "Credits"],
    "Usage Docs": ["Usage", "Explanations"],
}

BIN_PANEL_WIDTH = 360
BIN_PANEL_HEIGHT = 420
SHOP_PANEL_WIDTH = 360
SHOP_PANEL_HEIGHT = 420
PAR_PANEL_WIDTH = 360
PAR_PANEL_HEIGHT = 360
GUIDE_PANEL_WIDTH = 360
GUIDE_PANEL_HEIGHT = 300

GUIDE_CONTENT = {
    ("BIN Guide", "Info"): (
        "BIN Guide, Info",
        "Awano has two BIN editors because the files are not the same format.\n\n"
        "BIN Editor opens the older 20070319 files, usually named .bin_c, .bin_j, "
        "or .bin_k. These are table style files with entries and named parameter fields. "
        "The editor keeps the original parameter padding when saving so unchanged files "
        "can round trip cleanly.\n\n"
        "Shop BINs opens Y0 and Y3 shop tables. Those use separate binary layouts. ",
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
        "original load.",
    ),
    ("Usage Docs", "Explanations"): (
        "Usage Docs, Explanations",
        "Entries are the rows in the loaded table. Fields are the values stored for the "
        "selected row.\n\n"
        "Text fields can be longer than the visible area, scroll as needed.\n\n"
        "The 2007 BIN editor has an E button because those tables can be expanded by "
        "duplicating an entry.\n\n"
        "Shop BIN numeric edits should keep the table compact. Description edits may grow "
        "the file because the save path rewrites the string area and updates pointers.",
    ),
}


def shorten_path_smart(path):
    parts = os.fspath(path).split(os.sep)

    if len(parts) >= 2:
        return f"...{os.sep}{parts[-2]}{os.sep}{parts[-1]}"

    return os.fspath(path)


class AwanoApp:
    def __init__(self):
        self.ui_state = {
            "main": None,
            "sub": None,
        }
        self.bin_state = {
            "visible": False,
            "x": 520,
            "y": 40,
            "dragging": False,
            "path": None,
            "last_saved_path": None,
            "document": None,
            "original_document": None,
            "source_buffer": None,
            "expanded_entry_defaults": {},
            "entry_index": 0,
            "parameter_index": 0,
            "dirty": False,
            "status": "Open a 20070319 BIN to start editing.",
        }
        self.shop_state = {
            "visible": False,
            "x": 520,
            "y": 40,
            "dragging": False,
            "path": None,
            "last_saved_path": None,
            "document": None,
            "original_document": None,
            "source_buffer": None,
            "entry_index": 0,
            "field_index": 0,
            "dirty": False,
            "game": SHOP_GAME_Y0,
            "status": "Open a Y0 shop BIN to start editing.",
        }
        self.par_state = {
            "visible": False,
            "x": 520,
            "y": 84,
            "dragging": False,
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
            "logs": [],
            "thread": None,
            "update_queue": None,
            "cancel_event": None,
        }
        self.guide_state = {
            "visible": False,
            "x": 520,
            "y": 76,
            "dragging": False,
            "title": "Guide",
            "text": "",
        }

        self.main_btns = []
        self.sub_btns = []
        self.sub_sub_btns = []
        self.drag_data = {"x": 0, "y": 0}
        self.topmost = True

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

        self.create_bin_widgets()
        self.create_shop_widgets()
        self.create_par_widgets()
        self.create_guide_widgets()
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

    def create_bin_widgets(self):
        panel = tk.Frame(self.root, bg="#0f141b", highlightthickness=0)
        header = tk.Frame(panel, bg="#1c2734", height=28)
        header.pack(fill="x")

        title_label = tk.Label(
            header,
            text="BIN Editor",
            bg="#1c2734",
            fg="white",
            font=("Segoe UI", 10, "bold"),
        )
        title_label.pack(side="left", padx=8, pady=4)

        encoding_button = tk.Button(
            header,
            text="UTF-8",
            command=self.toggle_bin_encoding,
            bg=ACCENT,
            fg="black",
            relief="flat",
            font=("Segoe UI", 8, "bold"),
            activebackground="#ffd663",
        )
        encoding_button.pack(side="right", padx=6, pady=4)

        close_button = tk.Button(
            header,
            text="X",
            command=self.close_bin_document,
            bg="#4a4f57",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#6b7380",
        )
        close_button.pack(side="right", pady=4)

        for widget in (header, title_label):
            widget.bind("<Button-1>", self.start_bin_drag)
            widget.bind("<B1-Motion>", self.do_bin_drag)
            widget.bind("<ButtonRelease-1>", self.stop_bin_drag)

        info_var = tk.StringVar(value="No BIN loaded.")
        status_var = tk.StringVar(value=self.bin_state["status"])
        entry_jump_var = tk.StringVar(value="")

        info_label = tk.Label(
            panel,
            textvariable=info_var,
            bg="#0f141b",
            fg="white",
            anchor="w",
            justify="left",
            wraplength=320,
            font=("Segoe UI", 8, "bold"),
        )
        info_label.pack(fill="x", padx=8, pady=(6, 2))

        path_label = tk.Label(
            panel,
            textvariable=status_var,
            bg="#0f141b",
            fg="#b8c2ce",
            anchor="w",
            justify="left",
            wraplength=320,
            font=("Segoe UI", 8),
        )
        path_label.pack(fill="x", padx=8, pady=(0, 6))

        lists_frame = tk.Frame(panel, bg="#0f141b")
        lists_frame.pack(fill="both", padx=8)

        entry_column = tk.Frame(lists_frame, bg="#0f141b")
        entry_column.pack(side="left", fill="both")

        entry_label = tk.Label(
            entry_column,
            text="Entries",
            bg="#0f141b",
            fg="#dfe7f0",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        entry_label.pack(fill="x", pady=(0, 2))

        entry_list_frame = tk.Frame(entry_column, bg="#0f141b")
        entry_list_frame.pack()

        entry_list = tk.Listbox(
            entry_list_frame,
            exportselection=False,
            width=12,
            height=7,
            bg="#1a212a",
            fg="white",
            relief="flat",
            selectbackground=ACCENT,
            selectforeground="black",
            activestyle="none",
            font=("Consolas", 9),
        )
        entry_list.pack(side="left")
        entry_list.bind("<<ListboxSelect>>", self.on_bin_entry_select)

        entry_scrollbar = tk.Scrollbar(
            entry_list_frame,
            command=entry_list.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        entry_scrollbar.pack(side="left", fill="y")
        entry_list.configure(yscrollcommand=entry_scrollbar.set)

        parameter_column = tk.Frame(lists_frame, bg="#0f141b")
        parameter_column.pack(side="left", fill="both", padx=(8, 0))

        parameter_label = tk.Label(
            parameter_column,
            text="Fields",
            bg="#0f141b",
            fg="#dfe7f0",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        parameter_label.pack(fill="x", pady=(0, 2))

        parameter_list_frame = tk.Frame(parameter_column, bg="#0f141b")
        parameter_list_frame.pack()

        parameter_list = tk.Listbox(
            parameter_list_frame,
            exportselection=False,
            width=24,
            height=7,
            bg="#1a212a",
            fg="white",
            relief="flat",
            selectbackground=ACCENT,
            selectforeground="black",
            activestyle="none",
            font=("Consolas", 9),
        )
        parameter_list.pack(side="left")
        parameter_list.bind("<<ListboxSelect>>", self.on_bin_parameter_select)

        parameter_scrollbar = tk.Scrollbar(
            parameter_list_frame,
            command=parameter_list.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        parameter_scrollbar.pack(side="left", fill="y")
        parameter_list.configure(yscrollcommand=parameter_scrollbar.set)

        jump_row = tk.Frame(panel, bg="#0f141b")
        jump_row.pack(fill="x", padx=8, pady=(8, 4))

        jump_label = tk.Label(
            jump_row,
            text="Jump to Entry",
            bg="#0f141b",
            fg="#e1b85e",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        jump_label.pack(side="left")

        jump_entry = tk.Entry(
            jump_row,
            textvariable=entry_jump_var,
            width=8,
            bg="#1a212a",
            fg="white",
            relief="flat",
            insertbackground="white",
            justify="center",
            font=("Consolas", 9),
        )
        jump_entry.pack(side="left", padx=(8, 0))
        jump_entry.bind("<KeyRelease>", self.on_entry_jump_change)
        jump_entry.bind("<Return>", self.on_entry_jump_change)

        value_row = tk.Frame(panel, bg="#0f141b")
        value_row.pack(fill="x", padx=8)

        editor_label = tk.Label(
            value_row,
            text="Value",
            bg="#0f141b",
            fg="#dfe7f0",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        editor_label.pack(side="left")

        refresh_value_button = tk.Button(
            value_row,
            text="R",
            command=self.refresh_selected_bin_value,
            bg="#4d5c71",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#6e83a1",
        )
        refresh_value_button.pack(side="right")

        create_file_button = tk.Button(
            value_row,
            text="C",
            command=self.save_bin_as,
            bg="#4d6d4f",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#66956a",
        )
        create_file_button.pack(side="right", padx=(0, 4))

        expand_button = tk.Button(
            value_row,
            text="E",
            command=self.expand_bin_document,
            bg="#5b547b",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#7e76a8",
        )
        expand_button.pack(side="right", padx=(0, 4))

        reload_all_button = tk.Button(
            value_row,
            text="RA",
            command=self.reload_all_bin_values,
            bg="#6a4a4a",
            fg="white",
            relief="flat",
            width=4,
            font=("Segoe UI", 8, "bold"),
            activebackground="#8f6161",
        )
        reload_all_button.pack(side="right", padx=(0, 4))

        set_value_button = tk.Button(
            value_row,
            text="S",
            command=self.apply_bin_value,
            bg=ACCENT,
            fg="black",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#ffd663",
        )
        set_value_button.pack(side="right", padx=(0, 4))

        editor_frame = tk.Frame(panel, bg="#0f141b")
        editor_frame.pack(fill="x", padx=8, pady=(2, 8))

        editor = tk.Text(
            editor_frame,
            height=8,
            width=40,
            wrap="word",
            bg="#1a212a",
            fg="white",
            relief="flat",
            insertbackground="white",
            font=("Consolas", 9),
        )
        editor.pack(side="left", fill="x", expand=True)

        editor_scrollbar = tk.Scrollbar(
            editor_frame,
            command=editor.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        editor_scrollbar.pack(side="left", fill="y")
        editor.configure(yscrollcommand=editor_scrollbar.set)

        self.bin_widgets = {
            "panel": panel,
            "info_var": info_var,
            "status_var": status_var,
            "entry_jump_var": entry_jump_var,
            "entry_list": entry_list,
            "parameter_list": parameter_list,
            "editor": editor,
            "encoding_button": encoding_button,
        }

        self.refresh_bin_widgets()

    def create_shop_widgets(self):
        panel = tk.Frame(self.root, bg="#0f141b", highlightthickness=0)
        header = tk.Frame(panel, bg="#1c2734", height=28)
        header.pack(fill="x")

        title_label = tk.Label(
            header,
            text="Shop BINs",
            bg="#1c2734",
            fg="white",
            font=("Segoe UI", 10, "bold"),
        )
        title_label.pack(side="left", padx=8, pady=4)

        close_button = tk.Button(
            header,
            text="X",
            command=self.close_shop_document,
            bg="#4a4f57",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#6b7380",
        )
        close_button.pack(side="right", pady=4)

        for widget in (header, title_label):
            widget.bind("<Button-1>", self.start_shop_drag)
            widget.bind("<B1-Motion>", self.do_shop_drag)
            widget.bind("<ButtonRelease-1>", self.stop_shop_drag)

        info_var = tk.StringVar(value="No shop BIN loaded.")
        status_var = tk.StringVar(value=self.shop_state["status"])
        entry_jump_var = tk.StringVar(value="")

        info_label = tk.Label(
            panel,
            textvariable=info_var,
            bg="#0f141b",
            fg="white",
            anchor="w",
            justify="left",
            wraplength=320,
            font=("Segoe UI", 8, "bold"),
        )
        info_label.pack(fill="x", padx=8, pady=(6, 2))

        status_label = tk.Label(
            panel,
            textvariable=status_var,
            bg="#0f141b",
            fg="#b8c2ce",
            anchor="w",
            justify="left",
            wraplength=320,
            font=("Segoe UI", 8),
        )
        status_label.pack(fill="x", padx=8, pady=(0, 6))

        lists_frame = tk.Frame(panel, bg="#0f141b")
        lists_frame.pack(fill="both", padx=8)

        entry_column = tk.Frame(lists_frame, bg="#0f141b")
        entry_column.pack(side="left", fill="both")

        entry_label = tk.Label(
            entry_column,
            text="Entries",
            bg="#0f141b",
            fg="#dfe7f0",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        entry_label.pack(fill="x", pady=(0, 2))

        entry_list_frame = tk.Frame(entry_column, bg="#0f141b")
        entry_list_frame.pack()

        entry_list = tk.Listbox(
            entry_list_frame,
            exportselection=False,
            width=12,
            height=7,
            bg="#1a212a",
            fg="white",
            relief="flat",
            selectbackground=ACCENT,
            selectforeground="black",
            activestyle="none",
            font=("Consolas", 9),
        )
        entry_list.pack(side="left")
        entry_list.bind("<<ListboxSelect>>", self.on_shop_entry_select)

        entry_scrollbar = tk.Scrollbar(
            entry_list_frame,
            command=entry_list.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        entry_scrollbar.pack(side="left", fill="y")
        entry_list.configure(yscrollcommand=entry_scrollbar.set)

        field_column = tk.Frame(lists_frame, bg="#0f141b")
        field_column.pack(side="left", fill="both", padx=(8, 0))

        field_label = tk.Label(
            field_column,
            text="Fields",
            bg="#0f141b",
            fg="#dfe7f0",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        field_label.pack(fill="x", pady=(0, 2))

        field_list_frame = tk.Frame(field_column, bg="#0f141b")
        field_list_frame.pack()

        field_list = tk.Listbox(
            field_list_frame,
            exportselection=False,
            width=24,
            height=7,
            bg="#1a212a",
            fg="white",
            relief="flat",
            selectbackground=ACCENT,
            selectforeground="black",
            activestyle="none",
            font=("Consolas", 9),
        )
        field_list.pack(side="left")
        field_list.bind("<<ListboxSelect>>", self.on_shop_field_select)

        field_scrollbar = tk.Scrollbar(
            field_list_frame,
            command=field_list.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        field_scrollbar.pack(side="left", fill="y")
        field_list.configure(yscrollcommand=field_scrollbar.set)

        jump_row = tk.Frame(panel, bg="#0f141b")
        jump_row.pack(fill="x", padx=8, pady=(8, 4))

        jump_label = tk.Label(
            jump_row,
            text="Jump to Entry",
            bg="#0f141b",
            fg="#e1b85e",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        jump_label.pack(side="left")

        jump_entry = tk.Entry(
            jump_row,
            textvariable=entry_jump_var,
            width=8,
            bg="#1a212a",
            fg="white",
            relief="flat",
            insertbackground="white",
            justify="center",
            font=("Consolas", 9),
        )
        jump_entry.pack(side="left", padx=(8, 0))
        jump_entry.bind("<KeyRelease>", self.on_shop_entry_jump_change)
        jump_entry.bind("<Return>", self.on_shop_entry_jump_change)

        value_row = tk.Frame(panel, bg="#0f141b")
        value_row.pack(fill="x", padx=8)

        editor_label = tk.Label(
            value_row,
            text="Value",
            bg="#0f141b",
            fg="#dfe7f0",
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        editor_label.pack(side="left")

        refresh_value_button = tk.Button(
            value_row,
            text="R",
            command=self.refresh_selected_shop_value,
            bg="#4d5c71",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#6e83a1",
        )
        refresh_value_button.pack(side="right")

        create_file_button = tk.Button(
            value_row,
            text="C",
            command=self.save_shop_as,
            bg="#4d6d4f",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#66956a",
        )
        create_file_button.pack(side="right", padx=(0, 4))

        reload_all_button = tk.Button(
            value_row,
            text="RA",
            command=self.reload_all_shop_values,
            bg="#6a4a4a",
            fg="white",
            relief="flat",
            width=4,
            font=("Segoe UI", 8, "bold"),
            activebackground="#8f6161",
        )
        reload_all_button.pack(side="right", padx=(0, 4))

        set_value_button = tk.Button(
            value_row,
            text="S",
            command=self.apply_shop_value,
            bg=ACCENT,
            fg="black",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#ffd663",
        )
        set_value_button.pack(side="right", padx=(0, 4))

        editor_frame = tk.Frame(panel, bg="#0f141b")
        editor_frame.pack(fill="x", padx=8, pady=(2, 8))

        editor = tk.Text(
            editor_frame,
            height=8,
            width=40,
            wrap="word",
            bg="#1a212a",
            fg="white",
            relief="flat",
            insertbackground="white",
            font=("Consolas", 9),
        )
        editor.pack(side="left", fill="x", expand=True)

        editor_scrollbar = tk.Scrollbar(
            editor_frame,
            command=editor.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        editor_scrollbar.pack(side="left", fill="y")
        editor.configure(yscrollcommand=editor_scrollbar.set)

        self.shop_widgets = {
            "panel": panel,
            "info_var": info_var,
            "status_var": status_var,
            "entry_jump_var": entry_jump_var,
            "entry_list": entry_list,
            "field_list": field_list,
            "editor": editor,
        }

        self.refresh_shop_widgets()

    def create_par_widgets(self):
        panel = tk.Frame(self.root, bg="#0f141b", highlightthickness=0)
        header = tk.Frame(panel, bg="#1c2734", height=28)
        header.pack(fill="x")

        title_label = tk.Label(
            header,
            text="PAR Unpack",
            bg="#1c2734",
            fg="white",
            font=("Segoe UI", 10, "bold"),
        )
        title_label.pack(side="left", padx=8, pady=4)

        close_button = tk.Button(
            header,
            text="X",
            command=self.close_par_panel,
            bg="#4a4f57",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#6b7380",
        )
        close_button.pack(side="right", padx=6, pady=4)

        for widget in (header, title_label):
            widget.bind("<Button-1>", self.start_par_drag)
            widget.bind("<B1-Motion>", self.do_par_drag)
            widget.bind("<ButtonRelease-1>", self.stop_par_drag)

        info_var = tk.StringVar(value="No PAR batch running.")
        status_var = tk.StringVar(value=self.par_state["status"])
        summary_var = tk.StringVar(value=self.par_state["summary"])

        info_label = tk.Label(
            panel,
            textvariable=info_var,
            bg="#0f141b",
            fg="white",
            anchor="w",
            justify="left",
            wraplength=320,
            font=("Segoe UI", 8, "bold"),
        )
        info_label.pack(fill="x", padx=8, pady=(6, 2))

        status_label = tk.Label(
            panel,
            textvariable=status_var,
            bg="#0f141b",
            fg="#b8c2ce",
            anchor="w",
            justify="left",
            wraplength=320,
            font=("Segoe UI", 8),
        )
        status_label.pack(fill="x", padx=8)

        summary_label = tk.Label(
            panel,
            textvariable=summary_var,
            bg="#0f141b",
            fg="#e1b85e",
            anchor="w",
            justify="left",
            wraplength=320,
            font=("Segoe UI", 8, "bold"),
        )
        summary_label.pack(fill="x", padx=8, pady=(2, 6))

        progress_canvas = tk.Canvas(
            panel,
            height=12,
            bg="#1a212a",
            highlightthickness=0,
            relief="flat",
        )
        progress_canvas.pack(fill="x", padx=8, pady=(0, 6))
        progress_fill = progress_canvas.create_rectangle(0, 0, 0, 12, fill=ACCENT, outline="")

        log_frame = tk.Frame(panel, bg="#0f141b")
        log_frame.pack(fill="both", expand=True, padx=8)

        log_text = tk.Text(
            log_frame,
            height=7,
            wrap="word",
            bg="#1a212a",
            fg="white",
            relief="flat",
            insertbackground="white",
            font=("Consolas", 8),
            state="disabled",
        )
        log_text.pack(side="left", fill="both", expand=True)

        log_scrollbar = tk.Scrollbar(
            log_frame,
            command=log_text.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        log_scrollbar.pack(side="left", fill="y")
        log_text.configure(yscrollcommand=log_scrollbar.set)

        button_row = tk.Frame(panel, bg="#0f141b")
        button_row.pack(fill="x", padx=8, pady=(6, 8))

        cancel_button = tk.Button(
            button_row,
            text="Cancel",
            command=self.cancel_par_batch,
            bg="#6a4a4a",
            fg="white",
            relief="flat",
            width=9,
            font=("Segoe UI", 8, "bold"),
            activebackground="#8f6161",
        )
        cancel_button.pack(side="right")

        self.par_widgets = {
            "panel": panel,
            "info_var": info_var,
            "status_var": status_var,
            "summary_var": summary_var,
            "progress_canvas": progress_canvas,
            "progress_fill": progress_fill,
            "log_text": log_text,
            "cancel_button": cancel_button,
        }

        self.refresh_par_widgets()

    def create_guide_widgets(self):
        panel = tk.Frame(self.root, bg="#0f141b", highlightthickness=0)
        header = tk.Frame(panel, bg="#1c2734", height=28)
        header.pack(fill="x")

        title_var = tk.StringVar(value=self.guide_state["title"])
        title_label = tk.Label(
            header,
            textvariable=title_var,
            bg="#1c2734",
            fg="white",
            font=("Segoe UI", 10, "bold"),
        )
        title_label.pack(side="left", padx=8, pady=4)

        close_button = tk.Button(
            header,
            text="X",
            command=self.close_guide_panel,
            bg="#4a4f57",
            fg="white",
            relief="flat",
            width=3,
            font=("Segoe UI", 8, "bold"),
            activebackground="#6b7380",
        )
        close_button.pack(side="right", padx=6, pady=4)

        for widget in (header, title_label):
            widget.bind("<Button-1>", self.start_guide_drag)
            widget.bind("<B1-Motion>", self.do_guide_drag)
            widget.bind("<ButtonRelease-1>", self.stop_guide_drag)

        text_frame = tk.Frame(panel, bg="#0f141b")
        text_frame.pack(fill="both", expand=True, padx=8, pady=8)

        body_text = tk.Text(
            text_frame,
            height=13,
            width=40,
            wrap="word",
            bg="#1a212a",
            fg="white",
            relief="flat",
            insertbackground="white",
            font=("Segoe UI", 9),
            padx=8,
            pady=6,
            state="disabled",
            cursor="arrow",
        )
        body_text.pack(side="left", fill="both", expand=True)

        body_scrollbar = tk.Scrollbar(
            text_frame,
            command=body_text.yview,
            troughcolor="#121821",
            activebackground="#6e83a1",
        )
        body_scrollbar.pack(side="left", fill="y")
        body_text.configure(yscrollcommand=body_scrollbar.set)

        self.guide_widgets = {
            "panel": panel,
            "title_var": title_var,
            "body_text": body_text,
        }

        self.refresh_guide_widgets()

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
        self.guide_state["title"] = title
        self.guide_state["text"] = body
        self.guide_state["visible"] = True
        self.bin_state["visible"] = False
        self.shop_state["visible"] = False
        self.refresh_guide_widgets()
        self.redraw()

    def close_guide_panel(self):
        self.guide_state["visible"] = False
        self.redraw()

    def refresh_guide_widgets(self):
        self.guide_widgets["title_var"].set(self.guide_state["title"])
        body_text = self.guide_widgets["body_text"]
        body_text.configure(state="normal")
        body_text.delete("1.0", "end")
        body_text.insert("1.0", self.guide_state["text"])
        body_text.configure(state="disabled")

    def start_guide_drag(self, event):
        self.guide_state["dragging"] = True
        self.guide_state["drag_x_root"] = event.x_root
        self.guide_state["drag_y_root"] = event.y_root

    def do_guide_drag(self, event):
        if not self.guide_state.get("dragging"):
            return

        dx = event.x_root - self.guide_state["drag_x_root"]
        dy = event.y_root - self.guide_state["drag_y_root"]

        self.guide_state["x"] += dx
        self.guide_state["y"] += dy
        self.guide_state["drag_x_root"] = event.x_root
        self.guide_state["drag_y_root"] = event.y_root

        self.redraw()

    def stop_guide_drag(self, _event):
        self.guide_state["dragging"] = False

    def open_bin_editor(self):
        file_path = filedialog.askopenfilename(
            filetypes=[
                ("All BIN files", "*.bin_c *.bin_j *.bin_k"),
                ("BIN C files", "*.bin_c"),
                ("BIN J files", "*.bin_j"),
                ("BIN K files", "*.bin_k"),
            ]
        )
        if not file_path:
            return

        self.load_bin_document(file_path)

    def load_bin_document(self, file_path):
        try:
            with open(file_path, "rb") as file_obj:
                source_bytes = file_obj.read()

            source_buffer = io.BytesIO(source_bytes)
            document = parse_bin_bytes(
                source_buffer.getvalue(),
                encoding="auto",
                file_path=file_path,
            )
            original_document = parse_bin_bytes(
                source_buffer.getvalue(),
                encoding=document.encoding,
                file_path=file_path,
            )
        except (BinFormatError, UnicodeDecodeError, OSError) as exc:
            messagebox.showerror("BIN Error", str(exc))
            return

        self.bin_state["document"] = document
        self.bin_state["original_document"] = original_document
        self.bin_state["source_buffer"] = source_buffer
        self.bin_state["expanded_entry_defaults"] = {}
        self.bin_state["path"] = file_path
        self.bin_state["last_saved_path"] = None
        self.bin_state["visible"] = True
        self.bin_state["dirty"] = False
        self.bin_state["entry_index"] = 0
        self.bin_state["parameter_index"] = 0
        self.bin_state["status"] = "BIN loaded."
        self.shop_state["visible"] = False
        self.guide_state["visible"] = False

        self.refresh_bin_widgets()
        self.redraw()

    def hide_bin_panel(self):
        self.bin_state["visible"] = False
        self.redraw()

    def close_bin_document(self):
        if self.bin_state["dirty"]:
            should_close = messagebox.askyesno(
                "Close BIN",
                "Discard the current BIN edits and close it?",
            )
            if not should_close:
                return

        self.bin_state["document"] = None
        self.bin_state["original_document"] = None
        self.bin_state["path"] = None
        self.bin_state["last_saved_path"] = None
        self.bin_state["source_buffer"] = None
        self.bin_state["expanded_entry_defaults"] = {}
        self.bin_state["visible"] = False
        self.bin_state["dirty"] = False
        self.bin_state["entry_index"] = 0
        self.bin_state["parameter_index"] = 0
        self.bin_state["status"] = "Open a 20070319 BIN to start editing."
        self.refresh_bin_widgets()
        self.redraw()

    def toggle_bin_encoding(self):
        document = self.bin_state["document"]
        if document is None:
            return

        document.encoding = "cp932" if document.encoding == "utf-8" else "utf-8"
        self.bin_state["dirty"] = True
        self.bin_state["status"] = f"Save encoding set to {document.encoding.upper()}."
        self.refresh_bin_widgets()

    def start_bin_drag(self, event):
        self.bin_state["dragging"] = True
        self.bin_state["drag_x_root"] = event.x_root
        self.bin_state["drag_y_root"] = event.y_root

    def do_bin_drag(self, event):
        if not self.bin_state.get("dragging"):
            return

        dx = event.x_root - self.bin_state["drag_x_root"]
        dy = event.y_root - self.bin_state["drag_y_root"]

        self.bin_state["x"] += dx
        self.bin_state["y"] += dy
        self.bin_state["drag_x_root"] = event.x_root
        self.bin_state["drag_y_root"] = event.y_root

        self.redraw()

    def stop_bin_drag(self, _event):
        self.bin_state["dragging"] = False

    def on_bin_entry_select(self, _event=None):
        selection = self.bin_widgets["entry_list"].curselection()
        if not selection:
            return

        self.select_bin_entry(selection[0])

    def on_bin_parameter_select(self, _event=None):
        selection = self.bin_widgets["parameter_list"].curselection()
        if not selection:
            return

        self.bin_state["parameter_index"] = selection[0]
        self.load_selected_bin_value()

    def load_selected_bin_value(self):
        document = self.bin_state["document"]
        if document is None or not document.parameters or document.entry_count <= 0:
            self.bin_widgets["editor"].delete("1.0", "end")
            return

        entry_index = min(self.bin_state["entry_index"], document.entry_count - 1)
        parameter_index = min(
            self.bin_state["parameter_index"],
            len(document.parameters) - 1,
        )

        self.bin_state["entry_index"] = entry_index
        self.bin_state["parameter_index"] = parameter_index

        parameter = document.parameters[parameter_index]
        value = document.get_value(entry_index, parameter.name, "")
        display_value = format_value_for_editor(parameter.type_name, value)
        editor = self.bin_widgets["editor"]
        editor.delete("1.0", "end")
        editor.insert("1.0", display_value)

    def refresh_bin_widgets(self):
        document = self.bin_state["document"]
        entry_list = self.bin_widgets["entry_list"]
        parameter_list = self.bin_widgets["parameter_list"]

        entry_list.delete(0, "end")
        parameter_list.delete(0, "end")

        if document is None:
            self.bin_widgets["info_var"].set("No BIN loaded.")
            self.bin_widgets["status_var"].set(self.bin_state["status"])
            self.bin_widgets["entry_jump_var"].set("")
            self.bin_widgets["encoding_button"].configure(text="UTF-8")
            self.bin_widgets["editor"].delete("1.0", "end")
            return

        for entry_index in range(document.entry_count):
            entry_list.insert("end", f"Entry {entry_index:03d}")

        for parameter in document.parameters:
            parameter_list.insert("end", parameter.name)

        self.bin_state["entry_index"] = min(
            self.bin_state["entry_index"],
            max(document.entry_count - 1, 0),
        )
        self.bin_state["parameter_index"] = min(
            self.bin_state["parameter_index"],
            max(len(document.parameters) - 1, 0),
        )

        if document.entry_count:
            self.select_bin_entry(self.bin_state["entry_index"])

        if document.parameters:
            parameter_list.selection_set(self.bin_state["parameter_index"])
            parameter_list.activate(self.bin_state["parameter_index"])

        dirty_marker = " *" if self.bin_state["dirty"] else ""
        filename = os.path.basename(self.bin_state["path"] or document.file_path or "BIN")
        self.bin_widgets["info_var"].set(
            f"{filename}{dirty_marker}\n"
            f"{document.entry_count} entries | {len(document.parameters)} fields | "
            f"{shorten_path_smart(self.bin_state['path'] or document.file_path or filename)}"
        )
        self.bin_widgets["status_var"].set(self.bin_state["status"])
        self.bin_widgets["encoding_button"].configure(text=document.encoding.upper())
        self.load_selected_bin_value()

    def select_bin_entry(self, entry_index, update_jump_var=True):
        document = self.bin_state["document"]
        if document is None or document.entry_count <= 0:
            return

        entry_index = max(0, min(entry_index, document.entry_count - 1))
        self.bin_state["entry_index"] = entry_index

        entry_list = self.bin_widgets["entry_list"]
        entry_list.selection_clear(0, "end")
        entry_list.selection_set(entry_index)
        entry_list.activate(entry_index)
        entry_list.see(entry_index)

        if update_jump_var:
            self.bin_widgets["entry_jump_var"].set(f"{entry_index:03d}")

        self.load_selected_bin_value()

    def on_entry_jump_change(self, _event=None):
        document = self.bin_state["document"]
        if document is None or document.entry_count <= 0:
            return

        raw_value = self.bin_widgets["entry_jump_var"].get().strip()
        if not raw_value or not raw_value.isdigit():
            return

        target_index = int(raw_value)
        if 0 <= target_index < document.entry_count:
            self.select_bin_entry(target_index, update_jump_var=False)

    def apply_bin_value(self):
        self.commit_current_bin_value()

    def commit_current_bin_value(self, show_feedback=True):
        document = self.bin_state["document"]
        if document is None or not document.parameters:
            return False

        parameter = document.parameters[self.bin_state["parameter_index"]]
        raw_value = self.bin_widgets["editor"].get("1.0", "end-1c")

        try:
            document.set_value(
                self.bin_state["entry_index"],
                parameter.name,
                raw_value,
            )
        except (BinFormatError, ValueError) as exc:
            if show_feedback:
                messagebox.showerror("BIN Error", str(exc))
            return False

        self.bin_state["dirty"] = True
        if show_feedback:
            self.bin_state["status"] = (
                f"Updated {parameter.name} for entry {self.bin_state['entry_index']:03d}."
            )
        self.refresh_bin_widgets()
        return True

    def refresh_selected_bin_value(self):
        document = self.bin_state["document"]
        original_document = self.bin_state["original_document"]
        if document is None or original_document is None or not document.parameters:
            return

        parameter = document.parameters[self.bin_state["parameter_index"]]
        entry_index = self.bin_state["entry_index"]

        if entry_index >= original_document.entry_count:
            duplicated_defaults = self.bin_state["expanded_entry_defaults"].get(entry_index, {})

            if parameter.name in duplicated_defaults:
                document.entries[entry_index][parameter.name] = duplicated_defaults[parameter.name]
                self.bin_state["status"] = (
                    f"Restored {parameter.name} for duplicated entry {entry_index:03d}."
                )
            else:
                document.unset_value(entry_index, parameter.name)
                self.bin_state["status"] = (
                    f"Cleared {parameter.name} for duplicated entry {entry_index:03d}."
                )

            self.bin_state["dirty"] = True
            self.refresh_bin_widgets()
            return

        if original_document.has_value(entry_index, parameter.name):
            original_value = original_document.get_value(entry_index, parameter.name)
            document.entries[entry_index][parameter.name] = original_value
        else:
            document.unset_value(entry_index, parameter.name)

        self.bin_state["dirty"] = True
        self.bin_state["status"] = (
            f"Restored {parameter.name} for entry {entry_index:03d} from the original BIN."
        )
        self.refresh_bin_widgets()

    def expand_bin_document(self):
        document = self.bin_state["document"]
        if document is None:
            return

        if document.entry_count <= 0:
            messagebox.showerror(
                "Expand Failed",
                "This BIN has no existing entries to duplicate yet.",
            )
            return

        if document.parameters and not self.commit_current_bin_value(show_feedback=False):
            messagebox.showerror(
                "Expand Failed",
                "The current value could not be saved into memory. Fix it before duplicating an entry.",
            )
            return

        source_entry_index = self.bin_state["entry_index"]
        source_entry = dict(document.entries[source_entry_index])
        new_entry_index = document.append_entry(source_entry=source_entry)
        self.bin_state["expanded_entry_defaults"][new_entry_index] = dict(source_entry)
        self.bin_state["dirty"] = True
        self.bin_state["entry_index"] = new_entry_index
        self.bin_state["status"] = (
            f"Duplicated entry {source_entry_index:03d} into entry {new_entry_index:03d}."
        )
        self.refresh_bin_widgets()

    def reload_all_bin_values(self):
        source_buffer = self.bin_state["source_buffer"]
        original_document = self.bin_state["original_document"]
        if source_buffer is None or original_document is None:
            return

        if self.bin_state["dirty"]:
            should_reload = messagebox.askyesno(
                "Reload All",
                "Discard all current BIN edits and reload the original values?",
            )
            if not should_reload:
                return

        try:
            reloaded_document = parse_bin_bytes(
                source_buffer.getvalue(),
                encoding=original_document.encoding,
                file_path=self.bin_state["path"],
            )
        except (BinFormatError, UnicodeDecodeError) as exc:
            messagebox.showerror("Reload Failed", str(exc))
            return

        current_entry_index = self.bin_state["entry_index"]
        current_parameter_index = self.bin_state["parameter_index"]

        self.bin_state["document"] = reloaded_document
        self.bin_state["expanded_entry_defaults"] = {}
        self.bin_state["dirty"] = False
        self.bin_state["entry_index"] = current_entry_index
        self.bin_state["parameter_index"] = current_parameter_index
        self.bin_state["status"] = "Reloaded the in-memory BIN from the original file."
        self.refresh_bin_widgets()

    def save_bin_as(self):
        document = self.bin_state["document"]
        if document is None:
            return

        if not self.commit_current_bin_value(show_feedback=False):
            messagebox.showerror(
                "Save Failed",
                "The current value could not be saved into memory. Fix it before saving the BIN.",
            )
            return

        default_name = os.path.basename(
            self.bin_state["last_saved_path"]
            or self.bin_state["path"]
            or document.file_path
            or "edited.bin"
        )
        output_path = filedialog.asksaveasfilename(
            defaultextension=".bin_c",
            filetypes=[
                ("All BIN files", "*.bin_c *.bin_j *.bin_k"),
                ("BIN C files", "*.bin_c"),
                ("BIN J files", "*.bin_j"),
                ("BIN K files", "*.bin_k")
            ],
            initialfile=default_name,
        )

        if not output_path:
            return

        try:
            output_bytes = document.to_bytes(encoding=document.encoding)
            output_buffer = io.BytesIO(output_bytes)
            with open(output_path, "wb") as file_obj:
                file_obj.write(output_buffer.getvalue())
        except (BinFormatError, OSError, UnicodeEncodeError) as exc:
            messagebox.showerror("Save Failed", str(exc))
            return

        self.bin_state["last_saved_path"] = output_path
        self.bin_state["dirty"] = False
        self.bin_state["status"] = f"Created BIN at {shorten_path_smart(output_path)}."
        self.refresh_bin_widgets()

    def open_shop_bin_editor(self, game=None):
        target_game = game or self.shop_state["game"]
        file_path = filedialog.askopenfilename(
            title=f"Open {SHOP_GAME_LABELS[target_game]} shop BIN",
            filetypes=[
                ("Shop BIN files", "*.bin"),
                ("All files", "*.*"),
            ]
        )
        if not file_path:
            return

        if self.shop_state["dirty"]:
            should_open = messagebox.askyesno(
                "Open Shop BIN",
                "Discard the current shop BIN edits and open another file?",
            )
            if not should_open:
                return

        previous_game = self.shop_state["game"]
        self.shop_state["game"] = target_game
        if not self.load_shop_document(file_path):
            self.shop_state["game"] = previous_game
            self.refresh_shop_widgets()

    def load_shop_document(self, file_path):
        try:
            with open(file_path, "rb") as file_obj:
                source_bytes = file_obj.read()

            return self.load_shop_document_from_bytes(file_path, source_bytes)
        except OSError as exc:
            messagebox.showerror("Shop BIN Error", str(exc))
            return False

    def load_shop_document_from_bytes(self, file_path, source_bytes):
        try:
            source_buffer = io.BytesIO(source_bytes)
            document = parse_shop_bin_bytes(
                source_buffer.getvalue(),
                game=self.shop_state["game"],
                encoding="auto",
                file_path=file_path,
            )
            original_document = parse_shop_bin_bytes(
                source_buffer.getvalue(),
                game=self.shop_state["game"],
                encoding=document.encoding,
                file_path=file_path,
            )
        except (ShopBinFormatError, UnicodeDecodeError) as exc:
            messagebox.showerror("Shop BIN Error", str(exc))
            return False

        self.shop_state["document"] = document
        self.shop_state["original_document"] = original_document
        self.shop_state["source_buffer"] = source_buffer
        self.shop_state["path"] = file_path
        self.shop_state["last_saved_path"] = None
        self.shop_state["visible"] = True
        self.shop_state["dirty"] = False
        self.shop_state["entry_index"] = 0
        self.shop_state["field_index"] = 0
        self.shop_state["status"] = f"{SHOP_GAME_LABELS[self.shop_state['game']]} shop BIN loaded."
        self.bin_state["visible"] = False
        self.guide_state["visible"] = False

        self.refresh_shop_widgets()
        self.redraw()
        return True

    def close_shop_document(self):
        if self.shop_state["dirty"]:
            should_close = messagebox.askyesno(
                "Close Shop BIN",
                "Discard the current shop BIN edits and close it?",
            )
            if not should_close:
                return

        self.shop_state["document"] = None
        self.shop_state["original_document"] = None
        self.shop_state["path"] = None
        self.shop_state["last_saved_path"] = None
        self.shop_state["source_buffer"] = None
        self.shop_state["visible"] = False
        self.shop_state["dirty"] = False
        self.shop_state["entry_index"] = 0
        self.shop_state["field_index"] = 0
        self.shop_state["status"] = (
            f"Open a {SHOP_GAME_LABELS[self.shop_state['game']]} shop BIN to start editing."
        )
        self.refresh_shop_widgets()
        self.redraw()

    def start_shop_drag(self, event):
        self.shop_state["dragging"] = True
        self.shop_state["drag_x_root"] = event.x_root
        self.shop_state["drag_y_root"] = event.y_root

    def do_shop_drag(self, event):
        if not self.shop_state.get("dragging"):
            return

        dx = event.x_root - self.shop_state["drag_x_root"]
        dy = event.y_root - self.shop_state["drag_y_root"]

        self.shop_state["x"] += dx
        self.shop_state["y"] += dy
        self.shop_state["drag_x_root"] = event.x_root
        self.shop_state["drag_y_root"] = event.y_root

        self.redraw()

    def stop_shop_drag(self, _event):
        self.shop_state["dragging"] = False

    def on_shop_entry_select(self, _event=None):
        selection = self.shop_widgets["entry_list"].curselection()
        if not selection:
            return

        self.select_shop_entry(selection[0])

    def on_shop_field_select(self, _event=None):
        selection = self.shop_widgets["field_list"].curselection()
        if not selection:
            return

        self.shop_state["field_index"] = selection[0]
        self.load_selected_shop_value()

    def refresh_shop_widgets(self):
        document = self.shop_state["document"]
        entry_list = self.shop_widgets["entry_list"]
        field_list = self.shop_widgets["field_list"]

        entry_list.delete(0, "end")
        field_list.delete(0, "end")

        if document is None:
            self.shop_widgets["info_var"].set("No shop BIN loaded.")
            self.shop_widgets["status_var"].set(self.shop_state["status"])
            self.shop_widgets["entry_jump_var"].set("")
            self.shop_widgets["editor"].delete("1.0", "end")
            return

        for entry_index in range(document.entry_count):
            entry_list.insert("end", document.entry_label(entry_index))

        self.shop_state["entry_index"] = min(
            self.shop_state["entry_index"],
            max(document.entry_count - 1, 0),
        )

        if document.entry_count:
            entry_list.selection_set(self.shop_state["entry_index"])
            entry_list.activate(self.shop_state["entry_index"])
            entry_list.see(self.shop_state["entry_index"])
            self.populate_shop_fields()

        dirty_marker = " *" if self.shop_state["dirty"] else ""
        filename = os.path.basename(self.shop_state["path"] or document.file_path or "Shop BIN")
        self.shop_widgets["info_var"].set(
            f"{filename}{dirty_marker}\n"
            f"{SHOP_GAME_LABELS[document.game]} | {document.shared_count} shared | "
            f"{document.item_count} items | {shorten_path_smart(self.shop_state['path'] or document.file_path or filename)}"
        )
        self.shop_widgets["status_var"].set(self.shop_state["status"])
        self.load_selected_shop_value()

    def populate_shop_fields(self):
        document = self.shop_state["document"]
        field_list = self.shop_widgets["field_list"]
        field_list.delete(0, "end")

        if document is None or document.entry_count <= 0:
            return

        field_names = document.field_names_for_entry(self.shop_state["entry_index"])
        for field_name in field_names:
            field_list.insert("end", field_name)

        self.shop_state["field_index"] = min(
            self.shop_state["field_index"],
            max(len(field_names) - 1, 0),
        )

        if field_names:
            field_list.selection_set(self.shop_state["field_index"])
            field_list.activate(self.shop_state["field_index"])

    def select_shop_entry(self, entry_index, update_jump_var=True):
        document = self.shop_state["document"]
        if document is None or document.entry_count <= 0:
            return

        entry_index = max(0, min(entry_index, document.entry_count - 1))
        self.shop_state["entry_index"] = entry_index
        self.shop_state["field_index"] = 0

        entry_list = self.shop_widgets["entry_list"]
        entry_list.selection_clear(0, "end")
        entry_list.selection_set(entry_index)
        entry_list.activate(entry_index)
        entry_list.see(entry_index)

        if update_jump_var:
            self.shop_widgets["entry_jump_var"].set(f"{entry_index:03d}")

        self.populate_shop_fields()
        self.load_selected_shop_value()

    def on_shop_entry_jump_change(self, _event=None):
        document = self.shop_state["document"]
        if document is None or document.entry_count <= 0:
            return

        raw_value = self.shop_widgets["entry_jump_var"].get().strip()
        if not raw_value or not raw_value.isdigit():
            return

        target_index = int(raw_value)
        if 0 <= target_index < document.entry_count:
            self.select_shop_entry(target_index, update_jump_var=False)

    def get_selected_shop_field_name(self):
        document = self.shop_state["document"]
        if document is None or document.entry_count <= 0:
            return None

        field_names = document.field_names_for_entry(self.shop_state["entry_index"])
        if not field_names:
            return None

        self.shop_state["field_index"] = min(
            self.shop_state["field_index"],
            len(field_names) - 1,
        )
        return field_names[self.shop_state["field_index"]]

    def load_selected_shop_value(self):
        document = self.shop_state["document"]
        field_name = self.get_selected_shop_field_name()
        if document is None or field_name is None:
            self.shop_widgets["editor"].delete("1.0", "end")
            return

        value = document.get_value(self.shop_state["entry_index"], field_name)
        display_value = format_shop_value_for_editor(value)
        editor = self.shop_widgets["editor"]
        editor.delete("1.0", "end")
        editor.insert("1.0", display_value)

    def apply_shop_value(self):
        self.commit_current_shop_value()

    def commit_current_shop_value(self, show_feedback=True):
        document = self.shop_state["document"]
        field_name = self.get_selected_shop_field_name()
        if document is None or field_name is None:
            return False

        raw_value = self.shop_widgets["editor"].get("1.0", "end-1c")
        try:
            document.set_value(
                self.shop_state["entry_index"],
                field_name,
                raw_value,
            )
        except (ShopBinFormatError, UnicodeEncodeError, ValueError) as exc:
            if show_feedback:
                messagebox.showerror("Shop BIN Error", str(exc))
            return False

        self.shop_state["dirty"] = True
        if show_feedback:
            self.shop_state["status"] = (
                f"Updated {field_name} for entry {self.shop_state['entry_index']:03d}."
            )
        self.refresh_shop_widgets()
        return True

    def refresh_selected_shop_value(self):
        document = self.shop_state["document"]
        original_document = self.shop_state["original_document"]
        field_name = self.get_selected_shop_field_name()
        if document is None or original_document is None or field_name is None:
            return

        entry_index = self.shop_state["entry_index"]
        if entry_index >= original_document.entry_count:
            return

        try:
            original_value = original_document.get_value(entry_index, field_name)
            document.set_value(entry_index, field_name, original_value)
        except (ShopBinFormatError, IndexError, ValueError) as exc:
            messagebox.showerror("Restore Failed", str(exc))
            return

        self.shop_state["dirty"] = True
        self.shop_state["status"] = (
            f"Restored {field_name} for entry {entry_index:03d} from the original shop BIN."
        )
        self.refresh_shop_widgets()

    def reload_all_shop_values(self):
        source_buffer = self.shop_state["source_buffer"]
        original_document = self.shop_state["original_document"]
        if source_buffer is None or original_document is None:
            return

        if self.shop_state["dirty"]:
            should_reload = messagebox.askyesno(
                "Reload Shop BIN",
                "Discard all current shop BIN edits and reload the original values?",
            )
            if not should_reload:
                return

        try:
            reloaded_document = parse_shop_bin_bytes(
                source_buffer.getvalue(),
                game=self.shop_state["game"],
                encoding=original_document.encoding,
                file_path=self.shop_state["path"],
            )
        except (ShopBinFormatError, UnicodeDecodeError) as exc:
            messagebox.showerror("Reload Failed", str(exc))
            return

        current_entry_index = self.shop_state["entry_index"]
        current_field_index = self.shop_state["field_index"]

        self.shop_state["document"] = reloaded_document
        self.shop_state["dirty"] = False
        self.shop_state["entry_index"] = current_entry_index
        self.shop_state["field_index"] = current_field_index
        self.shop_state["status"] = "Reloaded the in-memory shop BIN from the original file."
        self.refresh_shop_widgets()

    def save_shop_as(self):
        document = self.shop_state["document"]
        if document is None:
            return

        if not self.commit_current_shop_value(show_feedback=False):
            messagebox.showerror(
                "Save Failed",
                "The current value could not be saved into memory. Fix it before saving the shop BIN.",
            )
            return

        default_name = os.path.basename(
            self.shop_state["last_saved_path"]
            or self.shop_state["path"]
            or document.file_path
            or "edited_shop.bin"
        )
        output_path = filedialog.asksaveasfilename(
            defaultextension=".bin",
            filetypes=[
                ("Shop BIN files", "*.bin"),
                ("All files", "*.*"),
            ],
            initialfile=default_name,
        )

        if not output_path:
            return

        try:
            output_bytes = document.to_bytes(encoding=document.encoding)
            output_buffer = io.BytesIO(output_bytes)
            with open(output_path, "wb") as file_obj:
                file_obj.write(output_buffer.getvalue())
        except (ShopBinFormatError, OSError, UnicodeEncodeError) as exc:
            messagebox.showerror("Save Failed", str(exc))
            return

        self.shop_state["last_saved_path"] = output_path
        self.shop_state["dirty"] = False
        self.shop_state["status"] = f"Created shop BIN at {shorten_path_smart(output_path)}."
        self.refresh_shop_widgets()

    def start_par_drag(self, event):
        self.par_state["dragging"] = True
        self.par_state["drag_x_root"] = event.x_root
        self.par_state["drag_y_root"] = event.y_root

    def do_par_drag(self, event):
        if not self.par_state.get("dragging"):
            return

        dx = event.x_root - self.par_state["drag_x_root"]
        dy = event.y_root - self.par_state["drag_y_root"]

        self.par_state["x"] += dx
        self.par_state["y"] += dy
        self.par_state["drag_x_root"] = event.x_root
        self.par_state["drag_y_root"] = event.y_root

        self.redraw()

    def stop_par_drag(self, _event):
        self.par_state["dragging"] = False

    def start_par_batch_unpack(self):
        if self.par_state["running"]:
            messagebox.showinfo("PAR Unpack", "A PAR batch is already running.")
            return

        folder_path = filedialog.askdirectory()
        if not folder_path:
            return

        update_queue = queue.Queue()
        cancel_event = threading.Event()
        worker_thread = threading.Thread(
            target=run_par_batch_unpack,
            args=(folder_path, update_queue, cancel_event, PAR_MAX_WORKERS),
            daemon=True,
        )

        self.par_state["root_path"] = folder_path
        self.par_state["output_root"] = None
        self.par_state["status"] = "Scanning for PAR archives..."
        self.par_state["summary"] = "Preparing batch controller..."
        self.par_state["progress"] = 0.0
        self.par_state["running"] = True
        self.par_state["cancel_requested"] = False
        self.par_state["top_level_jobs"] = 0
        self.par_state["nested_jobs"] = 0
        self.par_state["total_jobs"] = 0
        self.par_state["completed_jobs"] = 0
        self.par_state["active_jobs"] = 0
        self.par_state["queued_jobs"] = 0
        self.par_state["error_count"] = 0
        self.par_state["logs"] = [f"Selected {folder_path} for PAR batch unpack."]
        self.par_state["thread"] = worker_thread
        self.par_state["update_queue"] = update_queue
        self.par_state["cancel_event"] = cancel_event
        self.par_state["visible"] = True

        self.refresh_par_widgets()
        self.redraw()

        worker_thread.start()
        self.root.after(100, self.poll_par_updates)

    def cancel_par_batch(self):
        if not self.par_state["running"]:
            return

        cancel_event = self.par_state["cancel_event"]
        if cancel_event is None or cancel_event.is_set():
            return

        cancel_event.set()
        self.par_state["cancel_requested"] = True
        self.par_state["status"] = "Cancelling PAR batch..."
        self.append_par_log("Cancellation requested. Waiting for active workers to stop.")
        self.refresh_par_widgets()

    def close_par_panel(self):
        if self.par_state["running"]:
            should_cancel = messagebox.askyesno(
                "Close PAR Unpack",
                "Cancel the current PAR batch and hide the panel?",
            )
            if not should_cancel:
                return
            self.cancel_par_batch()

        self.par_state["visible"] = False
        self.redraw()

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
                self.par_state["status"] = event.get("status", self.par_state["status"])
                self.par_state["output_root"] = event.get("output_root", self.par_state["output_root"])
                top_level_jobs = int(event.get("top_level_jobs", self.par_state["top_level_jobs"]))
                nested_jobs = int(event.get("nested_jobs", self.par_state["nested_jobs"]))
                self.par_state["summary"] = (
                    f"{event.get('completed_jobs', 0)} / {event.get('total_jobs', 0)} archives | "
                    f"{top_level_jobs} top-level + {nested_jobs} nested | "
                    f"{event.get('active_jobs', 0)} active | {event.get('queued_jobs', 0)} queued | "
                    f"{event.get('error_count', 0)} errors"
                )
                self.par_state["progress"] = float(event.get("progress", self.par_state["progress"]))
                self.par_state["running"] = bool(event.get("running", self.par_state["running"]))
                self.par_state["top_level_jobs"] = top_level_jobs
                self.par_state["nested_jobs"] = nested_jobs
                self.par_state["total_jobs"] = int(event.get("total_jobs", self.par_state["total_jobs"]))
                self.par_state["completed_jobs"] = int(event.get("completed_jobs", self.par_state["completed_jobs"]))
                self.par_state["active_jobs"] = int(event.get("active_jobs", self.par_state["active_jobs"]))
                self.par_state["queued_jobs"] = int(event.get("queued_jobs", self.par_state["queued_jobs"]))
                self.par_state["error_count"] = int(event.get("error_count", self.par_state["error_count"]))
                continue

            if event_type == "error":
                self.par_state["running"] = False
                self.par_state["status"] = event.get("message", "PAR batch failed.")
                self.append_par_log(self.par_state["status"])
                messagebox.showerror("PAR Batch Error", self.par_state["status"])
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
        self.redraw()

        if thread is not None and thread.is_alive():
            self.root.after(100, self.poll_par_updates)

    def append_par_log(self, message):
        if not message:
            return

        self.par_state["logs"].append(message)
        self.par_state["logs"] = self.par_state["logs"][-120:]

        log_text = self.par_widgets["log_text"]
        log_text.configure(state="normal")
        log_text.delete("1.0", "end")
        log_text.insert("1.0", "\n".join(self.par_state["logs"]))
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

        progress_canvas = self.par_widgets["progress_canvas"]
        progress_canvas.update_idletasks()
        bar_width = max(progress_canvas.winfo_width(), 1)
        fill_width = int(max(0.0, min(1.0, self.par_state["progress"])) * bar_width)
        progress_canvas.coords(self.par_widgets["progress_fill"], 0, 0, fill_width, 12)

        cancel_button = self.par_widgets["cancel_button"]
        cancel_button.configure(
            state="normal" if self.par_state["running"] else "disabled",
            text="Cancel" if self.par_state["running"] else "Done",
        )

        log_text = self.par_widgets["log_text"]
        log_text.configure(state="normal")
        log_text.delete("1.0", "end")
        if self.par_state["logs"]:
            log_text.insert("1.0", "\n".join(self.par_state["logs"]))
            log_text.see("end")
        log_text.configure(state="disabled")

    def draw_par_panel(self):
        if not self.par_state["visible"]:
            return

        base_x = self.par_state["x"]
        base_y = self.par_state["y"]

        self.canvas.create_rectangle(
            base_x,
            base_y,
            base_x + PAR_PANEL_WIDTH,
            base_y + PAR_PANEL_HEIGHT,
            fill="#202833",
            outline="",
        )
        self.canvas.create_rectangle(
            base_x + 3,
            base_y + 3,
            base_x + PAR_PANEL_WIDTH - 3,
            base_y + PAR_PANEL_HEIGHT - 3,
            outline="#3a4656",
        )
        self.canvas.create_window(
            base_x + 6,
            base_y + 6,
            anchor="nw",
            window=self.par_widgets["panel"],
            width=PAR_PANEL_WIDTH - 12,
            height=PAR_PANEL_HEIGHT - 12,
        )

    def draw_bin_editor(self):
        if not self.bin_state["visible"]:
            return

        base_x = self.bin_state["x"]
        base_y = self.bin_state["y"]

        self.canvas.create_rectangle(
            base_x,
            base_y,
            base_x + BIN_PANEL_WIDTH,
            base_y + BIN_PANEL_HEIGHT,
            fill="#202833",
            outline="",
        )
        self.canvas.create_rectangle(
            base_x + 3,
            base_y + 3,
            base_x + BIN_PANEL_WIDTH - 3,
            base_y + BIN_PANEL_HEIGHT - 3,
            outline="#3a4656",
        )
        self.canvas.create_window(
            base_x + 6,
            base_y + 6,
            anchor="nw",
            window=self.bin_widgets["panel"],
            width=BIN_PANEL_WIDTH - 12,
            height=BIN_PANEL_HEIGHT - 12,
        )

    def draw_shop_editor(self):
        if not self.shop_state["visible"]:
            return

        base_x = self.shop_state["x"]
        base_y = self.shop_state["y"]

        self.canvas.create_rectangle(
            base_x,
            base_y,
            base_x + SHOP_PANEL_WIDTH,
            base_y + SHOP_PANEL_HEIGHT,
            fill="#202833",
            outline="",
        )
        self.canvas.create_rectangle(
            base_x + 3,
            base_y + 3,
            base_x + SHOP_PANEL_WIDTH - 3,
            base_y + SHOP_PANEL_HEIGHT - 3,
            outline="#3a4656",
        )
        self.canvas.create_window(
            base_x + 6,
            base_y + 6,
            anchor="nw",
            window=self.shop_widgets["panel"],
            width=SHOP_PANEL_WIDTH - 12,
            height=SHOP_PANEL_HEIGHT - 12,
        )

    def draw_guide_panel(self):
        if not self.guide_state["visible"]:
            return

        base_x = self.guide_state["x"]
        base_y = self.guide_state["y"]

        self.canvas.create_rectangle(
            base_x,
            base_y,
            base_x + GUIDE_PANEL_WIDTH,
            base_y + GUIDE_PANEL_HEIGHT,
            fill="#202833",
            outline="",
        )
        self.canvas.create_rectangle(
            base_x + 3,
            base_y + 3,
            base_x + GUIDE_PANEL_WIDTH - 3,
            base_y + GUIDE_PANEL_HEIGHT - 3,
            outline="#3a4656",
        )
        self.canvas.create_window(
            base_x + 6,
            base_y + 6,
            anchor="nw",
            window=self.guide_widgets["panel"],
            width=GUIDE_PANEL_WIDTH - 12,
            height=GUIDE_PANEL_HEIGHT - 12,
        )

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

                self.bin_state["visible"] = False
                self.shop_state["visible"] = False
                self.guide_state["visible"] = False
                self.redraw()
                return

        for name, rect in self.sub_btns:
            if self.point_in_rect(x, y, rect):
                if self.ui_state["sub"] == name:
                    self.ui_state["sub"] = None
                else:
                    self.ui_state["sub"] = name

                self.bin_state["visible"] = False
                self.shop_state["visible"] = False
                self.guide_state["visible"] = False
                self.redraw()
                return

        for name, rect in self.sub_sub_btns:
            if self.point_in_rect(x, y, rect):
                if (self.ui_state["sub"], name) in GUIDE_CONTENT:
                    self.open_guide_panel(self.ui_state["sub"], name)
                    return

                if self.ui_state["sub"] == "PAR Unpack" and name == "Batch Unpack":
                    self.start_par_batch_unpack()
                    return

                if self.ui_state["sub"] == "BIN Editor" and name == "Open":
                    self.open_bin_editor()
                    return

                if self.ui_state["sub"] == "BIN Editor" and name == "Close":
                    self.close_bin_document()
                    return

                if self.ui_state["sub"] == "Shop BINs" and name == "Y0":
                    self.open_shop_bin_editor(game=SHOP_GAME_Y0)
                    return

                if self.ui_state["sub"] == "Shop BINs" and name == "Y3":
                    self.open_shop_bin_editor(game=SHOP_GAME_Y3)
                    return

                if self.ui_state["sub"] == "Shop BINs" and name == "Close":
                    self.close_shop_document()
                    return

                return

    def start_drag(self, event):
        self.drag_data["x"] = event.x_root
        self.drag_data["y"] = event.y_root

    def do_drag(self, event):
        dx = event.x_root - self.drag_data["x"]
        dy = event.y_root - self.drag_data["y"]

        x = self.root.winfo_x() + dx
        y = self.root.winfo_y() + dy

        self.root.geometry(f"+{x}+{y}")

        self.drag_data["x"] = event.x_root
        self.drag_data["y"] = event.y_root

    def close_app(self, _event=None):
        if self.par_state["running"]:
            self.cancel_par_batch()
            thread = self.par_state["thread"]
            if thread is not None:
                thread.join(timeout=1.0)
        self.root.destroy()

    def toggle_topmost(self, _event=None):
        self.topmost = not self.topmost
        self.root.attributes("-topmost", self.topmost)

    def redraw(self):
        self.canvas.delete("all")

        self.draw_title()
        self.main_btns = self.draw_main()
        self.sub_btns = self.draw_strip()
        self.sub_sub_btns = self.draw_sub_strip()
        self.draw_par_panel()
        self.draw_bin_editor()
        self.draw_shop_editor()
        self.draw_guide_panel()


def run_app():
    app = AwanoApp()
    app.run()
