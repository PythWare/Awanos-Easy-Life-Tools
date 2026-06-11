# Awano's Easy Life Tools/AELT

Awano wanted the sweet life, the easy life ya know? That's my inspiration for this toolkit which is meant to make modding supported formats easier. I HIGHLY suggest reading this readme and the Guide within Awano's Easy Life Tools.

This toolkit is written in Python and Dart (will explain further down what Dart is being used for). Scroll to the bottom to see GUI examples of the toolkit if you desire.

# Requirements

Windows (AELT doesn't support linux/mac) and Python 3, that's it. The GUI is custom but uses tkinter, making it a lightweight app.

The Dart code is compiled so you don't need Dart installed since you'll be using main.pyw.

# How to run

double click main.pyw, should run after that. If it has issues with double clicking then open cmd in the current directory and type `python main.pyw`

If AELT does not launch it's usually caused by Python not being installed correctly or .pyw file associations using the wrong Python. Please verify your Python installation before reporting a bug.

Back up your game files before using AELT.

# Controls

The GUI is intentionally designed to be unique, it doesn't look like a standard GUI app. 

To move the app around you must use right click on the GUI (the vertical buttons or the title of the app).

To exit out of AELT, click the esc button on your keyboard.

Press F1 to toggle on/off always on top mode.

Editor panels can be moved by dragging their title bars.

# T and G spherical buttons

T is where the modding software live while G is the Guide section for AELT, all you need to do is left click the T or G spheres for whatever you're wanting to use. I suggest reading the Guide section (click the G sphere) before using the tools.

# Current features

AELT supports Yakuza 0 20070319 BIN editing (.bin_c, .bin_k, .bin_j), Yakuza 0/Yakuza 3 Shop BIN editing, and high speed PAR batch unpacking with nested PAR support. PAR archives can be unpacked in parallel using up to 4 worker processes.

I may expand AELT with more editors in the future and support other Yakuza games since it's designed with expanding the toolkit in mind.

# PAR Batch Unpack Warning

The PAR batch unpacker can run up to 4 external par.exe worker processes at the same time. Large batches may cause high CPU usage, high RAM usage, and heavy disk activity. Extracted files, decompressed files, and nested PAR archives may require more disk space than the original selected folder. For example, Yakuza 0 (legacy pc version) with a full unpack extracts/decompresses with 290,960 files. Close the game before unpacking, select only the folder you intend to unpack, make sure you have enough free disk space, and avoid running other heavy programs during large batch jobs.

The main purpose of batch unpacking is to make it quicker and easier for the end user, all you have to do is select the folder you want checked for PARs and the batch unpacking will output to the directory AELT is in.

# Performance Notes

Some games unpack very large numbers of files, that is normal. Unpacking can take several minutes or longer depending on:

Game size, number of container entries, compression, nested PAR depth, and SSD vs HDD.

If the progress bar appears stuck, it isn't. It may still be working through heavy nested PAR/decompression logic.

For best results, unpack to a SSD.

# GUI talk

I may change the GUI for the editors in AELT to match my Ever Steel's GUI which is more cell based and table designed. I'll include a sample image of Ever Steel so you have an idea incase people end up preferring Ever Steel's data editing design over AELT's.

<img width="1920" height="1002" alt="ra4" src="https://github.com/user-attachments/assets/e963fdc0-47e8-483b-a350-6b19811fa12b" />

# Dart usage

I wanted to test some ideas I had with having Dart mixed in with my Python code (Dart outperforms Python in some areas after all). As explained earlier you don't need Dart installed to run AELT, the released version includes the compiled dart source so that you only need Python 3 installed. Dart in this toolkit is predominantly used for the unpacking.

# GUI examples of AELT

<img width="1097" height="467" alt="ra1" src="https://github.com/user-attachments/assets/bb65701c-c840-4bd5-af60-67a828cd553d" />

<img width="1090" height="563" alt="ra2" src="https://github.com/user-attachments/assets/a7ab61d1-5661-46aa-a312-ddd45a78ad89" />

<img width="965" height="491" alt="ra3" src="https://github.com/user-attachments/assets/61cd9d1c-a051-42c0-846d-06b2ad8ccab7" />
