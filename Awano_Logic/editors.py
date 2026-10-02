import os, struct
import tkinter as tk
from array import array
from tkinter import filedialog, messagebox
from .bin import BinFormatError, format_value_for_editor, parse_bin_bytes
from .search_index import SEPARATOR, SearchIndex
from .shop_bin import (
    SHOP_GAME_LABELS,
    SHOP_GAME_Y0,
    ShopBinFormatError,
    format_shop_value_for_editor,
    parse_shop_bin_bytes,
)
from .string_tbl import (
    StringTableFormatError,
    format_string_tbl_value_for_editor,
    parse_string_tbl_bytes,
)
from .widgets import (
    ACCENT,
    ACCENT_ACTIVE,
    EDITOR_FONT,
    FIELD_BG,
    GOLD_FG,
    HEADING_FG,
    LIST_FONT,
    MUTED_FG,
    PANEL_BG,
    FloatingPanel,
    ToggleButton,
    VirtualList,
    make_button,
    make_scrollbar,
)

EDITOR_PANEL_WIDTH = 1000
EDITOR_PANEL_HEIGHT = 680
EDITOR_PANEL_X = 540
EDITOR_PANEL_Y = 40
SEARCH_DELAY_MS = 120
SNIPPET_CONTEXT = 32
SNIPPET_LIMIT = 140
HIGHLIGHT_LIMIT = 2000

def shorten_path_smart(path):
    parts = os.fspath(path).split(os.sep)

    if len(parts) >= 2:
        return f"{os.sep}{parts[-2]}{os.sep}{parts[-1]}"

    return os.fspath(path)

def build_snippet(text, query, case_sensitive):
    haystack = text if case_sensitive else text.lower()
    position = max(haystack.find(query if case_sensitive else query.lower()), 0)
    start = max(0, position - SNIPPET_CONTEXT)
    end = min(len(text), start + SNIPPET_LIMIT)
    snippet = " ".join(text[start:end].split())

    if start > 0:
        snippet = "..." + snippet
    if end < len(text):
        snippet += "..."
    return snippet

class EditorPanel:
    title = "Editor"
    title_noun = "File"
    document_noun = "file"
    entries_heading = "Entries"
    fields_heading = "Fields"
    jump_heading = "Jump to Entry"
    jump_digits = 3
    error_title = "Editor Error"
    empty_info = "No file loaded."
    loaded_status = "File loaded."
    format_error = ValueError
    commit_errors = (ValueError,)
    open_title = None
    open_filetypes = [("All files", "*.*")]
    save_extension = ".bin"
    save_filetypes = [("All files", "*.*")]
    fallback_name = "edited.bin"
    reset_field_on_entry_change = True
    skip_unchanged_on_apply = False
    column_widths = (180, 260)

    def __init__(self, app):
        self.app = app
        self.state = {
            "path": None,
            "last_saved_path": None,
            "document": None,
            "original_document": None,
            "source_bytes": None,
            "entry_index": 0,
            "field_index": 0,
            "dirty": False,
            "status": self.idle_status(),
            "loaded_text": "",
            "loaded_bytes": None,
        }
        self.search_index = SearchIndex()
        self.search_matches = array("q")
        self.search_truncated = False
        self.search_query = ""
        self.search_job = None

        self.panel = FloatingPanel(
            app.root,
            self.title,
            EDITOR_PANEL_WIDTH,
            EDITOR_PANEL_HEIGHT,
            EDITOR_PANEL_X,
            EDITOR_PANEL_Y,
            self.close_document,
            min_width=560,
            min_height=400,
        )
        self.build_widgets()
        self.panel.window.bind("<Control-f>", self.focus_search)
        app.register_panel(self.panel)
        self.refresh()

    def build_widgets(self):
        body = self.panel.body
        self.build_header_extras(self.panel.header)

        self.info_var = tk.StringVar()
        self.status_var = tk.StringVar()
        self.length_var = tk.StringVar()
        self.results_heading_var = tk.StringVar(value="Results")
        self.hit_length = tk.IntVar(master=body)

        self.info_label = tk.Label(
            body,
            textvariable=self.info_var,
            bg=PANEL_BG,
            fg="white",
            anchor="w",
            justify="left",
            font=("Segoe UI", 8, "bold"),
        )
        self.info_label.pack(fill="x", padx=8, pady=(6, 2))

        self.status_label = tk.Label(
            body,
            textvariable=self.status_var,
            bg=PANEL_BG,
            fg=MUTED_FG,
            anchor="w",
            justify="left",
            font=("Segoe UI", 8),
        )
        self.status_label.pack(fill="x", padx=8, pady=(0, 6))
        body.bind("<Configure>", self.on_body_resize)

        self.build_search_row(body)

        split = tk.PanedWindow(
            body,
            orient="vertical",
            bg=PANEL_BG,
            sashwidth=6,
            borderwidth=0,
            sashrelief="flat",
            opaqueresize=True,
        )
        split.pack(fill="both", expand=True, padx=8, pady=(0, 2))

        columns = tk.PanedWindow(
            split,
            orient="horizontal",
            bg=PANEL_BG,
            sashwidth=6,
            borderwidth=0,
            sashrelief="flat",
            opaqueresize=True,
        )
        entries_column, self.entries_list = self.build_list_column(
            columns, self.entries_heading, self.on_entry_list_select
        )
        fields_column, self.fields_list = self.build_list_column(
            columns, self.fields_heading, self.on_field_list_select
        )
        results_column, self.results_list = self.build_list_column(
            columns, self.results_heading_var, self.on_result_select
        )
        columns.add(entries_column, width=self.column_widths[0], minsize=90, stretch="never")
        columns.add(fields_column, width=self.column_widths[1], minsize=120, stretch="never")
        columns.add(results_column, minsize=160, stretch="always")

        split.add(columns, height=250, minsize=110, stretch="always")
        split.add(self.build_value_area(split), minsize=120, stretch="always")

    def build_search_row(self, body):
        row = tk.Frame(body, bg=PANEL_BG)
        row.pack(fill="x", padx=8, pady=(0, 6))

        search_label = tk.Label(
            row,
            text="Search",
            bg=PANEL_BG,
            fg=GOLD_FG,
            font=("Segoe UI", 8, "bold"),
        )
        search_label.pack(side="left")

        self.jump_var = tk.StringVar()
        jump_entry = tk.Entry(
            row,
            textvariable=self.jump_var,
            width=8,
            bg=FIELD_BG,
            fg="white",
            relief="flat",
            insertbackground="white",
            justify="center",
            font=LIST_FONT,
        )
        jump_entry.pack(side="right", padx=(8, 0))
        jump_entry.bind("<KeyRelease>", self.on_jump_change)
        jump_entry.bind("<Return>", self.on_jump_change)

        jump_label = tk.Label(
            row,
            text=self.jump_heading,
            bg=PANEL_BG,
            fg=GOLD_FG,
            font=("Segoe UI", 8, "bold"),
        )
        jump_label.pack(side="right", padx=(16, 0))

        self.case_toggle = ToggleButton(row, "Aa", self.on_search_option_change, width=3)
        self.case_toggle.button.pack(side="right", padx=(4, 0))

        self.exact_toggle = ToggleButton(row, "Exact", self.on_search_option_change, width=5)
        self.exact_toggle.button.pack(side="right", padx=(8, 0))

        self.search_var = tk.StringVar()
        self.search_entry = tk.Entry(
            row,
            textvariable=self.search_var,
            bg=FIELD_BG,
            fg="white",
            relief="flat",
            insertbackground="white",
            font=LIST_FONT,
        )
        self.search_entry.pack(side="left", fill="x", expand=True, padx=(8, 0), ipady=2)
        self.search_entry.bind("<Return>", lambda event: self.step_result(1))
        self.search_entry.bind("<Shift-Return>", lambda event: self.step_result(-1))
        self.search_entry.bind("<Escape>", self.clear_search)
        self.search_var.trace_add("write", self.on_search_change)

    def build_list_column(self, parent, heading, on_select):
        column = tk.Frame(parent, bg=PANEL_BG)
        heading_option = (
            {"textvariable": heading} if isinstance(heading, tk.StringVar) else {"text": heading}
        )
        heading_label = tk.Label(
            column,
            bg=PANEL_BG,
            fg=HEADING_FG,
            anchor="w",
            font=("Segoe UI", 8, "bold"),
            **heading_option,
        )
        heading_label.pack(fill="x", pady=(0, 2))

        virtual_list = VirtualList(column, on_select)
        virtual_list.frame.pack(fill="both", expand=True)
        return column, virtual_list

    def build_value_area(self, parent):
        area = tk.Frame(parent, bg=PANEL_BG)

        value_row = tk.Frame(area, bg=PANEL_BG)
        value_row.pack(fill="x", pady=(6, 2))

        value_label = tk.Label(
            value_row,
            text="Value",
            bg=PANEL_BG,
            fg=HEADING_FG,
            anchor="w",
            font=("Segoe UI", 8, "bold"),
        )
        value_label.pack(side="left")

        length_label = tk.Label(
            value_row,
            textvariable=self.length_var,
            bg=PANEL_BG,
            fg=MUTED_FG,
            font=("Segoe UI", 8),
        )
        length_label.pack(side="left", padx=(10, 0))

        for position, (text, command, bg, active_bg, fg, width) in enumerate(
            reversed(self.value_buttons())
        ):
            button = make_button(value_row, text, command, bg, active_bg, fg=fg, width=width)
            button.pack(side="right", padx=(0, 0 if position == 0 else 4))

        editor_frame = tk.Frame(area, bg=PANEL_BG)
        editor_frame.pack(fill="both", expand=True, pady=(2, 0))

        self.editor = tk.Text(
            editor_frame,
            height=4,
            width=20,
            wrap="word",
            bg=FIELD_BG,
            fg="white",
            relief="flat",
            insertbackground="white",
            font=EDITOR_FONT,
            undo=True,
            padx=6,
            pady=4,
        )
        self.editor.pack(side="left", fill="both", expand=True)
        self.editor.tag_configure("search_hit", background="#7a5c00", foreground="white")
        self.editor.tag_raise("sel")
        self.editor.bind("<KeyRelease>", self.update_length_label)

        editor_scrollbar = make_scrollbar(editor_frame, self.editor.yview)
        editor_scrollbar.pack(side="left", fill="y")
        self.editor.configure(yscrollcommand=editor_scrollbar.set)
        return area

    def value_buttons(self):
        return [
            ("S", self.apply_value, ACCENT, ACCENT_ACTIVE, "black", 3),
            ("RA", self.reload_all_values, "#6a4a4a", "#8f6161", "white", 4),
            *self.extra_value_buttons(),
            ("C", self.save_as, "#4d6d4f", "#66956a", "white", 3),
            ("R", self.restore_selected_value, "#4d5c71", "#6e83a1", "white", 3),
        ]

    def build_header_extras(self, header):
        pass

    def refresh_header_extras(self):
        pass

    def extra_value_buttons(self):
        return []

    def document_replaced(self):
        pass

    def loaded_message(self):
        return self.loaded_status

    def saved_status(self, output_path, output_bytes):
        return f"Created {self.document_noun} at {shorten_path_smart(output_path)}."

    def entry_count(self):
        document = self.state["document"]
        return 0 if document is None else document.entry_count

    def result_entry_label(self, entry_index):
        return self.entry_label(entry_index)

    def result_field_label(self, entry_index, field_index):
        return self.field_label(entry_index, field_index)

    def iter_search_texts(self):
        for entry_index in range(self.entry_count()):
            yield [
                self.value_text(entry_index, field_index)
                for field_index in range(self.field_count(entry_index))
            ]

    def value_changed(self, entry_index, field_index):
        self.search_index.update(entry_index, field_index, self.value_text(entry_index, field_index))

    def display_name(self, fallback):
        document = self.state["document"]
        return os.path.basename(self.state["path"] or document.file_path or fallback)

    def display_path(self, fallback):
        document = self.state["document"]
        return shorten_path_smart(self.state["path"] or document.file_path or fallback)

    def bad_marker(self):
        return " *" if self.state["dirty"] else ""

    def format_jump(self, entry_index):
        return f"{entry_index:0{self.jump_digits}d}"

    def dialog_parent(self):
        return self.panel.window if self.panel.visible else self.app.root

    def show_error(self, title, message):
        messagebox.showerror(title, message, parent=self.dialog_parent())

    def ask_yes_no(self, title, message):
        return messagebox.askyesno(title, message, parent=self.dialog_parent())

    def ask_open_path(self, title=None):
        options = {"parent": self.dialog_parent(), "filetypes": self.open_filetypes}
        if title:
            options["title"] = title
        return filedialog.askopenfilename(**options)

    def confirm_open_discard(self):
        if not self.state["dirty"]:
            return True

        return self.ask_yes_no(
            f"Open {self.title_noun}",
            f"Discard the current {self.document_noun} edits and open another file?",
        )

    def show_panel(self):
        if self.state["document"] is not None:
            self.app.show_exclusive(self.panel)

    def open_document(self):
        file_path = self.ask_open_path(self.open_title)
        if not file_path or not self.confirm_open_discard():
            return False

        return self.load_document(file_path)

    def load_document(self, file_path):
        try:
            with open(file_path, "rb") as file_obj:
                source_bytes = file_obj.read()
        except OSError as exc:
            self.show_error(self.error_title, str(exc))
            return False

        return self.load_document_bytes(file_path, source_bytes)

    def load_document_bytes(self, file_path, source_bytes):
        try:
            document = self.parse(source_bytes, "auto", file_path)
            original_document = self.parse(source_bytes, document.encoding, file_path)
        except (self.format_error, UnicodeDecodeError, struct.error) as exc:
            self.show_error(self.error_title, str(exc))
            return False

        self.state.update(
            document=document,
            original_document=original_document,
            source_bytes=source_bytes,
            path=file_path,
            last_saved_path=None,
            dirty=False,
            entry_index=0,
            field_index=0,
            status=self.loaded_message(),
        )
        self.document_replaced()
        self.search_index.invalidate()
        self.refresh()
        self.app.show_exclusive(self.panel)
        return True

    def close_document(self):
        if self.state["dirty"] and not self.ask_yes_no(
            f"Close {self.title_noun}",
            f"Discard the current {self.document_noun} edits and close it?",
        ):
            return

        self.state.update(
            document=None,
            original_document=None,
            source_bytes=None,
            path=None,
            last_saved_path=None,
            dirty=False,
            entry_index=0,
            field_index=0,
        )
        self.state["status"] = self.idle_status()
        self.document_replaced()
        self.search_index.invalidate()
        self.refresh()
        self.panel.hide()

    def reload_all_values(self):
        source_bytes = self.state["source_bytes"]
        original_document = self.state["original_document"]
        if source_bytes is None or original_document is None:
            return

        if self.state["dirty"] and not self.ask_yes_no(
            f"Reload {self.title_noun}",
            f"Discard all current {self.document_noun} edits and reload the original values?",
        ):
            return

        try:
            reloaded_document = self.parse(
                source_bytes,
                original_document.encoding,
                self.state["path"],
            )
        except (self.format_error, UnicodeDecodeError, struct.error) as exc:
            self.show_error("Reload Failed", str(exc))
            return

        self.state["document"] = reloaded_document
        self.state["dirty"] = False
        self.state["status"] = (
            f"Reloaded the in-memory {self.document_noun} from the original file."
        )
        self.document_replaced()
        self.search_index.invalidate()
        self.refresh()

    def save_as(self):
        document = self.state["document"]
        if document is None:
            return

        if not self.commit_current_value(show_feedback=False):
            self.show_error(
                "Save Failed",
                "The current value couldnt be saved into memory. "
                f"Fix it before saving the {self.document_noun}.",
            )
            return

        default_name = os.path.basename(
            self.state["last_saved_path"]
            or self.state["path"]
            or document.file_path
            or self.fallback_name
        )
        output_path = filedialog.asksaveasfilename(
            parent=self.dialog_parent(),
            defaultextension=self.save_extension,
            filetypes=self.save_filetypes,
            initialfile=default_name,
        )
        if not output_path:
            return

        try:
            output_bytes = document.to_bytes(encoding=document.encoding)
            with open(output_path, "wb") as file_obj:
                file_obj.write(output_bytes)
        except (self.format_error, OSError, UnicodeEncodeError, struct.error) as exc:
            self.show_error("Save Failed", str(exc))
            return

        self.state["last_saved_path"] = output_path
        self.state["dirty"] = False
        self.state["status"] = self.saved_status(output_path, output_bytes)
        self.refresh()

    def apply_value(self):
        self.commit_current_value()

    def commit_current_value(self, show_feedback=True):
        if self.state["document"] is None:
            return False

        location = self.current_location()
        if location is None:
            return True

        raw_value = self.editor.get("1.0", "end-1c")
        if raw_value == self.state["loaded_text"] and (
            not show_feedback or self.skip_unchanged_on_apply
        ):
            return True

        try:
            self.store_value(*location, raw_value)
        except self.commit_errors as exc:
            if show_feedback:
                self.show_error(self.error_title, str(exc))
            return False

        self.state["dirty"] = True
        if show_feedback:
            self.state["status"] = self.updated_status(*location)
        self.value_changed(*location)
        self.refresh()
        return True

    def current_location(self):
        if self.entry_count() <= 0:
            return None

        entry_index = self.state["entry_index"]
        field_count = self.field_count(entry_index)
        if field_count <= 0:
            return None

        self.state["field_index"] = min(self.state["field_index"], field_count - 1)
        return entry_index, self.state["field_index"]

    def refresh(self):
        document = self.state["document"]
        self.refresh_header_extras()
        self.status_var.set(self.state["status"])

        if document is None:
            self.info_var.set(self.empty_info)
            self.jump_var.set("")
            self.entries_list.set_items(0, None)
            self.fields_list.set_items(0, None)
        else:
            entry_count = self.entry_count()
            self.state["entry_index"] = max(0, min(self.state["entry_index"], entry_count - 1))
            self.entries_list.set_items(
                entry_count,
                self.entry_label,
                self.state["entry_index"] if entry_count else -1,
            )
            if entry_count:
                self.jump_var.set(self.format_jump(self.state["entry_index"]))
            self.populate_fields()
            self.info_var.set(self.info_text())

        self.load_selected_value()
        self.run_search(keep_position=True)

    def populate_fields(self):
        if self.entry_count() <= 0:
            self.fields_list.set_items(0, None)
            return

        entry_index = self.state["entry_index"]
        field_count = self.field_count(entry_index)
        self.state["field_index"] = max(0, min(self.state["field_index"], field_count - 1))
        self.fields_list.set_items(
            field_count,
            lambda field_index: self.field_label(entry_index, field_index),
            self.state["field_index"] if field_count else -1,
        )

    def select_entry(self, entry_index, field_index=None, update_jump=True):
        entry_count = self.entry_count()
        if entry_count <= 0:
            return

        entry_index = max(0, min(entry_index, entry_count - 1))
        self.state["entry_index"] = entry_index
        if field_index is not None:
            self.state["field_index"] = field_index
        elif self.reset_field_on_entry_change:
            self.state["field_index"] = 0

        self.entries_list.select(entry_index)
        if update_jump:
            self.jump_var.set(self.format_jump(entry_index))

        self.populate_fields()
        self.load_selected_value()

    def on_entry_list_select(self, entry_index):
        self.select_entry(entry_index)

    def on_field_list_select(self, field_index):
        self.state["field_index"] = field_index
        self.load_selected_value()

    def on_jump_change(self, event=None):
        entry_count = self.entry_count()
        raw_value = self.jump_var.get().strip()
        if entry_count <= 0 or not raw_value.isdigit():
            return

        target_index = int(raw_value)
        if 0 <= target_index < entry_count:
            self.select_entry(target_index, update_jump=False)

    def load_selected_value(self):
        location = self.current_location()
        text = "" if location is None else self.value_text(*location)

        self.editor.delete("1.0", "end")
        if text:
            self.editor.insert("1.0", text)
        self.editor.edit_reset()

        self.state["loaded_text"] = text
        self.state["loaded_bytes"] = self.encoded_length(text)
        self.update_length_label()
        self.highlight_editor_matches()

    def encoded_length(self, text):
        document = self.state["document"]
        if document is None:
            return None

        try:
            return len(text.encode(document.encoding))
        except UnicodeEncodeError:
            return None

    def update_length_label(self, event=None):
        document = self.state["document"]
        if document is None:
            self.length_var.set("")
            return

        text = self.editor.get("1.0", "end-1c")
        encoding_label = document.encoding.upper()
        byte_count = self.encoded_length(text)
        if byte_count is None:
            self.length_var.set(f"{len(text):,} chars | not valid {encoding_label}")
            return

        details = f"{len(text):,} chars | {byte_count:,} bytes {encoding_label}"
        loaded_bytes = self.state["loaded_bytes"]
        if loaded_bytes is not None and byte_count != loaded_bytes:
            details += f" ({byte_count - loaded_bytes:+,d})"
        self.length_var.set(details)

    def on_body_resize(self, event):
        wrap_length = max(event.width - 24, 120)
        self.info_label.configure(wraplength=wrap_length)
        self.status_label.configure(wraplength=wrap_length)

    def focus_search(self, event=None):
        self.search_entry.focus_set()
        self.search_entry.select_range(0, "end")
        return "break"

    def clear_search(self, event=None):
        self.search_var.set("")
        self.run_search()
        return "break"

    def on_search_change(self, *args):
        if self.search_job is not None:
            self.panel.window.after_cancel(self.search_job)
        self.search_job = self.panel.window.after(SEARCH_DELAY_MS, self.run_search)

    def on_search_option_change(self):
        self.run_search()

    def run_search(self, keep_position=False):
        if self.search_job is not None:
            self.panel.window.after_cancel(self.search_job)
            self.search_job = None

        query = self.search_var.get().replace(SEPARATOR, "")
        previous_selection = self.results_list.selected if keep_position else -1

        if not query or self.state["document"] is None:
            self.search_query = ""
            self.search_matches = array("q")
            self.search_truncated = False
        else:
            if self.search_index.stale:
                self.search_index.rebuild(self.iter_search_texts())
            self.search_query = query
            self.search_matches, self.search_truncated = self.search_index.search(
                query,
                exact=self.exact_toggle.value,
                case_sensitive=self.case_toggle.value,
            )

        match_count = len(self.search_matches)
        if self.search_query:
            overflow = "+" if self.search_truncated else ""
            noun = "match" if match_count == 1 else "matches"
            self.results_heading_var.set(f"Results  {match_count:,}{overflow} {noun}")
        else:
            self.results_heading_var.set("Results")

        self.results_list.set_items(
            match_count,
            self.result_label,
            min(previous_selection, match_count - 1),
        )
        self.highlight_editor_matches()

    def result_label(self, result_index):
        record = self.search_matches[result_index]
        if record >= len(self.search_index.texts):
            return ""

        entry_index, field_index = self.search_index.locate(record)
        snippet = build_snippet(
            self.search_index.text_at(record),
            self.search_query,
            self.case_toggle.value,
        )
        return (
            f"{self.result_entry_label(entry_index)} | "
            f"{self.result_field_label(entry_index, field_index)} | {snippet}"
        )

    def on_result_select(self, result_index):
        if result_index >= len(self.search_matches):
            return

        record = self.search_matches[result_index]
        if record >= len(self.search_index.texts):
            return

        entry_index, field_index = self.search_index.locate(record)
        self.select_entry(entry_index, field_index)

    def step_result(self, delta):
        if self.search_job is not None:
            self.run_search()

        match_count = len(self.search_matches)
        if match_count == 0:
            return "break"

        current = self.results_list.selected
        if current >= 0:
            target = (current + delta) % match_count
        else:
            target = 0 if delta > 0 else match_count - 1
        self.results_list.choose(target)
        return "break"

    def highlight_editor_matches(self):
        editor = self.editor
        editor.tag_remove("search_hit", "1.0", "end")
        query = self.search_query
        if not query or self.state["document"] is None:
            return

        case_sensitive = self.case_toggle.value
        if self.exact_toggle.value:
            text = editor.get("1.0", "end-1c")
            same = text == query if case_sensitive else text.lower() == query.lower()
            if same:
                editor.tag_add("search_hit", "1.0", "end-1c")
            return

        start = "1.0"
        for attempt in range(HIGHLIGHT_LIMIT):
            position = editor.search(
                query,
                start,
                stopindex="end",
                nocase=not case_sensitive,
                count=self.hit_length,
            )
            length = self.hit_length.get()
            if not position or length <= 0:
                return

            start = f"{position}+{length}c"
            editor.tag_add("search_hit", position, start)

class BinEditor(EditorPanel):
    title = "BIN Editor"
    title_noun = "BIN"
    document_noun = "BIN"
    error_title = "BIN Error"
    empty_info = "No BIN loaded."
    loaded_status = "BIN loaded."
    format_error = BinFormatError
    commit_errors = (BinFormatError, ValueError)
    open_filetypes = [
        ("All BIN files", "*.bin *.bin_c *.bin_j *.bin_k"),
        ("BIN files", "*.bin"),
        ("BIN C files", "*.bin_c"),
        ("BIN J files", "*.bin_j"),
        ("BIN K files", "*.bin_k"),
    ]
    save_extension = ".bin_c"
    save_filetypes = open_filetypes
    fallback_name = "edited.bin"
    reset_field_on_entry_change = False
    column_widths = (150, 240)

    def __init__(self, app):
        self.expanded_entry_defaults = {}
        super().__init__(app)

    def idle_status(self):
        return "Open a 20070319 BIN to start editing."

    def parse(self, data, encoding, file_path):
        return parse_bin_bytes(data, encoding=encoding, file_path=file_path)

    def build_header_extras(self, header):
        self.encoding_button = make_button(
            header,
            "UTF-8",
            self.toggle_encoding,
            ACCENT,
            ACCENT_ACTIVE,
            fg="black",
            width=6,
        )
        self.encoding_button.pack(side="right", padx=(0, 2), pady=4)

    def refresh_header_extras(self):
        document = self.state["document"]
        self.encoding_button.configure(
            text="UTF-8" if document is None else document.encoding.upper()
        )

    def extra_value_buttons(self):
        return [("E", self.expand_document, "#5b547b", "#7e76a8", "white", 3)]

    def document_replaced(self):
        self.expanded_entry_defaults = {}

    def field_count(self, entry_index):
        return len(self.state["document"].parameters)

    def entry_label(self, entry_index):
        return f"Entry {entry_index:03d}"

    def field_label(self, entry_index, field_index):
        return self.state["document"].parameters[field_index].name

    def value_text(self, entry_index, field_index):
        document = self.state["document"]
        parameter = document.parameters[field_index]
        return format_value_for_editor(
            parameter_type_name(parameter),
            document.get_value(entry_index, parameter.name, ""),
        )

    def iter_search_texts(self):
        document = self.state["document"]
        columns = [
            (parameter.name, parameter_type_name(parameter))
            for parameter in document.parameters
        ]
        for entry in document.entries:
            yield [
                format_value_for_editor(type_name, entry.get(name, ""))
                for name, type_name in columns
            ]

    def store_value(self, entry_index, field_index, raw_value):
        document = self.state["document"]
        document.set_value(entry_index, document.parameters[field_index].name, raw_value)

    def updated_status(self, entry_index, field_index):
        parameter_name = self.state["document"].parameters[field_index].name
        return f"Updated {parameter_name} for entry {entry_index:03d}."

    def info_text(self):
        document = self.state["document"]
        filename = self.display_name("BIN")
        return (
            f"{filename}{self.bad_marker()}\n"
            f"{document.entry_count} entries | {len(document.parameters)} fields | "
            f"{self.display_path(filename)}"
        )

    def toggle_encoding(self):
        document = self.state["document"]
        if document is None:
            return

        document.encoding = "cp932" if document.encoding == "utf-8" else "utf-8"
        self.state["dirty"] = True
        self.state["status"] = f"Save encodin set to {document.encoding.upper()}."
        self.refresh()

    def restore_selected_value(self):
        document = self.state["document"]
        original_document = self.state["original_document"]
        location = self.current_location()
        if document is None or original_document is None or location is None:
            return

        entry_index, field_index = location
        parameter = document.parameters[field_index]

        if entry_index >= original_document.entry_count:
            duplicated_defaults = self.expanded_entry_defaults.get(entry_index, {})
            if parameter.name in duplicated_defaults:
                document.entries[entry_index][parameter.name] = duplicated_defaults[parameter.name]
                self.state["status"] = (
                    f"Restored {parameter.name} for duplicated entry {entry_index:03d}."
                )
            else:
                document.unset_value(entry_index, parameter.name)
                self.state["status"] = (
                    f"Cleared {parameter.name} for duplicated entry {entry_index:03d}."
                )
        else:
            if original_document.has_value(entry_index, parameter.name):
                document.entries[entry_index][parameter.name] = original_document.get_value(
                    entry_index, parameter.name
                )
            else:
                document.unset_value(entry_index, parameter.name)
            self.state["status"] = (
                f"Restored {parameter.name} for entry {entry_index:03d} from the original BIN."
            )

        self.state["dirty"] = True
        self.value_changed(entry_index, field_index)
        self.refresh()

    def expand_document(self):
        document = self.state["document"]
        if document is None:
            return

        if document.entry_count <= 0:
            self.show_error(
                "Expand Failed",
                "This BIN has no existing entries to duplicate yet.",
            )
            return

        if not self.commit_current_value(show_feedback=False):
            self.show_error(
                "Expand Failed",
                "The current value couldnt be saved into memory. Fix it before duplicating an entry.",
            )
            return

        source_entry_index = self.state["entry_index"]
        source_entry = dict(document.entries[source_entry_index])
        new_entry_index = document.append_entry(source_entry=source_entry)
        self.expanded_entry_defaults[new_entry_index] = dict(source_entry)
        self.state["dirty"] = True
        self.state["entry_index"] = new_entry_index
        self.state["status"] = (
            f"Duplicated entry {source_entry_index:03d} into entry {new_entry_index:03d}."
        )
        self.search_index.invalidate()
        self.refresh()

class ShopEditor(EditorPanel):
    title = "Shop BINs"
    title_noun = "Shop BIN"
    document_noun = "shop BIN"
    error_title = "Shop BIN Error"
    empty_info = "No shop BIN loaded."
    format_error = ShopBinFormatError
    commit_errors = (ShopBinFormatError, UnicodeEncodeError, ValueError)
    open_filetypes = [
        ("Shop BIN files", "*.bin"),
        ("All files", "*.*"),
    ]
    save_extension = ".bin"
    save_filetypes = open_filetypes
    fallback_name = "edited_shop.bin"
    column_widths = (150, 200)

    def __init__(self, app):
        self.game = SHOP_GAME_Y0
        super().__init__(app)

    def idle_status(self):
        return f"Open a {SHOP_GAME_LABELS[self.game]} shop BIN to start editing."

    def loaded_message(self):
        return f"{SHOP_GAME_LABELS[self.game]} shop BIN loaded."

    def parse(self, data, encoding, file_path):
        return parse_shop_bin_bytes(data, game=self.game, encoding=encoding, file_path=file_path)

    def open_for_game(self, game=None):
        target_game = game or self.game
        file_path = self.ask_open_path(f"Open {SHOP_GAME_LABELS[target_game]} shop BIN")
        if not file_path or not self.confirm_open_discard():
            return

        previous_game = self.game
        self.game = target_game
        if not self.load_document(file_path):
            self.game = previous_game
            self.refresh()

    def field_names(self, entry_index):
        return self.state["document"].field_names_for_entry(entry_index)

    def field_count(self, entry_index):
        return len(self.field_names(entry_index))

    def entry_label(self, entry_index):
        return self.state["document"].entry_label(entry_index)

    def field_label(self, entry_index, field_index):
        return self.field_names(entry_index)[field_index]

    def value_text(self, entry_index, field_index):
        document = self.state["document"]
        return format_shop_value_for_editor(
            document.get_value(entry_index, self.field_names(entry_index)[field_index])
        )

    def iter_search_texts(self):
        document = self.state["document"]
        for entry_index in range(document.entry_count):
            yield [
                format_shop_value_for_editor(document.get_value(entry_index, field_name))
                for field_name in document.field_names_for_entry(entry_index)
            ]

    def value_changed(self, entry_index, field_index):
        self.search_index.invalidate()

    def store_value(self, entry_index, field_index, raw_value):
        self.state["document"].set_value(
            entry_index,
            self.field_names(entry_index)[field_index],
            raw_value,
        )

    def updated_status(self, entry_index, field_index):
        field_name = self.field_names(entry_index)[field_index]
        return f"Updated {field_name} for entry {entry_index:03d}."

    def info_text(self):
        document = self.state["document"]
        filename = self.display_name("Shop BIN")
        return (
            f"{filename}{self.bad_marker()}\n"
            f"{SHOP_GAME_LABELS[document.game]} | {document.shared_count} shared | "
            f"{document.item_count} items | {self.display_path(filename)}"
        )

    def restore_selected_value(self):
        document = self.state["document"]
        original_document = self.state["original_document"]
        location = self.current_location()
        if document is None or original_document is None or location is None:
            return

        entry_index, field_index = location
        if entry_index >= original_document.entry_count:
            return

        field_name = self.field_names(entry_index)[field_index]
        try:
            original_value = original_document.get_value(entry_index, field_name)
            document.set_value(entry_index, field_name, original_value)
        except (ShopBinFormatError, IndexError, ValueError) as exc:
            self.show_error("Restore Failed", str(exc))
            return

        self.state["dirty"] = True
        self.state["status"] = (
            f"Restored {field_name} for entry {entry_index:03d} from the original shop BIN."
        )
        self.value_changed(entry_index, field_index)
        self.refresh()

class StringTableEditor(EditorPanel):
    title = "String Table"
    title_noun = "String Table"
    document_noun = "string table"
    entries_heading = "Groups"
    fields_heading = "Strings"
    jump_heading = "Jump to Group"
    jump_digits = 4
    error_title = "String Table Error"
    empty_info = "No string table loaded."
    loaded_status = "String table loaded."
    format_error = StringTableFormatError
    commit_errors = (UnicodeEncodeError,)
    open_title = "Open string table"
    open_filetypes = [
        ("String table", "string_tbl*.bin"),
        ("BIN files", "*.bin"),
        ("All files", "*.*"),
    ]
    save_extension = ".bin"
    save_filetypes = open_filetypes
    fallback_name = "string_tbl.bin"
    skip_unchanged_on_apply = True
    column_widths = (250, 300)

    def idle_status(self):
        return "Open a string_tbl.bin to start editing."

    def parse(self, data, encoding, file_path):
        return parse_string_tbl_bytes(data, encoding=encoding, file_path=file_path)

    def field_count(self, entry_index):
        return len(self.state["document"].groups[entry_index])

    def entry_label(self, entry_index):
        return self.state["document"].entry_label(entry_index)

    def field_label(self, entry_index, field_index):
        return self.state["document"].field_label(entry_index, field_index)

    def result_entry_label(self, entry_index):
        return f"Group {entry_index:04d}"

    def result_field_label(self, entry_index, field_index):
        return f"String {field_index:03d}"

    def value_text(self, entry_index, field_index):
        return format_string_tbl_value_for_editor(
            self.state["document"].get_value(entry_index, field_index)
        )

    def iter_search_texts(self):
        for group in self.state["document"].groups:
            yield ["" if value is None else value for value in group]

    def store_value(self, entry_index, field_index, raw_value):
        document = self.state["document"]
        raw_value.encode(document.encoding)
        document.set_value(entry_index, field_index, raw_value)

    def updated_status(self, entry_index, field_index):
        return f"Updated group {entry_index:04d} string {field_index:03d}."

    def saved_status(self, output_path, output_bytes):
        size_change = len(output_bytes) - len(self.state["source_bytes"])
        return (
            f"Created string table at {shorten_path_smart(output_path)} "
            f"({len(output_bytes)} bytes, {size_change:+d} vs original)."
        )

    def info_text(self):
        document = self.state["document"]
        file_path = self.state["path"] or document.file_path or "string_tbl.bin"
        return (
            f"{os.path.basename(file_path)}{self.bad_marker()}\n"
            f"{document.entry_count} groups | {document.string_count} strings | "
            f"{document.encoding.upper()} | {shorten_path_smart(file_path)}"
        )

    def restore_selected_value(self):
        document = self.state["document"]
        original_document = self.state["original_document"]
        location = self.current_location()
        if document is None or original_document is None or location is None:
            return

        document.set_value(*location, original_document.get_value(*location))
        self.state["dirty"] = True
        self.state["status"] = (
            f"Restored group {location[0]:04d} string {location[1]:03d} from the original file."
        )
        self.value_changed(*location)
        self.refresh()

def parameter_type_name(parameter):
    try:
        return parameter.type_name
    except BinFormatError:
        return "unknown"
