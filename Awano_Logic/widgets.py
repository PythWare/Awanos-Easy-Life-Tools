import tkinter as tk
import tkinter.font as tkfont

ACCENT = "#f4b400"
ACCENT_ACTIVE = "#ffd663"
PANEL_BG = "#0f141b"
PANEL_FRAME = "#202833"
PANEL_OUTLINE = "#3a4656"
HEADER_BG = "#1c2734"
FIELD_BG = "#1a212a"
TROUGH = "#121821"
SCROLL_ACTIVE = "#6e83a1"
HEADING_FG = "#dfe7f0"
MUTED_FG = "#b8c2ce"
GOLD_FG = "#e1b85e"
TOGGLE_OFF = "#2d3846"
LIST_FONT = ("Consolas", 9)
EDITOR_FONT = ("Consolas", 10)
SCREEN_MARGIN = 48
TASKBAR_ALLOWANCE = 48

def make_button(parent, text, command, bg, active_bg, fg="white", width=3):
    return tk.Button(
        parent,
        text=text,
        command=command,
        bg=bg,
        fg=fg,
        relief="flat",
        width=width,
        font=("Segoe UI", 8, "bold"),
        activebackground=active_bg,
    )

def make_scrollbar(parent, command):
    return tk.Scrollbar(
        parent,
        command=command,
        troughcolor=TROUGH,
        activebackground=SCROLL_ACTIVE,
    )

class ToggleButton:
    def __init__(self, parent, text, on_change, width=5):
        self.value = False
        self.on_change = on_change
        self.button = make_button(parent, text, self.toggle, TOGGLE_OFF, SCROLL_ACTIVE, width=width)

    def toggle(self):
        self.value = not self.value
        self.button.configure(
            bg=ACCENT if self.value else TOGGLE_OFF,
            fg="black" if self.value else "white",
            activebackground=ACCENT_ACTIVE if self.value else SCROLL_ACTIVE,
        )
        self.on_change()

class VirtualList:
    def __init__(self, parent, on_select=None):
        self.on_select = on_select
        self.count = 0
        self.top = 0
        self.rows = 1
        self.selected = -1
        self.label_for = None
        self.wheel_remainder = 0

        self.frame = tk.Frame(parent, bg=PANEL_BG)
        self.listbox = tk.Listbox(
            self.frame,
            exportselection=False,
            height=1,
            width=1,
            bg=FIELD_BG,
            fg="white",
            relief="flat",
            borderwidth=0,
            highlightthickness=0,
            selectbackground=ACCENT,
            selectforeground="black",
            activestyle="none",
            font=LIST_FONT,
        )
        self.scrollbar = make_scrollbar(self.frame, self.on_scrollbar)
        self.listbox.pack(side="left", fill="both", expand=True)
        self.scrollbar.pack(side="left", fill="y")

        list_font = tkfont.Font(root=self.listbox, font=self.listbox.cget("font"))
        self.line_height = (
            list_font.metrics("linespace") + 1 + 2 * int(self.listbox.cget("selectborderwidth"))
        )

        self.listbox.bind("<Configure>", self.on_resize)
        self.listbox.bind("<Button-1>", self.on_click)
        self.listbox.bind("<B1-Motion>", lambda event: "break")
        self.listbox.bind("<ButtonRelease-1>", lambda event: "break")
        self.listbox.bind("<Double-Button-1>", lambda event: "break")
        self.listbox.bind("<Shift-Button-1>", lambda event: "break")
        self.listbox.bind("<Control-Button-1>", lambda event: "break")
        self.listbox.bind("<MouseWheel>", self.on_wheel)
        self.listbox.bind("<Up>", lambda event: self.move_selection(-1))
        self.listbox.bind("<Down>", lambda event: self.move_selection(1))
        self.listbox.bind("<Prior>", lambda event: self.move_selection(-self.rows))
        self.listbox.bind("<Next>", lambda event: self.move_selection(self.rows))
        self.listbox.bind("<Home>", lambda event: self.move_selection(-self.count))
        self.listbox.bind("<End>", lambda event: self.move_selection(self.count))
        self.scrollbar.bind("<MouseWheel>", self.on_wheel)

    def set_items(self, count, label_for, selected=-1):
        self.count = max(0, count)
        self.label_for = label_for
        self.selected = min(selected, self.count - 1)
        if self.selected >= 0:
            self.see(self.selected)
        self.clamp_top()
        self.render()

    def select(self, index, see=True):
        if self.count <= 0:
            return
        self.selected = max(0, min(index, self.count - 1))
        if see:
            self.see(self.selected)
        self.render()

    def choose(self, index):
        self.select(index)
        if self.on_select is not None and self.selected >= 0:
            self.on_select(self.selected)

    def see(self, index):
        if index < self.top:
            self.top = index
        elif index >= self.top + self.rows:
            self.top = index - self.rows + 1
        self.clamp_top()

    def clamp_top(self):
        self.top = max(0, min(self.top, self.count - self.rows))

    def scroll_to(self, top):
        self.top = int(top)
        self.clamp_top()
        self.render()

    def render(self):
        end = min(self.count, self.top + self.rows + 1)
        label_for = self.label_for
        labels = [label_for(index) for index in range(self.top, end)] if label_for else []

        self.listbox.delete(0, "end")
        if labels:
            self.listbox.insert(0, *labels)
        if self.top <= self.selected < end:
            self.listbox.selection_set(self.selected - self.top)

        if self.count <= self.rows:
            self.scrollbar.set(0.0, 1.0)
        else:
            self.scrollbar.set(self.top / self.count, (self.top + self.rows) / self.count)

    def on_resize(self, event):
        rows = max(1, event.height // self.line_height)
        if rows == self.rows:
            return
        self.rows = rows
        if self.selected >= 0:
            self.see(self.selected)
        self.clamp_top()
        self.render()

    def on_click(self, event):
        self.listbox.focus_set()
        index = self.top + event.y // self.line_height
        if 0 <= index < self.count:
            self.choose(index)
        return "break"

    def on_wheel(self, event):
        self.wheel_remainder += -event.delta * 3
        steps = int(self.wheel_remainder / 120)
        if steps:
            self.wheel_remainder -= steps * 120
            self.scroll_to(self.top + steps)
        return "break"

    def on_scrollbar(self, action, amount, unit=None):
        if action == "moveto":
            self.scroll_to(float(amount) * self.count)
            return

        step = int(amount)
        self.scroll_to(self.top + (step * self.rows if unit == "pages" else step))

    def move_selection(self, delta):
        if self.count <= 0:
            return "break"

        if self.selected >= 0:
            self.choose(self.selected + delta)
        else:
            self.choose(0 if delta > 0 else self.count - 1)
        return "break"

class FloatingPanel:
    def __init__(self, root, title, width, height, offset_x, offset_y, on_close, min_width=360, min_height=260):
        self.root = root
        self.offset_x = offset_x
        self.offset_y = offset_y
        self.min_width = min_width
        self.min_height = min_height
        self.width = max(min_width, min(width, root.winfo_screenwidth() - SCREEN_MARGIN))
        self.height = max(
            min_height,
            min(height, root.winfo_screenheight() - SCREEN_MARGIN - TASKBAR_ALLOWANCE),
        )
        self.visible = False
        self.drag_origin = None
        self.resize_origin = None

        self.window = tk.Toplevel(root, bg=PANEL_FRAME)
        self.window.withdraw()
        self.window.overrideredirect(True)
        self.window.attributes("-topmost", True)

        outline = tk.Frame(
            self.window,
            bg=PANEL_BG,
            highlightthickness=1,
            highlightbackground=PANEL_OUTLINE,
            highlightcolor=PANEL_OUTLINE,
        )
        outline.pack(fill="both", expand=True, padx=3, pady=3)

        self.header = tk.Frame(outline, bg=HEADER_BG, height=28)
        self.header.pack(fill="x", padx=2, pady=(2, 0))

        self.title_var = tk.StringVar(value=title)
        title_label = tk.Label(
            self.header,
            textvariable=self.title_var,
            bg=HEADER_BG,
            fg="white",
            font=("Segoe UI", 10, "bold"),
        )
        title_label.pack(side="left", padx=8, pady=4)

        close_button = make_button(self.header, "X", on_close, "#4a4f57", "#6b7380")
        close_button.pack(side="right", padx=6, pady=4)

        for widget in (self.header, title_label):
            widget.bind("<Button-1>", self.start_drag)
            widget.bind("<B1-Motion>", self.do_drag)
            widget.bind("<ButtonRelease-1>", self.stop_drag)

        footer = tk.Frame(outline, bg=PANEL_BG, height=14)
        footer.pack(side="bottom", fill="x")

        grip = tk.Label(
            footer,
            text="◢",
            bg=PANEL_BG,
            fg=SCROLL_ACTIVE,
            cursor="size_nw_se",
            font=("Segoe UI", 9),
        )
        grip.pack(side="right", padx=(0, 1))
        grip.bind("<Button-1>", self.start_resize)
        grip.bind("<B1-Motion>", self.do_resize)
        grip.bind("<ButtonRelease-1>", self.stop_resize)

        self.body = tk.Frame(outline, bg=PANEL_BG)
        self.body.pack(fill="both", expand=True, padx=2)

    def apply_geometry(self, origin=None):
        origin_x, origin_y = origin or (self.root.winfo_rootx(), self.root.winfo_rooty())
        self.window.geometry(
            f"{self.width}x{self.height}+{origin_x + self.offset_x}+{origin_y + self.offset_y}"
        )

    def keep_on_screen(self):
        origin_x = self.root.winfo_rootx()
        origin_y = self.root.winfo_rooty()
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight() - TASKBAR_ALLOWANCE
        x = origin_x + self.offset_x
        y = origin_y + self.offset_y

        if not (0 <= x < screen_width and 0 <= y < screen_height):
            return

        x = max(0, min(x, screen_width - self.width))
        y = max(0, min(y, screen_height - self.height))
        self.offset_x = x - origin_x
        self.offset_y = y - origin_y

    def show(self):
        if not self.visible:
            self.keep_on_screen()
            self.apply_geometry()
            self.window.deiconify()
            self.visible = True
        self.window.lift()

    def hide(self):
        if self.visible:
            self.window.withdraw()
            self.visible = False

    def set_topmost(self, topmost):
        self.window.attributes("-topmost", topmost)

    def start_drag(self, event):
        self.drag_origin = (event.x_root, event.y_root)

    def do_drag(self, event):
        if self.drag_origin is None:
            return

        self.offset_x += event.x_root - self.drag_origin[0]
        self.offset_y += event.y_root - self.drag_origin[1]
        self.drag_origin = (event.x_root, event.y_root)
        self.apply_geometry()

    def stop_drag(self, event=None):
        self.drag_origin = None

    def start_resize(self, event):
        self.resize_origin = (event.x_root, event.y_root, self.width, self.height)

    def do_resize(self, event):
        if self.resize_origin is None:
            return

        origin_x, origin_y, start_width, start_height = self.resize_origin
        self.width = max(self.min_width, start_width + event.x_root - origin_x)
        self.height = max(self.min_height, start_height + event.y_root - origin_y)
        self.apply_geometry()

    def stop_resize(self, event=None):
        self.resize_origin = None
