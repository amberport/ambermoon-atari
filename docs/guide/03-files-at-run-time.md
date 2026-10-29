# 3. Files unpacked while playing

## The problem

Ambermoon's game files are not plain data. Most of them are
**containers**: one file with many numbered entries, all maps of a world
in one, all portraits in another. The entries are **encrypted** with Jurie
Horneman's XOR stream ("JH") and many of them are **packed** with
Thalion's LOB compression. A few files stand alone, with a JH envelope of
their own.

Thalion's game code sees none of that. It names a file by a number and an
entry by a number, and expects plain data back:

```
moveq.l #0,d0
move.b  Event_b4(a5),d0        which chest
addq.w  #1,d0                  entries count from one
moveq.l #Chest_data_file,d1    which file
jsr     Load_subfile
move.b  d0,Chest_data_handle   a memory handle comes back
```

Everything between the two numbers and the plain data was in the library:
the file names (not one appears in the whole released source, only the
numbered list in `GAME_OFF.S`), the container format, the key, the
unpacker, the error messages. On the Amiga that is `AM2_CPU`. On the
Atari there is GEMDOS on top, which wants names of eight letters, a dot
and three (8.3), and which reports its errors in its own numbers.

## The idea

There are two ways to bring the game files to the Atari:

- **Convert them once**, with a tool on the PC, into files the Atari
  library can read directly: no containers, no encryption, no packing.
- **Read them as they ship**, and undo container, encryption and packing
  every time an entry is loaded.

The project takes the second way; it is its second goal, of equal rank
with taking over Thalion's code. The player copies the game files they
own, the build only renames them to 8.3, and the Atari reads the same
bytes the Amiga reads. There is no converter whose mistakes would end up
in the data, and no converted copy of Thalion's data to keep anywhere.
The price is time at every load; how that was bought back is below.

One call of `Load_subfile` runs through this chain:

```
Load_subfile             d1 = Thalion's file number, d0 = entry
  Teildatei_waehlen      maps lie in 1Map_data, 2Map_data, 3Map_data: which one?
  Datei_name             number → 8.3 name, "AMBFILES\" in front
  Eintrag_lesen          open, read the head and the lengths, seek, read the entry, close
  by container id:
    AMNC                 the whole entry is JH-encrypted
    AMNP                 a pack head in clear, the rest JH-encrypted
    AMPC                 a pack head, not encrypted
    AMBR                 raw
  Packkopf_aufloesen     packed: unpack into a new block; not packed: drop the head
→ d0 = handle of the plain data
```

A container is simple: four letters of id, the number of entries, one
long word with the length of each entry, then the entries one after the
other. Where an entry lies is the sum of the lengths before it. The JH key
of an entry is its number.

### Only the entry, not the whole file

A map container is up to 609 KB. Until 2026-10-21 the library read the
whole file and kept it in a cache of one; every change of map, which
reads several containers, then paused noticeably, and the cache held a
second copy in memory. Now `Eintrag_lesen` does what `AM2_CPU` does: it
reads the six-byte head and the lengths up to the entry, seeks to the
entry with `Fseek`, and reads only that. If `Fseek` lands anywhere else,
it falls back to reading the whole file. That has not happened since TOS
was called correctly (finding 270), but the check costs one comparison.

### Which of three files

Nine kinds of file are split over several containers: the 2D maps, their
texts and their tile graphics in parts 1–3, the 3D files in parts 2 and 3.
Thalion's code knows one file number for each kind; the library picks the
part. The obvious guess is "by entry", and for maps it works, because the
entry is the map number. But `AM2_CPU` asks **`Map_nr`**, the map the
party is on: up to 256 part 1, 257–299 part 2, 300–399 part 3, from 400
part 2 again (finding 197). For the 3D walls and objects the two readings
differ: `2Wall3D` and `3Wall3D` carry different graphics under the same
number. The entry number stays the same in every part, and so does the
key.

### Who unpacks

Thalion calls `Decompress` exactly once in the whole source, in
`Show_layout`, for the screen layouts. Everyone else, `Init_map` for
example, reads right after `Load_subfile` as if the data were plain. For
a while the library therefore unpacked nothing in `Load_subfile`: the one
caller that ran at the time did it itself. That was a rule drawn from one
call site. The layouts are an `AMNC` container, where the LOB block lies
*under* the encryption, a second layer the caller removes. In `AMNP` and
`AMPC` containers every entry starts with a pack head, and that layer the
original `Load_subfile` removed itself (finding 183):

```
1,"LOB",size,packed length,body      packed
0,0,0,0,data                         not packed
```

`Decompress` itself gets only `a0`, the buffer with the packed block at
its start, because the packed length is in the block's head. It moves the
packed body to the end of the buffer and unpacks towards the front; the
buffer is the unpacked size plus Thalion's `Default_safety_factor`, so the
writing never overtakes the reading.

### Thalion's own loops

The two inner loops are Thalion's. The decrypting loop is `Crypt_block`
in `HULL/VARIOUS.S`, in the released source: every word is XORed with the
key, then the key becomes key × 17 + 87. The unpacking loop is the core of
Thalion's `Decompress` in `AM2_CPU`; the build takes it from there as
`Lob_core` (chapter 0, the third way). Our routines around them only
handle lengths and registers.

They came in late, on 2026-10-21, because a map change on the STE was too
slow (finding 274). The first versions were our own loops, written from
the format descriptions. Thalion's are faster, unpacking about 2.2 times,
decrypting 1.7 times on the STE. And reading Thalion's loop showed a
mistake in ours: `Crypt_block` treats an odd last byte as half a word and
XORs it with the high byte of the next key. Our loop had left it alone.
210 of the 1755 encrypted entries of the game have an odd length, all of
them maps and map texts; with our reading every one of them ended in a
wrong byte.

### Memory: handles, not pointers

What comes back is not an address but a **handle**, a number from 1 to
199. Thalion asks for the address with `Claim_pointer` and lets go with
`Free_pointer`. On the Amiga the library could move a block that nobody
held, to close gaps. Our memory never moves anything, but the handles
stay: more than a hundred call sites use them, and the claim counters
behave as in the original, because Thalion's `Out_of_memory` lives on
them. Without memory, Thalion's allocation does not return at all; it
goes to `Out_of_memory`, which saves the party and restarts, as on the
Amiga.

### Writing back

`Save_subfile` gets an entry number, a file number and the data, but no
length. It can work only because it overwrites an entry of the same
size: the files the game writes into (`Chest_data.amb`,
`Party_char.amb`, `Automap.amb`, `Merchant_data.amb`) are `AMBR`
containers with raw entries of fixed size. Since 2026-10-21 it writes
just that entry, at its place in the file.

Those working files are the running game. A **save game** is a folder
`SAVE.nn` with copies of them; `SAVE.00` is the template for a new game.
In the folders the files are JH-encrypted, with a four-byte envelope that
carries its own key ("JH", then the key XOR "JH"); the key changes with
every save, taken from the frame counter. Loading a save game decrypts them into the working files
(`Get_saved_game`); saving encrypts them into the folder
(`Put_saved_game`). Both are library routines; Thalion's code only calls
them.

### When something goes wrong

The original distinguishes two cases, and so does the library now
(finding 268):

- **A disk error** goes to Thalion's own requester, `Disk_error_handler`
  in `HULL/CONTROLS.S`: "error … file … try again?". "Yes" repeats the
  load, "no" ends the program. GEMDOS reports its errors in its own
  numbers; `Fehler_umsetzen` translates them by meaning into the AmigaDOS
  numbers Thalion's table knows, "file not found" to "object not found".
- **An entry that does not exist**, one behind the last of a container,
  is not a disk error but a broken game. The library shows Thalion's
  diagnostic screen "FILE COULDN'T BE LOADED", the kind of file and the
  entry, waits for a click and ends.

### Where goal 2 gives way

Two things are computed at build time, both by the user's decision and
listed with the way back in `docs/17-deviations.md`: the ST palettes
(D1, `STPAL.DAT`), and where in `Text.amb` each of the library's
texts lies (D5). The ST palettes cost about a second per new palette on
8 MHz, at every map change, combat and event picture, and could not be
corrected by hand; a precomputed file can do both. The game files
themselves are still read as they ship, `Palettes.amb` included: the
precomputed file is only looked up by the colours Thalion's code loaded.

## In the code

All of it is in `engine/src/HULL/FILES_SUP.S`, except where noted.

| Routine | What it does |
|---|---|
| `Load_subfile`, `Load_unique_subfile` | Thalion's names: one entry of a container, plain; the two are the same with us, because our memory never shares a block |
| `Teildatei_waehlen` | which part of a split file, by `Map_nr` |
| `Datei_name`, `Ordner_suchen` | file number → 8.3 name; `AMBFILES\` in front when the folder is there (finding 262) |
| `Eintrag_lesen`, `Eintrag_suchen` | read the head and lengths, seek, read the entry; `Eintrag_aus_datei` is the fallback |
| `JH_decrypt` | around Thalion's `Crypt_block` (`HULL/VARIOUS.S`), with the odd last byte |
| `LOB_decompress` | around `Lob_core`, Thalion's unpacking loop from `AM2_CPU` |
| `Packkopf_aufloesen` | the pack head of `AMNP`/`AMPC` entries |
| `Decompress` | Thalion's name: a LOB block in place, for `Show_layout` |
| `Load_file` | Thalion's name: a whole single file, JH envelope and LOB removed |
| `Save_subfile` | Thalion's name: one entry back into its container |
| `Dateifehler`, `Fehler_umsetzen` | GEMDOS errors to Thalion's `Disk_error_handler` |
| `Ladefehler_schirm` | `HULL/DIAGNOSE_SUP.S`: the screen for a missing entry |
| `Allocate_memory`, `Claim_pointer`, `Free_pointer` … | `HULL/MEMORY.S`: the handles |
| `Get_saved_game`, `Put_saved_game` | `HULL/SPIELSTAND.S`: save games to working files and back |

The 8.3 names have two sides that change together: the name table
`dn_tabelle` at the end of `FILES_SUP.S`, and the renaming in
`deliver_data` in `tools/build_common.sh`.

On the host, `tools/ambtool.py` reads the same formats and is the
reference the Atari code was checked against over the whole game data.
The diagnostic switch `ENTPACKPRUEF` builds a self-test that loads one
layout exactly as `Show_layout` does and writes it to `LAYOUT.BIN`, to
compare byte for byte with `ambtool.py`.

Findings: 183 (the pack head, three containers for one file number), 197
(the part by `Map_nr`), 262 (the folder `AMBFILES`), 268 (disk errors and
missing entries), 270 (TOS destroys registers), 274 (Thalion's loops, the
odd byte). The formats were first described by Pyrdacor
(`docs/01-Datenfluss-und-Formate.md`, German). Developer reference:
[chapter 8 of the developer
documentation](../developer/08-files-music-amiga.md).
