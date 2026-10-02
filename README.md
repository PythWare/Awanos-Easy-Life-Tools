# Awano's Easy Life Tools/AELT

Awano wanted the sweet life, the easy life ya know? That's my inspiration for this software which is meant to make modding supported formats easier. I HIGHLY suggest reading this readme and the Guide within Awano's Easy Life Tools.

The software is written in Python and Dart (will explain further down what Dart is being used for). Scroll to the bottom to see GUI examples of the software if you desire.

# Requirements

Windows (AELT doesn't support linux/mac) and Python 3, that's it. The GUI is custom but uses tkinter, making it a lightweight app.

The Dart code is compiled so you don't need Dart installed since you'll be using main.pyw.

# How to run

double click main.pyw, should run after that. If it has issues with double clicking then open cmd in the current directory and type `python main.pyw`

If AELT does not launch it's usually caused by Python not being installed correctly or .pyw file associations using the wrong Python. Please verify your Python installation before reporting a bug.

Back up your game files before using AELT.

# Credits

Credit goes to SlowpokeVG for his javascript source on the 20070319 BIN format and Violet for her binary templates on the Shop BIN formats.

# Controls

The GUI is intentionally designed to be unique, it doesn't look like a standard app. 

To move the app around you must use right click on the GUI (the vertical buttons or the title of the app).

To exit out of AELT, click the esc button on your keyboard.

Press F1 to toggle on/off always on top mode.

Editor panels can be moved by dragging their title bars.

# T and G spherical buttons

T is where the modding software live while G is the Guide section for AELT, all you need to do is left click the T or G spheres for whatever you're wanting to use. I suggest reading the Guide section (click the G sphere) before using the tools.

# Current features

AELT supports Yakuza 0 20070319 BIN editing (.bin_c, .bin_k, .bin_j), Yakuza 0/Yakuza 3 Shop BIN editing, String Table modding (tested on Yakuza 5's string_tbl.bin, haven't yet tested on other yakuza games), and high speed PAR batch unpacking with nested PAR support. PAR archives can be unpacked in parallel using up to 4 worker processes.

I may expand AELT with more editors in the future and support other Yakuza games since it's designed with expanding the toolkit in mind.

# PAR Batch Unpack Warning

The PAR batch unpacker can run up to 4 external par.exe worker processes at the same time. Large batches may cause high CPU usage, high RAM usage, and heavy disk activity. Extracted files, decompressed files, and nested PAR archives may require more disk space than the original selected folder. For example, Yakuza 0 (legacy pc version) with a full unpack extracts/decompresses with 290,960 files. Pirate Yakuzas In Hawaii unpacks with over 436k files. Close the game before unpacking, select only the folder you intend to unpack, make sure you have enough free disk space, and avoid running other heavy programs during large batch jobs.

The main purpose of batch unpacking is to make it quicker and easier for the end user, all you have to do is select the folder you want checked for PARs and the batch unpacking will output to the directory AELT is in. AELT checks the selected directory and subdirectories for PARs/nested PARs.

AELT is best used for PAR/nested PAR unpacking if you need a lot of PARs unpacked, so batch unpacking. If you only need a small handful of PARs unpacked then existing PAR unpackers may be better.

# Performance Notes

Some games unpack very large numbers of files, that is normal. Unpacking can take several minutes or longer depending on:

Game size, number of container entries, compression, nested PAR depth, and SSD vs HDD.

If the progress bar appears stuck, it isn't. It may still be working through heavy nested PAR/decompression logic.

For best results, unpack to a SSD.

# Dart usage

I wanted to test some ideas I had with having Dart mixed in with my Python code (Dart outperforms Python in some areas after all). As explained earlier you don't need Dart installed to run AELT, the released version includes the compiled dart source so that you only need Python 3 installed. Dart in this toolkit is predominantly used for the unpacking.

# GUI examples of AELT

<img width="1614" height="823" alt="a2" src="https://github.com/user-attachments/assets/855c7c6e-9ff0-4b7f-9bbd-99b048119dc9" />

<img width="1561" height="774" alt="A3" src="https://github.com/user-attachments/assets/e506c0c3-3368-45f2-abcb-5a6e9ba45651" />

<img width="1569" height="780" alt="a4" src="https://github.com/user-attachments/assets/900c36a8-576c-470f-98c0-6ea1c33bb71e" />

<img width="1617" height="755" alt="a5" src="https://github.com/user-attachments/assets/eba25ccf-ba66-472d-b4eb-53b2ec861519" />
