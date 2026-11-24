# Update 1.6

Been working on this update for awhile, the biggest change is ditching python infavor of pure Dart. Awano's Easy Life Tools is now fully in Dart and has 0 dependencies, you don't need python or dart installed. Just download the executable from releases and run it

# Awano's Easy Life Tools/AELT

Awano wanted the sweet life, the easy life ya know? That's my inspiration for this software which is meant to make modding supported formats easier. I HIGHLY suggest reading this readme and the Guide within Awano's Easy Life Tools.

The software is written in Dart. Earlier versions of AELT were written in a mix of Python/Dart but versions 1.6 onward are pure Dart, which means there are no dependencies if you use AELT 1.6 onward since the dart code is compiled. Scroll to the bottom to see GUI examples of the software if you desire.

# Requirements

Windows but if you're a linuxian, you can probably get AELT to run with wine. I'm not using flutter for the GUI of AELT.

The Dart code is compiled so you don't need Dart installed, just double click the executable to run.

# How to run

double click the executable, should run after that.

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

AELT supports Yakuza 0 20070319 BIN editing (.bin_c, .bin_k, .bin_j), Yakuza 0/Yakuza 3 Shop BIN editing, String Table modding (tested on Yakuza 5's string_tbl.bin, haven't yet tested on other yakuza games), and high speed PAR batch unpacking with nested PAR support. PAR archives can be unpacked in parallel using up to 4 workers.

I may expand AELT with more editors in the future and support other Yakuza games since it's designed with expanding the software in mind.

# PAR Batch Unpacking

Extracted files, decompressed files, and nested PAR archives may require more disk space than the original selected folder. For example, Yakuza 0 (legacy pc version) with a full unpack extracts/decompresses with 290,729 files. Pirate Yakuzas In Hawaii unpacks with over 436k files. Close the game before unpacking, select only the folder you intend to unpack, make sure you have enough free disk space, and avoid running other heavy programs during large batch jobs.

The main purpose of batch unpacking is to make it quicker and easier for the end user, all you have to do is select the folder you want checked for PARs and the batch unpacking will output to the directory AELT is in. AELT checks the selected directory and subdirectories for PARs/nested PARs.

AELT is best used for PAR/nested PAR unpacking if you need a lot of PARs unpacked, so batch unpacking but it's extremely fast even if you only need a few PARs unpacked

# Performance Notes

Some games unpack very large numbers of files, that is normal. Unpacking can take several minutes or longer or perhaps less depending on:

Game size, number of container entries, compression, nested PAR depth, whether you have the unpacking done in a folder that windows defender/your antivirus has excluded (I highly suggest setting an exclusion for whatever folder you unpack games to because defender/antivirus software throttle the unpacking speed), and SSD vs HDD.

If the progress bar appears stuck, it isn't. It may still be working through heavy nested PAR/decompression logic.

For best results, unpack to a SSD. Ultimately AELT's unpacking speed scales with your hardware, so if you have a good or decent PC the unpacking is ultra fast (I can fully unpack Yakuza 0's 290,729 files that are stored in PARs in 79.8 seconds, that's fast) but if your pc is weak or you chose to unpack to a HDD, expect a little longer.


# some GUI examples of AELT

<img width="1916" height="1025" alt="aelt1" src="https://github.com/user-attachments/assets/af1ed880-73eb-47d8-ace7-b7f801c22aa1" />

<img width="1920" height="1037" alt="aelt2" src="https://github.com/user-attachments/assets/45bbd2b6-b262-4aa0-8d62-d5c12b55229e" />

<img width="1920" height="1023" alt="aelt3" src="https://github.com/user-attachments/assets/e2f1845b-296a-4de6-b283-8c33a3bae3c0" />

<img width="1914" height="1016" alt="aelt4" src="https://github.com/user-attachments/assets/3d7e772b-79ba-4b30-8865-99f38c35b36a" />
