#!/usr/bin/env python3
"""thalion_prepare.py -- Thalion's game files (1.0x) laid out as 1.2x.

The build and the engine expect the files of 1.20: Text.amb, Objects.amb,
Button_graphics, Dict.amb, Monster_char.amb, Saves and Save.00 to Save.10.
Thalion's disks (1.01 German, 1.07 English) do not have them: texts, items
and button graphics lie inside AM2_CPU, the dictionary and the monster
file have other names, and the save games come from Initial/ through the
install program.  This tool makes them, at build time, into a folder of its
own (build/thalion/Amberfiles); Thalion's files stay as they are.  For a
1.2x folder it does nothing.

Made files (raw, Load_file reads raw files as they are):

    Text.amb          from AM2_CPU, in the layout of 1.20 (text_labels.py)
    Objects.amb       the item table from AM2_CPU (count word, 60 byte each)
    Button_graphics   from AM2_CPU (1.2x: hunk 5)
    Dict.amb          = Dictionary.<language>
    Monster_char.amb  = Monster_char_data.amb
    Saves             392 zero bytes: no last save game (Init_program then
                      puts up the character editor)
    Save.00-Save.10   each a copy of Initial/

DEVIATION (goal 2), docs/17-deviations.md D7: Text.amb, Objects.amb and
Button_graphics are made from AM2_CPU before run time and delivered as game
files; 1.2x has them as files of its own.  The way back:
read them from AM2_CPU at run time (the places are those of the virtual
1.21 image, tools/am2cpu_old.py).

Usage: thalion_prepare.py [--amberfiles DIR] [--out build/thalion]
Prints the folder to use as AMBER_DATEN, or nothing for 1.2x.
"""
import argparse
import os
import re
import shutil
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import am2cpu_old                      # noqa: E402
import paths                           # noqa: E402

TEXT_PLACES = am2cpu_old.TEXT_PLACES
ITEM_SIZE = 60
SAVES_SIZE = 392
BUTTONS_SIZE = 12168          # 1.2x hunk 5, Button_graphics


class Error(SystemExit):
    def __init__(self, text):
        SystemExit.__init__(self, "thalion_prepare.py: " + text)


def word(d, o):
    return struct.unpack(">H", d[o:o + 2])[0]


def longword(d, o):
    return struct.unpack(">I", d[o:o + 4])[0]


def text_at(d, o):
    e = d.index(b"\0", o)
    return d[o:e + 1]


class OldCpu:
    """The old AM2_CPU with its place table."""

    def __init__(self, path):
        self.hunks, self.version = am2cpu_old.read_old(path)
        import am2cpu_old_maps as K
        if self.version not in K.MAPS:
            raise Error("AM2_CPU %s: no place table" % self.version)
        self.place_map = K.MAPS[self.version]
        self.new_to_old = {(nh, nv): (oh, ov) for oh, ov, nh, nv in self.place_map["labels"]}

    def label(self, nh, nv):
        """1.21 label -> old (hunk, offset); stops if the code does not name it."""
        if (nh, nv) not in self.new_to_old:
            raise Error("no old place for 1.21 %d:$%X" % (nh, nv))
        return self.new_to_old[(nh, nv)]

    def pointer(self, oh, ov):
        """The old pointer at (oh, ov) -> its target (hunk, offset)."""
        h = self.hunks[oh]
        if ov not in h["reloc"]:
            raise Error("no pointer at old %d:$%X" % (oh, ov))
        return h["reloc"][ov], longword(h["data"], ov)


def part1(old):
    """-> the 46 texts of part 1, each with its zero byte."""
    import am2cpu_extract as A
    lists = sorted(m[1] for m in A.MESSAGE_LISTS if m)
    texts = []
    for nr, place in enumerate(TEXT_PLACES):
        if isinstance(place, tuple):           # World_map_names in hunk 6
            oh, ov = old.label(6, 0x104)
            target = old.pointer(oh, ov + 4 * nr)
        elif (4, place) in old.new_to_old and \
                old.new_to_old[(4, place)][1] not in old.hunks[old.new_to_old[(4, place)][0]]["reloc"]:
            target = old.new_to_old[(4, place)]     # the code names the text itself
        else:
            start = max(a for a in lists if a <= place)
            oh, ov = old.label(4, start)
            target = old.pointer(oh, ov + place - start)
        texts.append(text_at(old.hunks[target[0]]["data"], target[1]))
    return texts


# 1.2x reads the names of Text.amb through pointers in hunk 4 from $80C8
# (its start code fills them); Thalion's code points at the texts directly.
# So each pointer place names, through the place table's labels, the old
# address: $80C8 + 4k the k-th name list, then the single texts and their
# number fields.  $8100 (Magic_txt) is set apart by 1.2x's start code.
LIST_POINTERS = 0x80C8
SINGLE_POINTERS = 0x8104


def find_prompts(d, end):
    """The block of Find_large_text: word n, n length words, n texts; it
    ends where the first name list begins (zero fill allowed).  The texts
    end with a zero byte as a rule, not always (1.01 German, prompt 137,
    has none; Find_large_text goes by the lengths).  -> start; exactly one."""
    hits = []
    for p in range(0, end - 4, 2):
        n = word(d, p)
        if not 100 <= n <= 2000:
            continue
        lengths = struct.unpack(">%dH" % n, d[p + 2:p + 2 + 2 * n])
        e = p + 2 + 2 * n + sum(lengths)
        if min(lengths) and e <= end and not any(d[e:end]):
            hits.append((p, e))
    if len(hits) != 1:
        raise Error("prompt block: %d candidates" % len(hits))
    return hits[0]


def part3(old, d, count):
    """The name lists, each from its start to the next one, zero-padded to
    a longword, with the count word of 1.2x.  -> (lists, start of part 4)."""
    starts = [old.label(4, LIST_POINTERS + 4 * k)[1] for k in range(count)]
    end = old.label(4, SINGLE_POINTERS)[1]
    lists = []
    for k, a in enumerate(starts):
        b = starts[k + 1] if k + 1 < count else end
        if b <= a:
            raise Error("name list %d: old $%X .. $%X" % (k + 1, a, b))
        body = bytearray(d[a:b])
        while body and len(body) > 1 and body[-1] == 0 and body[-2] == 0:
            body.pop()                     # fill between the lists
        if body[-1] != 0:
            raise Error("name list %d does not end with a zero byte" % (k + 1))
        while len(body) % 4:
            body.append(0)
        lists.append(struct.pack(">H", len(body) // 4) + bytes(body))
    return lists, starts[0], end


def part4(old, d, o, singles):
    """The single texts and their number fields.

    1.2x's pointers from $8104 follow its table of part 4: for each text
    first one place per number field, then one for the text.  Through the
    labels each place names an old address.  Two have none (no code points
    there in 1.0x): the text is then the next old text in this region that
    nothing else claims (1.01/1.07: "BEIDE"/"BOTH", which Thalion keeps
    behind "GESCHLECHT"), and a number field the start of its digit run.
    -> [(text, [number field offsets])]."""
    claimed = {ov for oh, ov, nh, nv in old.place_map["labels"] if oh == 4}
    # the texts of the region, in file order
    region_texts = []
    p = o
    while True:
        while d[p] == 0:
            p += 1
        t = text_at(d, p)
        if not (0x20 <= t[0] < 0xFF) or len(t) > 80:
            break
        region_texts.append(p)
        p += len(t)
    starts = set(region_texts)

    def text_start(place):
        """old address inside a text -> start of that text"""
        return max(a for a in region_texts if a <= place)

    free = [a for a in region_texts if a not in claimed]
    place = SINGLE_POINTERS
    result = []
    for name, number_names in singles:
        fields = []
        for _ in number_names:
            target = old.new_to_old.get((4, place))
            fields.append(target and target[1])
            place += 4
        target = old.new_to_old.get((4, place))      # the text without a name has its place too
        place += 4
        if target and target[1] in starts:
            start = target[1]
        elif not name and any(fields):
            start = text_start(max(f for f in fields if f))
        else:
            if not free:
                raise Error("single text %s: no old place" % (name or number_names))
            start = free.pop(0)
            print("  thalion_prepare.py: NOTE %s: no code points at it, taken "
                  "the unclaimed text at old $%X" % (name or number_names, start),
                  file=sys.stderr)
        if start in free:
            free.remove(start)
        t = text_at(d, start)
        if all(fields):
            result.append((t, [f - start for f in fields]))
        else:
            rule = number_fields_of(t, number_names, name is None)
            result.append((t, [f - start if f else r for f, r in zip(fields, rule)]))
    return result


def number_fields_of(text, names, reverse_order):
    """Number fields of a single text: the starts of its digit runs (proved
    against Text.amb 1.21 in five languages)."""
    runs = [m.start() for m in re.finditer(rb"[0-9]+", text[:-1])]
    if len(runs) != len(names):
        raise Error("text %r: %d digit runs, %d number fields"
                     % (text, len(runs), len(names)))
    return list(reversed(runs)) if reverse_order else runs


def text_amb(old):
    import text_labels as T
    d = old.hunks[old.label(6, 0x104)[0]]["data"]   # the data hunk
    t1 = part1(old)
    lists, l_start, e_start = part3(old, d, len(T.LISTS))
    p_start, p_end = find_prompts(d, l_start)
    singles = part4(old, d, e_start, T.SINGLES)
    # the version lines lie in the code hunk of 1.0x
    for h in old.hunks:
        m = am2cpu_old.VERSION.search(h["data"])
        if m:
            break
    else:
        raise Error("version lines not found")
    ver1 = b"Ambermoon v" + m.group(1) + b"\0"
    ver2 = m.group(2) + b" / " + m.group(3) + b"\0"

    result = bytearray()
    # part 1: word longwords, word count, offset words, texts (to a longword)
    body = bytearray()
    offsets = []
    for t in t1:
        offsets.append(len(body))
        body += t
    while len(body) % 4:
        body.append(0)
    result += struct.pack(">HH", len(body) // 4, len(t1))
    result += struct.pack(">%dH" % len(t1), *offsets)
    result += body
    # part 2: the prompt block as it is
    result += d[p_start:p_end]
    while (len(result) + 2) % 4:
        result.append(0)
    # part 3
    for l in lists:
        result += l
    # part 4: table (number fields $FFxx before each length), then texts
    table = []
    for t, fields in singles:
        for f in fields:
            table.append(0xFF00 | f)
        table.append(len(t))
    result += struct.pack(">H", len(table)) + struct.pack(">%dH" % len(table), *table)
    for t, _ in singles:
        result += t
    # part 5: two bytes, the version lines
    result += b"\0\0" + ver1 + ver2
    while len(result) % 4:
        result.append(0)
    labels, _ = T.parse_text_amb(bytes(result))        # the same check as the build's
    return bytes(result)


def item_table(old):
    """The item table: word n, then n records of 60 bytes; the name (last
    20 bytes) printable.  Exactly one in the data hunk."""
    d = old.hunks[old.label(6, 0x104)[0]]["data"]
    hits = []
    for p in range(0, len(d) - 2, 2):
        n = word(d, p)
        if not 200 <= n <= 1000 or p + 2 + n * ITEM_SIZE > len(d):
            continue
        ok = True
        for i in range(n):
            name = d[p + 2 + i * ITEM_SIZE + 40:p + 2 + (i + 1) * ITEM_SIZE]
            if not (0x20 <= name[0] < 0xFF) or any(c and c < 0x20 for c in name):
                ok = False
                break
        if ok:
            hits.append(p)
    if len(hits) != 1:
        raise Error("item table: %d candidates" % len(hits))
    p = hits[0]
    return d[p:p + 2 + word(d, p) * ITEM_SIZE]


def buttons(old):
    oh, ov = old.label(5, 0)
    d = old.hunks[oh]["data"]
    if ov + BUTTONS_SIZE > len(d):
        raise Error("Button_graphics runs past the data hunk")
    return d[ov:ov + BUTTONS_SIZE]


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--amberfiles", default=paths.amberfiles())
    p.add_argument("--out", default="build/thalion")
    a = p.parse_args()
    source = a.amberfiles
    target = os.path.join(a.out, "Amberfiles")
    # build_falcon.sh and build_st.sh source build_common.sh again under
    # build_all.sh, with AMBER_DATEN already pointing here: the folder is
    # made, not made again (and never removed while it is the source).
    if os.path.realpath(source) == os.path.realpath(target):
        print(os.path.abspath(a.out))
        return
    if not am2cpu_old.is_old(os.path.join(source, "AM2_CPU")):
        return
    old = OldCpu(os.path.join(source, "AM2_CPU"))
    if os.path.isdir(target):
        shutil.rmtree(target)
    os.makedirs(target)
    for n in os.listdir(source):
        q = os.path.join(source, n)
        if os.path.isfile(q):
            shutil.copyfile(q, os.path.join(target, n))
    new = {
        "Text.amb": text_amb(old),
        "Objects.amb": item_table(old),
        "Button_graphics": buttons(old),
        "Saves": bytes(SAVES_SIZE),
    }
    for n, b in new.items():
        open(os.path.join(target, n), "wb").write(b)
    dictionaries = [n for n in os.listdir(source) if n.startswith("Dictionary.")]
    if len(dictionaries) != 1:
        raise Error("expected one Dictionary.* in %s, found %d" % (source, len(dictionaries)))
    shutil.copyfile(os.path.join(source, dictionaries[0]), os.path.join(target, "Dict.amb"))
    shutil.copyfile(os.path.join(source, "Monster_char_data.amb"),
                    os.path.join(target, "Monster_char.amb"))
    start = os.path.join(source, "Initial")
    for place in range(11):
        shutil.copytree(start, os.path.join(target, "Save.%02d" % place))
    print("  Thalion %s: Text.amb %d, Objects.amb %d (%d items), Button_graphics, "
          "Dict.amb, Monster_char.amb, Saves, Save.00-10 -> %s"
          % (old.version, len(new["Text.amb"]), len(new["Objects.amb"]),
             word(new["Objects.amb"], 0), target), file=sys.stderr)
    print(os.path.abspath(a.out))


if __name__ == "__main__":
    main()
