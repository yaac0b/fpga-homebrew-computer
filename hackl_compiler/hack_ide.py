#!/usr/bin/env python3
"""
Hack IDE - write Hack assembly, assemble it with your own assembler
(assembler.py / parser.py / code.py / symbol_table.py), and load +
run it on the Tang Nano 20K over UART, all from one "Run" button.

Setup:
    Put this file (hack_ide.py) in the SAME folder as your
    assembler.py, parser.py, code.py, and symbol_table.py - it
    imports your Assembler class directly, so nothing to configure.

    pip3 install pyserial

Run:
    python3 hack_ide.py

On macOS, tkinter ships with the python.org installer. If you
installed Python via Homebrew and get "No module named tkinter":
    brew install python-tk
"""

import json
import os
import queue
import sys
import tempfile
import threading
import time
import tkinter as tk
import hl  # HackL compiler (hl.py beside this file)
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("pyserial is required: pip3 install pyserial")
    sys.exit(1)

# Make sure Python can find assembler.py etc. even if this script is
# launched from a different working directory.
sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from assembler import Assembler
except ImportError as e:
    print(
        "Could not import your Assembler class.\n"
        "Make sure assembler.py, parser.py, code.py, and "
        "symbol_table.py are in the same folder as hack_ide.py.\n"
        f"(Import error: {e})"
    )
    sys.exit(1)


CONFIG_PATH = Path.home() / ".hack_ide_config.json"
BAUD_RATE = 115200

CMD_LOAD = 0x4C  # 'L'
CMD_RUN = 0x52   # 'R'
CMD_STOP = 0x53  # 'S'

MAX_ROM_WORDS = 32768  # program_ram.v of the GPU/SDRAM/ADC build (15-bit PC)

DEFAULT_ASM = """// Type your Hack assembly here, then hit Run.

@16
M=0

(LOOP)
    @16
    D=M
    @24577
    M=D
    @16
    M=M+1
    @LOOP
    0;JMP
"""

DEFAULT_HL = """// HackL: P1 = the 16 external LEDs, delay(ms), adc(channel)
while (1) {
    P1 = adc(0);
    delay(100);
}
"""

DEFAULT_CONFIG = {
    "serial_port": "",
    "language": "HackL",
    "delay_iters": hl.DEFAULT_ITERS,
}


# ==================================================================
# Config persistence
# ==================================================================

def load_config():
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                data = json.load(f)
            cfg = dict(DEFAULT_CONFIG)
            cfg.update(data)
            return cfg
        except (json.JSONDecodeError, OSError):
            pass
    return dict(DEFAULT_CONFIG)


def save_config(cfg):
    try:
        with open(CONFIG_PATH, "w") as f:
            json.dump(cfg, f, indent=2)
    except OSError:
        pass


# ==================================================================
# Hack file parsing / UART protocol
# ==================================================================

def read_hack_file(path):
    words = []
    with open(path) as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            if len(line) != 16 or any(c not in "01" for c in line):
                raise ValueError(
                    f"{path}:{line_num}: expected 16 bits of 0/1, got "
                    f"{line!r} ({len(line)} chars). This usually means "
                    f"an @address in your program is out of range "
                    f"(must be 0-32767)."
                )
            words.append(int(line, 2))

    if len(words) > MAX_ROM_WORDS:
        raise ValueError(
            f"Program has {len(words)} instructions; ROM only holds "
            f"{MAX_ROM_WORDS}."
        )

    return words


def build_load_packet(words):
    packet = bytearray([CMD_LOAD])
    n = len(words)
    packet.append(n & 0xFF)
    packet.append((n >> 8) & 0xFF)
    for w in words:
        packet.append(w & 0xFF)
        packet.append((w >> 8) & 0xFF)
    return packet


# ==================================================================
# GUI
# ==================================================================

class HackIDE:
    def __init__(self, root):
        self.root = root
        self.root.title("Hack IDE (HackL + Assembly)")
        self.root.geometry("900x650")

        self.cfg = load_config()
        self.log_queue = queue.Queue()
        self.current_file = None
        self.worker_thread = None

        self._build_ui()
        self._poll_log_queue()

    # ------------------------------------------------------------
    # UI construction
    # ------------------------------------------------------------

    def _build_ui(self):
        toolbar = ttk.Frame(self.root, padding=6)
        toolbar.pack(side=tk.TOP, fill=tk.X)

        ttk.Button(toolbar, text="Open", command=self.open_file).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Button(toolbar, text="Save", command=self.save_file).pack(
            side=tk.LEFT, padx=2
        )
        ttk.Separator(toolbar, orient=tk.VERTICAL).pack(
            side=tk.LEFT, fill=tk.Y, padx=8
        )

        self.run_button = ttk.Button(
            toolbar, text="Run  \u25b6", command=self.on_run
        )
        self.run_button.pack(side=tk.LEFT, padx=2)

        self.stop_button = ttk.Button(
            toolbar, text="Stop  \u25a0", command=self.on_stop
        )
        self.stop_button.pack(side=tk.LEFT, padx=2)

        ttk.Separator(toolbar, orient=tk.VERTICAL).pack(
            side=tk.LEFT, fill=tk.Y, padx=8
        )

        ttk.Label(toolbar, text="Port:").pack(side=tk.LEFT)
        self.port_var = tk.StringVar(value=self.cfg.get("serial_port", ""))
        self.port_combo = ttk.Combobox(
            toolbar, textvariable=self.port_var, width=22
        )
        self.port_combo.pack(side=tk.LEFT, padx=4)
        ttk.Button(
            toolbar, text="Refresh", command=self.refresh_ports
        ).pack(side=tk.LEFT, padx=2)

        ttk.Separator(toolbar, orient=tk.VERTICAL).pack(
            side=tk.LEFT, fill=tk.Y, padx=8
        )
        ttk.Label(toolbar, text="Language:").pack(side=tk.LEFT)
        self.lang_var = tk.StringVar(value=self.cfg.get("language", "HackL"))
        lang = ttk.Combobox(
            toolbar, textvariable=self.lang_var, width=9, state="readonly",
            values=["HackL", "Assembly"],
        )
        lang.pack(side=tk.LEFT, padx=4)
        lang.bind("<<ComboboxSelected>>", self._on_lang_change)

        # Editor
        editor_frame = ttk.Frame(self.root)
        editor_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=6, pady=(0, 4))

        self.editor = tk.Text(
            editor_frame, wrap=tk.NONE, undo=True, font=("Menlo", 13)
        )
        self.editor.insert("1.0", DEFAULT_HL if self.lang_var.get() == "HackL" else DEFAULT_ASM)
        yscroll = ttk.Scrollbar(
            editor_frame, orient=tk.VERTICAL, command=self.editor.yview
        )
        self.editor.configure(yscrollcommand=yscroll.set)
        self.editor.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        yscroll.pack(side=tk.RIGHT, fill=tk.Y)

        # Log pane
        log_frame = ttk.Frame(self.root)
        log_frame.pack(side=tk.BOTTOM, fill=tk.X, padx=6, pady=(0, 6))

        ttk.Label(log_frame, text="Log").pack(anchor=tk.W)

        self.log_text = tk.Text(
            log_frame, height=10, state=tk.DISABLED,
            font=("Menlo", 11), background="#1e1e1e", foreground="#d0d0d0"
        )
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        log_scroll = ttk.Scrollbar(
            log_frame, orient=tk.VERTICAL, command=self.log_text.yview
        )
        self.log_text.configure(yscrollcommand=log_scroll.set)
        log_scroll.pack(side=tk.RIGHT, fill=tk.Y)

        self.refresh_ports(select_saved=True)

    # ------------------------------------------------------------
    # Logging (thread-safe: workers put() to the queue, UI thread drains it)
    # ------------------------------------------------------------

    def log(self, message):
        self.log_queue.put(message)

    def _poll_log_queue(self):
        while True:
            try:
                message = self.log_queue.get_nowait()
            except queue.Empty:
                break
            self.log_text.configure(state=tk.NORMAL)
            self.log_text.insert(tk.END, message + "\n")
            self.log_text.see(tk.END)
            self.log_text.configure(state=tk.DISABLED)
        self.root.after(100, self._poll_log_queue)

    # ------------------------------------------------------------
    # File menu actions
    # ------------------------------------------------------------

    def _on_lang_change(self, _event=None):
        self.cfg["language"] = self.lang_var.get()
        save_config(self.cfg)

    def open_file(self):
        path = filedialog.askopenfilename(
            filetypes=[("HackL / Hack assembly", "*.hl *.asm"), ("All files", "*.*")]
        )
        if not path:
            return
        with open(path) as f:
            content = f.read()
        self.editor.delete("1.0", tk.END)
        self.editor.insert("1.0", content)
        self.current_file = path
        self.lang_var.set("HackL" if path.endswith(".hl") else "Assembly")
        self._on_lang_change()
        self.root.title(f"Hack IDE - {os.path.basename(path)}")

    def save_file(self):
        if not self.current_file:
            path = filedialog.asksaveasfilename(
                defaultextension=".hl" if self.lang_var.get() == "HackL" else ".asm",
                filetypes=[("HackL", "*.hl"), ("Hack assembly", "*.asm")],
            )
            if not path:
                return
            self.current_file = path
        with open(self.current_file, "w") as f:
            f.write(self.editor.get("1.0", tk.END))
        self.root.title(f"Hack IDE - {os.path.basename(self.current_file)}")
        self.log(f"Saved {self.current_file}")

    # ------------------------------------------------------------
    # Serial ports
    # ------------------------------------------------------------

    def refresh_ports(self, select_saved=False):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_combo["values"] = ports
        if select_saved and self.cfg.get("serial_port") in ports:
            self.port_var.set(self.cfg["serial_port"])
        elif ports and not self.port_var.get():
            self.port_var.set(ports[0])
        self.log(f"Found ports: {ports}" if ports else "No serial ports found.")

    # ------------------------------------------------------------
    # Run / Stop
    # ------------------------------------------------------------

    def on_run(self):
        if self.worker_thread and self.worker_thread.is_alive():
            self.log("Already running - wait for it to finish.")
            return

        port = self.port_var.get().strip()
        if not port:
            messagebox.showerror("No port selected", "Pick a serial port first.")
            return

        self.cfg["serial_port"] = port
        save_config(self.cfg)

        source = self.editor.get("1.0", tk.END)
        self.language = self.lang_var.get()

        self.run_button.configure(state=tk.DISABLED)
        self.worker_thread = threading.Thread(
            target=self._run_worker, args=(source, port), daemon=True
        )
        self.worker_thread.start()

    def _run_worker(self, source, port):
        try:
            with tempfile.TemporaryDirectory() as tmp_dir:
                asm_path = Path(tmp_dir) / "Program.asm"
                if self.language == "HackL":
                    self.log("Compiling HackL...")
                    try:
                        source = hl.compile_source(
                            source, int(self.cfg.get("delay_iters", hl.DEFAULT_ITERS))
                        )
                    except hl.HLError as e:
                        self.log(f"COMPILE ERROR: {e}")
                        return
                asm_path.write_text(source)
                hack_path = asm_path.with_suffix(".hack")

                self.log("Assembling...")
                assembler = Assembler(str(asm_path), str(hack_path))
                assembler.assemble()

                if not hack_path.exists():
                    raise RuntimeError(
                        "Assembler ran but produced no .hack file."
                    )

                words = read_hack_file(hack_path)
                self.log(f"Assembled OK - {len(words)} instructions")

                packet = build_load_packet(words)

                self.log(f"Opening {port}...")
                with serial.Serial(port, BAUD_RATE, timeout=2) as ser:
                    time.sleep(0.2)
                    self.log(f"Sending {len(packet)} bytes...")
                    ser.write(bytes(packet))
                    ser.flush()
                    time.sleep(len(words) * 0.001 + 0.05)
                    self.log("Starting CPU...")
                    ser.write(bytes([CMD_RUN]))
                    ser.flush()

                self.log("Done - running on the FPGA.")

        except Exception as e:
            self.log(f"ERROR: {e}")

        finally:
            self.root.after(0, lambda: self.run_button.configure(state=tk.NORMAL))

    def on_stop(self):
        port = self.port_var.get().strip()
        if not port:
            return
        try:
            with serial.Serial(port, BAUD_RATE, timeout=2) as ser:
                time.sleep(0.2)
                ser.write(bytes([CMD_STOP]))
                ser.flush()
            self.log("Sent stop command.")
        except Exception as e:
            self.log(f"ERROR sending stop: {e}")


def main():
    root = tk.Tk()
    app = HackIDE(root)
    root.mainloop()


if __name__ == "__main__":
    main()
