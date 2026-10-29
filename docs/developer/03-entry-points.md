# 3. Entry points and flow

## The engine: `ENGINE.TOS`

Thalion's source never calls its own `Init_program` (its header says to
call `Restart_game` instead), and `Restart_game` and `Exit_program` are
only names that Thalion's code jumps to. Their bodies lay in `AM2_CPU`.
They are ours now, in `engine/src/MAIN.S`, together with the program
entry `start`.

```
start                         engine/src/MAIN.S, the program entry
  command line of the loader  '0' continue, '1' new quest, empty = our start menu
  own stack, supervisor, etv_term -> Notausgang
  library data                AMBFILES\ found?  Objects.amb, button graphics,
                              Text.amb, Keymap, CPU check for 3D
  screen, raster, mouse       Bildpuffer_anlegen, Open_screen, Raster_install,
                              Musik_install, Set_mouse_ptr, Mouse_install
  without a choice            Startmenue (HULL/STARTMENUE.S)
  └ Restart_game              also entered by Thalion's Load_game
      Set_music(0), open file closed, memory cleared
      stacks reset in a fixed order: PA, module, tree, scroll bar
      Thalion's Init_program
      └ Main_loop             Thalion's Update_display    the modules draw
                              Thalion's Handle_input      their .Mev/.Kev lists
                              our Switch_screens          HDOBs and pointer into
                                                          the back screen, swap,
                                                          wait, Thalion's ScrQ_handler
```

**The order of the stacks matters** (findings 162, 172): `Reset_PA_stack`
must come before `Reset_module_stack`.

**Thalion's game is built around a module stack** (`HULL/MODULE_C.S`).
Every screen (map, inventory, combat, dialogue …) is a module with a
descriptor in Thalion's `MODULES.S`: its routines (`ModInit`, `DisInit`,
`DisUpd`, `DisExit`), its input lists, its VBL and screen-switch queues
and its **raster list** (which palette applies from which line; chapter
6). The library asks the stack two things: which palette applies in this
line, and whose queues run in the VBL. `VblQ_handler` and `ScrQ_handler`
are never called by Thalion's source; the library did that, so we do
(finding 190).

## Every frame: the VBL

`Raster_vbl` (`RASTER.S`) hangs in the TOS VBL queue and calls
`Bibliothek_vbl` (`LIBRARY.S`):

```
VBL_counter + 1
Basis_setzen      video base of the shown screen, with screen shaking
Maus_vbl          Button_state and one mouse event, as AM2_CPU does
Zeiger_vbl        the pointer follows the mouse in the shown screen
Thalion's VblQ_handler   timers, Time_2D …
Musik_vbl         sound buffer and the player's tick
```

On the ST, `Raster_vbl` first sets the registers of the first screen area
and arms Timer B for the next border (`St_raster_vbl`, `ST_LIB.S`).

The mouse comes from the IKBD packets through the vector that `Kbdvbase`
names (`Mouse_int`); the keyboard is read in `Read_key`
(`VARIOUS_SUP.S`, chapter 5).

## Leaving

- **`Exit_program`** (`MAIN.S`): Thalion jumps there from any depth. It
  removes music, raster, mouse and screen, restores the 68030 cache
  register, leaves supervisor mode and ends with
  `Pterm(Return_value)`. Return values −5000…−5002 mean "game completed"
  and tell the loader which ending to show (finding 263).
- **`Notausgang`**, the emergency exit (`MAIN.S`), hangs in `etv_term`.
  GEMDOS calls it on every `Pterm`, including the one TOS performs after
  a crash. It runs the same removal steps (each has a flag, so it does
  nothing after a regular exit), with the interrupt mask lowered so
  that `Close_screen` can wait for a VBL. Without it, our VBL, mouse
  vector and Timer B would point into freed memory after a crash.
- **After a crash:** `ENGINE.TOS` shows its load address at start.
  `ATARI/BOMBEN.TOS` then reads what TOS left at `$380` (PC, access
  address, registers, frame) and writes it to `BOMBEN.TXT`. PC minus load
  address is the offset in the symbol map (chapter 9).

## The program chain

`lader/lader.s` becomes `AMBER.TOS`, plain 68000 code. Like Thalion's
Amiga loader `Ambermoon` it starts the programs in turn. It looks for
each in `AMBFILES\` first, then next to itself; a missing program is
skipped quietly, any other load error is reported.

**One loader for both machines** (user, 2026-10-21). At the start it reads
the cookie `_MCH`: high word 3 is a Falcon, which starts `FANTASY.TOS`,
`INTRO.TOS`, `ENGINE.TOS`, `EXTRO.TOS`. Anything else, or no cookie jar
at all (an old ST TOS), is an ST, which starts `FANTSYST.TOS`,
`INTROST.TOS`, `ENGINEST.TOS`, `EXTROST.TOS`. The ST has no extro yet,
so there the chain skips it.

The programs talk through
the command line (length byte 1, one ASCII digit, terminating zero) and
their return value:

| Program | Command line | Returns |
|---|---|---|
| `FANTASY.TOS` | – | – |
| `INTRO.TOS` | `'1'` = a save game exists (from `SAVES`) | menu choice 0 continue, 1 new quest, 3 quit |
| `ENGINE.TOS` | `'0'` continue, `'1'` new quest, empty = start menu of the library | `Return_value`; −5000…−5002 = game completed |
| `EXTRO.TOS` | `'0'`–`'2'` = which ending | – |

Each program also runs alone.

## The other entry points

| Program | Entry | Our part |
|---|---|---|
| `FANTASY.TOS` | `start` in `fantasy/FEE_SUP.S`, included before Thalion's `FAIRY.S` | the hardware below Thalion's source |
| `INTRO.TOS`, `EXTRO.TOS` | `start` in `intro/INTRO_SUP.S`, `extro/EXTRO_SUP.S` | hand-over to Thalion's hunks on the Amiga layer (`amiga/`, chapter 10) |
| `AMBER.TOS` | `lader/lader.s` | all of it |
