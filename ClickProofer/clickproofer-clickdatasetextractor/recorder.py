"""Mouse timing recorder. Python + Tkinter only; no pip packages."""

import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import tempfile
import time


def analyze_events(events, intended_clicks):
    if type(intended_clicks) is not int or intended_clicks < 1:
        raise ValueError("Enter at least one intentional click.")
    presses = []
    holds = []
    gaps = []
    held = None
    last_release = None
    previous_time = -1
    for event in events:
        timestamp = event["t_ms"]
        if (type(timestamp) not in (int, float) or not math.isfinite(timestamp)
                or timestamp < 0 or timestamp < previous_time):
            raise ValueError("Event times must be finite, nonnegative, and ordered.")
        previous_time = timestamp
        if event["kind"] == "down":
            if held is not None:
                raise ValueError("Two presses without a release; collect a new sample.")
            held = timestamp
            presses.append(timestamp)
            if last_release is not None:
                gaps.append(timestamp - last_release)
        elif event["kind"] == "up":
            if held is None:
                raise ValueError("Release without a press; collect a new sample.")
            holds.append(timestamp - held)
            held = None
            last_release = timestamp
        else:
            raise ValueError("Unknown event kind.")
    if held is not None:
        raise ValueError("Release the mouse button before saving.")
    if not presses:
        raise ValueError("Click in the recording area first.")

    observed = len(presses)
    extra = observed - intended_clicks
    ordered_gaps = sorted(gaps)
    recommendation = None
    # The count alone cannot label individual clicks; this assumes extras have the shortest gaps.
    if 0 < extra <= len(gaps):
        candidate = math.floor(ordered_gaps[extra - 1]) + 1
        if candidate <= 250 and (extra == len(gaps) or candidate <= ordered_gaps[extra]):
            recommendation = candidate
    return {
        "observed_clicks": observed,
        "intended_clicks": intended_clicks,
        "extra_clicks": max(extra, 0),
        "missing_clicks": max(-extra, 0),
        "extra_clicks_per_100_intended": round(max(extra, 0) * 100 / intended_clicks, 2),
        "press_to_press_ms": [round(b - a, 3) for a, b in zip(presses, presses[1:])],
        "release_to_press_ms": [round(gap, 3) for gap in gaps],
        "hold_ms": [round(hold, 3) for hold in holds],
        "predicted_clicks_by_threshold_ms": {
            str(threshold): observed - sum(gap < threshold for gap in gaps)
            for threshold in (10, 20, 30, 50, 75, 100, 150, 250)
        },
        "suggested_threshold_ms": recommendation,
        "interpretation": (
            "Suggestion assumes intentional clicks are spaced apart and extra clicks have "
            "the shortest release-to-press gaps. Manual count cannot identify which clicks "
            "were faulty or how many physical clicks were affected. Test before using."
        ),
    }


def save_json(path, dataset):
    """Replace only after a complete write, so errors leave existing samples intact."""
    path = Path(path)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         delete=False, suffix=".tmp") as stream:
            temporary = stream.name
            json.dump(dataset, stream, indent=2, allow_nan=False)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def run_ui():
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    root = tk.Tk()
    root.title("ClickProofer - mouse dataset")
    root.geometry("610x460")
    root.minsize(520, 420)
    events = []
    started_ns = time.perf_counter_ns()
    first_message_time = None
    started_utc = datetime.now(timezone.utc).isoformat()
    dirty = False
    held = False
    button_names = {"Left": 1, "Middle": 2, "Right": 3}
    selected = tk.StringVar(value="Left")
    intended = tk.StringVar(value="1")
    status = tk.StringVar(value="Observed: 0 clicks")
    panel = ttk.Frame(root, padding=16)
    panel.pack(fill="both", expand=True)
    ttk.Label(panel, text="Pause ClickProofer first to measure the raw fault.\n"
              "Click here slowly (about once per second). Keep your own count.").pack(anchor="w")
    controls = ttk.Frame(panel)
    controls.pack(fill="x", pady=12)
    ttk.Label(controls, text="Mouse button:").pack(side="left")
    selector = ttk.Combobox(controls, textvariable=selected, values=list(button_names),
                           state="readonly", width=9)
    selector.pack(side="left", padx=8)
    ttk.Label(controls, text="Real clicks I made:").pack(side="left", padx=(12, 4))
    spin = ttk.Spinbox(controls, from_=1, to=100000, textvariable=intended, width=8)
    spin.pack(side="left")
    canvas = tk.Canvas(panel, background="#e5f0ff", highlightthickness=1,
                       highlightbackground="#3568a8", takefocus=True, height=190)
    canvas.pack(fill="both", expand=True)
    canvas.create_text(240, 85, text="CLICK IN THIS AREA\nOnly this area is recorded",
                       font=("Segoe UI", 16), justify="center", tags="caption")
    canvas.bind("<Configure>", lambda e: canvas.coords("caption", e.width / 2, e.height / 2))

    def capture(event, kind):
        nonlocal dirty, held, first_message_time
        if event.num != button_names[selected.get()] or (kind == "up" and not held):
            return
        if kind == "down" and not (0 <= event.x < canvas.winfo_width()
                                    and 0 <= event.y < canvas.winfo_height()):
            return
        held = kind == "down"
        message_time = event.time & 0xFFFFFFFF
        if first_message_time is None:
            first_message_time = message_time
        events.append({"kind": kind, "button": selected.get().lower(),
                       "t_ms": (message_time - first_message_time) & 0xFFFFFFFF,
                       "received_t_ms": (time.perf_counter_ns() - started_ns) / 1_000_000,
                       "windows_message_time_ms": message_time,
                       "x": event.x, "y": event.y})
        dirty = True
        selector.configure(state="disabled")
        count = sum(item["kind"] == "down" for item in events)
        status.set(f"Observed: {count} clicks | {'Pressed' if held else 'Released'}")

    canvas.bind("<ButtonPress>", lambda event: capture(event, "down"))
    canvas.bind("<ButtonRelease>", lambda event: capture(event, "up"))
    ttk.Label(panel, textvariable=status).pack(anchor="w", pady=8)

    def save():
        nonlocal dirty
        try:
            count = int(intended.get())
            summary = analyze_events(events, count)
        except (ValueError, KeyError) as error:
            messagebox.showerror("Cannot save", str(error), parent=root)
            return
        path = filedialog.asksaveasfilename(
            parent=root, title="Save click dataset", defaultextension=".json",
            filetypes=[("JSON dataset", "*.json")],
            initialfile=datetime.now().strftime("mouse-%Y%m%d-%H%M%S.json"))
        if not path:
            return
        dataset = {"schema_version": 1, "started_utc": started_utc,
                   "clock": "Windows message time offsets in milliseconds; received_t_ms is UI delivery time",
                   "button": selected.get().lower(), "intended_clicks": count,
                   "events": events, "summary": summary}
        try:
            save_json(path, dataset)
        except (OSError, ValueError) as error:
            messagebox.showerror("Save failed", str(error), parent=root)
            return
        dirty = False
        suggestion = summary["suggested_threshold_ms"]
        messagebox.showinfo("Dataset saved", f"Observed: {summary['observed_clicks']}\n"
                            f"Intentional: {count}\nExtra: {summary['extra_clicks']}\n"
                            f"Suggested threshold: {str(suggestion) + ' ms' if suggestion else 'no clear estimate'}\n\n"
                            "The estimate assumes your intentional clicks were spaced apart.\n"
                            "Enter it in ClickProofer and test normal double-clicks.", parent=root)

    def reset():
        nonlocal started_ns, started_utc, dirty, held, first_message_time
        if dirty and not messagebox.askyesno("Discard sample?", "Discard the unsaved sample?", parent=root):
            return
        events.clear()
        started_ns = time.perf_counter_ns()
        first_message_time = None
        started_utc = datetime.now(timezone.utc).isoformat()
        dirty = held = False
        intended.set("1")
        selector.configure(state="readonly")
        status.set("Observed: 0 clicks")

    def close():
        if not dirty or messagebox.askyesno("Discard sample?", "Close without saving this sample?", parent=root):
            root.destroy()

    def edited(*_):
        nonlocal dirty
        if events:
            dirty = True

    intended.trace_add("write", edited)
    actions = ttk.Frame(panel)
    actions.pack(fill="x")
    ttk.Button(actions, text="New sample", command=reset).pack(side="left")
    ttk.Button(actions, text="Save JSON + analysis", command=save).pack(side="right")
    root.protocol("WM_DELETE_WINDOW", close)
    root.mainloop()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--analyze", type=Path, help="Print analysis of a saved JSON dataset")
    args = parser.parse_args()
    if args.analyze:
        try:
            data = json.loads(args.analyze.read_text(encoding="utf-8"))
            print(json.dumps(analyze_events(data["events"], data["intended_clicks"]), indent=2))
        except (OSError, ValueError, KeyError, TypeError) as error:
            parser.exit(1, f"Cannot analyze dataset: {error}\n")
    else:
        run_ui()
