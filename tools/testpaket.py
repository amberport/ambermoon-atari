#!/usr/bin/env python3
"""Test package for one hardware date: collect the builds of all worktrees
into one folder ATARI/ for Falcon and Mega STE.

    python3 tools/testpaket.py zeigen              # what would go, how old
    python3 tools/testpaket.py ordner [PFAD]       # lay out PFAD/ATARI/
    python3 tools/testpaket.py karte ZIEL [--echt] # ATARI/ onto a card
    python3 tools/testpaket.py falcon [--echt] [--pruefen]

Tables: every worktree (main included) may hold
tools/testpaket_<branch>.tab; each line names one file or folder:

    Test  Machine  Source  Name
    T26   falcon   build/test/T26ENG.TOS   T26ENG.TOS
    T24   beide    ATARI                   -

Machine is falcon, st or beide (both).  Source is relative to the root of
the worktree that holds the table.  The package always holds a whole build
(AMBER.TOS, AMBFILES\\ with the game data): main's ATARI/, unless folder
lines (Name -) name others; those are laid over the root of ATARI/ in
table order instead.  A test that asks for the normal build names main's
ATARI in a folder line, so that it appears in TESTS.TXT.  A whole build
without AMBER.TOS or AMBFILES/ stops the run.  Of the programs in a whole
build only the game's go along (SPIEL_TOS); the measuring and diagnostic
builds the Falcon build also delivers (FEEDIAG.TOS, INTROMES.TOS ...) stay
out unless a file line names them (user, 2026-10-21).  A file lands in
AMBFILES\\ under Name (8.3).  A test number in the tables of two worktrees,
or one target name from two sources, stops the run.

The instructions TESTS.TXT come from the test rows (| Tnn | What | ... |
HW |) in the status file of the worktree whose table names the test: main
docs/05, falcon-tempo docs/05b, st docs/05c, doku docs/05d; without that
file, that worktree's docs/05.  One TESTS.TXT, sorted by machine.

`ordner` acts at once, without --echt; default PFAD is TEST/ in the
repository (not versioned).  It first removes what an earlier run left in
PFAD/ATARI/.  `karte` copies the same layout into ZIEL (the folder that is
ATARI\\ on the machine).  `falcon` sends only the files of the file lines
and TESTS.TXT through uIPtool (HTTP PUT, `curl -0 -T`,
codeberg.org/nokturnal/uiptool) to the address AMBER_FALCON (no default;
a variable or a line in build.cfg, tools/paths.py), folder AMBER_FALCON_ORDNER (default /g, i.e. G:\\); the whole build goes
once by card (`karte`).

Save games (SAVE*, SAVES, and everything inside the SAVE.nn folders) and
*.INF are never touched, except for the E17 cut (2026-10-24): `ordner` and
`karte` turn an old MUSIK.INF in ATARI\\AMBFILES into AMBER.INF once and
delete MUSIK.INF and ST.INF, as the build does.  Every mode refuses a
program that still names MUSIK.INF or ST.INF: it was built before the cut.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GESAMTBAU = os.path.join(WURZEL, 'ATARI')    # main's whole build, the default

# Status file per branch; a branch not listed, or a worktree without the
# file, falls back to its docs/05.
STATUS = {'main': 'docs/05-Naechste-Schritte.md',
          'falcon-tempo': 'docs/05b-Falcon-Tempo.md',
          'intro': 'docs/05b-Falcon-Tempo.md',
          'st': 'docs/05c-ST.md',
          'doku': 'docs/05d-Doku.md'}
STATUS_SONST = 'docs/05-Naechste-Schritte.md'

RECHNER = {'falcon': ('falcon',), 'st': ('st',), 'beide': ('falcon', 'st')}

FALCON = paths.value('AMBER_FALCON')     # the test Falcon's address, personal
FALCON_ORDNER = os.environ.get('AMBER_FALCON_ORDNER', '/g').rstrip('/')


# The programs of the game, for both machines.  Every other *.TOS in a
# folder line stays out of the package.
SPIEL_TOS = {'AMBER.TOS', 'ENGINE.TOS', 'ENGINEST.TOS',
             'FANTASY.TOS', 'INTRO.TOS', 'EXTRO.TOS',
             'FANTSYST.TOS', 'INTROST.TOS', 'EXTROST.TOS'}


def nur_messbau(name):
    n = name.upper()
    return n.endswith('.TOS') and n not in SPIEL_TOS


def geschuetzt(pfad):
    # Every part of the path counts: SAVE.01/PARTY.DAT is a save game too.
    teile = os.path.normpath(pfad).upper().split(os.sep)
    return (any(t.startswith('SAVE') for t in teile)
            or teile[-1].endswith('.INF'))


def neueste(ordner):
    # Newest modification time below a folder.
    zeit = os.path.getmtime(ordner)
    for wurzel, _, dateien in os.walk(ordner):
        for d in dateien:
            zeit = max(zeit, os.path.getmtime(os.path.join(wurzel, d)))
    return zeit


def worktrees():
    """(path, branch) of every worktree, main first."""
    aus = subprocess.run(['git', '-C', WURZEL, 'worktree', 'list', '--porcelain'],
                         capture_output=True, text=True, check=True).stdout
    liste, pfad = [], None
    for z in aus.splitlines():
        if z.startswith('worktree '):
            pfad = z[9:]
        elif z.startswith('branch ') and pfad:
            liste.append((pfad, z[7:].removeprefix('refs/heads/')))
    return sorted(liste, key=lambda w: w[1] != 'main')


class Zeile:
    def __init__(self, test, rechner, quelle, name, ort, zweig):
        self.test, self.rechner, self.quelle, self.name = test, rechner, quelle, name
        self.ort, self.zweig = ort, zweig       # where the table lies
        self.ordner = name == '-'


def tabellen_lesen():
    zeilen, herkunft = [], {}
    for pfad, zweig in worktrees():
        tab = os.path.join(pfad, 'tools', f'testpaket_{zweig.replace("/", "-")}.tab')
        if not os.path.exists(tab):
            continue
        for nr, z in enumerate(open(tab, encoding='utf-8'), 1):
            z = z.split('#', 1)[0].strip()
            if not z:
                continue
            teile = z.split()
            wo = f'{os.path.relpath(tab, WURZEL)}:{nr}'
            if len(teile) != 4 or teile[1] not in RECHNER:
                sys.exit(f'{wo}: expected "Test Machine Source Name" '
                         f'(machine falcon, st or beide)')
            test, rechner, quelle, name = teile
            if herkunft.setdefault(test, zweig) != zweig:
                sys.exit(f'{wo}: {test} also stands in the table of '
                         f'{herkunft[test]}; one test, one table')
            if name != '-':
                stamm, _, endung = name.partition('.')
                if len(stamm) > 8 or len(endung) > 3 or geschuetzt(name):
                    sys.exit(f'{wo}: {name} is not an allowed 8.3 name')
            zeilen.append(Zeile(test, rechner, os.path.join(pfad, quelle),
                                name, pfad, zweig))
    ziele = {}
    for z in zeilen:
        if not z.ordner and ziele.setdefault(z.name.upper(), z.quelle) != z.quelle:
            sys.exit(f'{z.name} comes from two sources: {ziele[z.name.upper()]} '
                     f'and {z.quelle}')
    return zeilen


def testliste_lesen(zeilen):
    """Nr -> (What, HW) from the status file of the table's worktree."""
    tests, gelesen = {}, set()
    for z in zeilen:
        if z.ort in gelesen:
            continue
        gelesen.add(z.ort)
        datei = os.path.join(z.ort, STATUS.get(z.zweig, STATUS_SONST))
        if not os.path.exists(datei):
            datei = os.path.join(z.ort, STATUS_SONST)
        eigene = {t.test for t in zeilen if t.ort == z.ort}
        for zeile in open(datei, encoding='utf-8'):
            m = re.match(r'\| (T\d+[a-z]?) \|(.*)\|$', zeile.strip())
            if m and m.group(1) in eigene:
                spalten = [s.strip() for s in m.group(2).split('|')]
                if len(spalten) >= 2:
                    tests[m.group(1)] = (spalten[0], spalten[-1])
    return tests


ERSETZEN = {'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'Ä': 'Ae', 'Ö': 'Oe', 'Ü': 'Ue',
            'ß': 'ss', '„': '"', '“': '"', '”': '"', '–': '-', '—': '-',
            '×': 'x', '→': '->', '↔': '<->', '…': '...', '≠': '!=', '’': "'"}


def atari_text(s):
    s = s.replace('`', '').replace('**', '').replace('*', '')
    for a, b in ERSETZEN.items():
        s = s.replace(a, b)
    return s.encode('ascii', 'replace').decode('ascii')


def testnummer(test):
    """Sort key of a test number: T96 before T96a before T97."""
    m = re.match(r'T(\d+)(.*)$', test)
    return (int(m.group(1)), m.group(2)) if m else (1 << 30, test)


def tests_txt(zeilen):
    liste = testliste_lesen(zeilen)
    dateien, rechner = {}, {}
    for z in zeilen:
        if z.ordner:
            eintrag = 'whole build (ATARI\\)'
        elif os.path.basename(z.quelle).upper() != z.name.upper():
            eintrag = f'{z.name} (= {os.path.basename(z.quelle)})'
        else:
            eintrag = z.name
        if eintrag not in dateien.setdefault(z.test, []):
            dateien[z.test].append(eintrag)
        rechner.setdefault(z.test, set()).update(RECHNER[z.rechner])
    aus = [f'Ambermoon test package, packed {time.strftime("%Y-%m-%d %H:%M")}',
           '',
           'One folder ATARI\\ for both machines; AMBER.TOS starts the game',
           'on either.  Test programs lie in AMBFILES\\ and are',
           'started there directly.  Save games and *.INF are not in the',
           'package; the tests say which save games to copy by hand.',
           'Answer per number, e.g. "T26 good, T29 garbage lines".', '']
    for titel, menge in (('FALCON', {'falcon'}), ('MEGA STE', {'st'}),
                         ('FALCON AND MEGA STE', {'falcon', 'st'})):
        auswahl = sorted((t for t in dateien if rechner[t] == menge),
                         key=testnummer)
        if not auswahl:
            continue
        aus += [f'=== {titel} ===', '']
        for test in auswahl:
            was, hw = liste.get(test, ('(not in the test list of its status file)', ''))
            aus.append(f'{test}  [HW: {atari_text(hw)}]')
            for zeile in textwrap.wrap(atari_text(was), 72):
                aus.append('    ' + zeile)
            aus.append('    Files: ' + ', '.join(dateien[test]))
            aus.append('')
    return ('\r\n'.join(aus) + '\r\n').encode('ascii')


def zeigen(zeilen):
    fehlt = False
    for z in zeilen:
        if os.path.isdir(z.quelle):
            t = time.strftime('%m-%d %H:%M', time.localtime(neueste(z.quelle)))
            info = f'{t}  {"folder":>8}'
        elif os.path.isfile(z.quelle):
            t = time.strftime('%m-%d %H:%M', time.localtime(os.path.getmtime(z.quelle)))
            info = f'{t}  {os.path.getsize(z.quelle):>8}'
        else:
            info, fehlt = 'MISSING', True
        print(f'{z.test:<4} {z.rechner:<6} {z.name:<13} {info:<22} '
              f'{os.path.relpath(z.quelle, WURZEL)}')
    if not any(z.ordner for z in zeilen):
        if os.path.isdir(GESAMTBAU):
            t = time.strftime('%m-%d %H:%M', time.localtime(neueste(GESAMTBAU)))
            info = f'{t}  {"folder":>8}'
        else:
            info, fehlt = 'MISSING', True
        print(f'{"-":<4} {"beide":<6} {"(whole build)":<13} {info:<22} '
              f'{os.path.relpath(GESAMTBAU, WURZEL)}')
    if fehlt:
        sys.exit('Builds are missing, see above.')


def gesamtbauten(zeilen):
    """The whole builds in the package: the folder lines, else main's ATARI/.
    Without one the package would lack the game data (2026-10-27: after
    T24/T30 had passed, no folder line was left, and `ordner` emptied
    TEST/ATARI/ down to the test files)."""
    liste = []
    for q in [z.quelle for z in zeilen if z.ordner] or [GESAMTBAU]:
        if q not in liste:
            liste.append(q)
    for q in liste:
        if not (os.path.isfile(os.path.join(q, 'AMBER.TOS'))
                and os.path.isdir(os.path.join(q, 'AMBFILES'))):
            sys.exit(f'{os.path.relpath(q, WURZEL)} is no whole build '
                     f'(AMBER.TOS and AMBFILES/ expected); build first')
    return liste


def auftraege(zeilen):
    """(source, path below ATARI/) for every file, whole builds first."""
    liste = []
    for ordner in gesamtbauten(zeilen):
        for wurzel, _, dateien in os.walk(ordner):
            rel = os.path.relpath(wurzel, ordner)
            for d in sorted(dateien):
                if nur_messbau(d):
                    continue
                if not geschuetzt(os.path.join(rel, d)):
                    liste.append((os.path.join(wurzel, d),
                                  os.path.normpath(os.path.join(rel, d))))
    for z in zeilen:
        if not z.ordner:
            liste.append((z.quelle, os.path.join('AMBFILES', z.name)))
    return liste


# The E17 cut (2026-10-24): from then on every program reads only AMBER.INF.
ALTE_INF = ('MUSIK.INF', 'ST.INF')


def alte_namen_pruefen(zeilen):
    # A program built before the cut still names an old settings file; with
    # it the user would have to ask which file the build under test reads.
    schlecht = []
    for q, rel in auftraege(zeilen):
        if not q.upper().endswith('.TOS'):
            continue
        daten = open(q, 'rb').read()
        for n in ALTE_INF:
            if n.encode() in daten:
                schlecht.append(f'{os.path.relpath(q, WURZEL)}: names {n}')
    if schlecht:
        sys.exit('Built before the E17 cut (reads an old settings file, not '
                 'AMBER.INF); rebuild it or take its line out of the table:\n  '
                 + '\n  '.join(schlecht))


def inf_umstellen(atari):
    # As settings_file in build_common.sh: an old MUSIK.INF becomes AMBER.INF
    # once (AUS -> MUSIC=OFF, DSP, CPU, YM), MUSIK.INF and ST.INF go; without
    # AMBER.INF the template.  A changed AMBER.INF stays.
    daten = os.path.join(atari, 'AMBFILES')
    neu = os.path.join(daten, 'AMBER.INF')
    for ort in (daten, atari):
        alt = os.path.join(ort, 'MUSIK.INF')
        if os.path.isfile(alt) and not os.path.exists(neu):
            wahl = open(alt, 'rb').read(3).decode('latin-1').upper()
            wert = {'AUS': 'OFF', 'DSP': 'DSP', 'CPU': 'CPU'}.get(
                wahl, 'YM' if wahl.startswith('YM') else None)
            if wert:
                vorlage = open(os.path.join(WURZEL, 'tools', 'amber.inf')).read()
                os.makedirs(daten, exist_ok=True)
                open(neu, 'w').write(
                    vorlage.replace('MUSIC=DSP ', f'MUSIC={wert} ', 1))
                print(f'{alt} ({wahl}) -> AMBER.INF, MUSIC={wert}')
        for n in ALTE_INF:
            p = os.path.join(ort, n)
            if os.path.isfile(p):
                os.remove(p)
                print(f'removed {p} (read by no program since the E17 cut)')
    if not os.path.exists(neu):
        os.makedirs(daten, exist_ok=True)
        shutil.copyfile(os.path.join(WURZEL, 'tools', 'amber.inf'), neu)
        print(f'{neu}: template (MUSIC=DSP, PLAIN_ST=NO)')


def leeren(ordner):
    # Remove the files of an earlier run, keeping save games and *.INF.
    for wurzel, _, dateien in os.walk(ordner):
        for d in dateien:
            p = os.path.join(wurzel, d)
            if not geschuetzt(os.path.relpath(p, ordner)):
                os.remove(p)


def auslegen(zeilen, ziel, echt):
    for q, rel in auftraege(zeilen):
        z = os.path.join(ziel, rel)
        if not echt:
            print(f'cp {os.path.relpath(q, WURZEL)} -> {z}')
            continue
        os.makedirs(os.path.dirname(z), exist_ok=True)
        shutil.copyfile(q, z)
    z = os.path.join(ziel, 'TESTS.TXT')
    if not echt:
        print(f'TESTS.TXT -> {z}\n\nOnly shown.  With --echt it is copied.')
        return False
    open(z, 'wb').write(tests_txt(zeilen))
    return True


def nach_ordner(zeilen, pfad):
    ziel = os.path.join(pfad, 'ATARI')
    os.makedirs(ziel, exist_ok=True)
    leeren(ziel)
    inf_umstellen(ziel)
    auslegen(zeilen, ziel, True)
    n = sum(1 for z in zeilen if not z.ordner)
    bauten = ', '.join(os.path.relpath(q, WURZEL) for q in gesamtbauten(zeilen))
    print(f'{ziel}: whole build ({bauten}) and {n} test files, with TESTS.TXT')


def nach_karte(zeilen, ziel, echt):
    if not os.path.isdir(ziel):
        sys.exit(f'{ziel} is not a folder (card mounted?)')
    if echt:
        inf_umstellen(ziel)
    if auslegen(zeilen, ziel, echt):
        os.sync()
        print(f'copied to {ziel}, synced.  Unmount the card now.')


def curl(argumente):
    r = subprocess.run(['curl', '-0', '-sS', '-m', '300'] + argumente,
                       capture_output=True)
    return r.returncode, r.stdout, r.stderr.decode(errors='replace')


def nach_falcon(zeilen, echt, pruefen):
    if not FALCON:
        sys.exit('AMBER_FALCON is not set: the test Falcon\'s address, as a '
                 'variable or in build.cfg (build.cfg.example)')
    basis = f'http://{FALCON}{FALCON_ORDNER}'
    liste = [(z.quelle, f'{basis}/AMBFILES/{z.name}') for z in zeilen
             if not z.ordner]
    txt = tests_txt(zeilen)
    if not echt:
        for q, ziel in liste:
            print(f'PUT {os.path.relpath(q, WURZEL)} -> {ziel}')
        print(f'PUT TESTS.TXT ({len(txt)} bytes) -> {basis}/TESTS.TXT')
        print('\nOnly shown.  With --echt it is sent.  The whole build '
              '(folder lines) goes by card.')
        return
    code, aus, fehler = curl(['-m', '5', '-o', '/dev/null', '-w', '%{http_code}',
                              f'{basis}/?dir'])
    if code != 0 or aus.decode() != '200':
        sys.exit(f'Falcon at {FALCON} does not answer (uIPtool running?): '
                 f'{fehler.strip() or aus.decode()}')
    with tempfile.TemporaryDirectory() as tmp:
        txt_datei = os.path.join(tmp, 'TESTS.TXT')
        open(txt_datei, 'wb').write(txt)
        liste.append((txt_datei, f'{basis}/TESTS.TXT'))
        for q, ziel in liste:
            t0 = time.time()
            code, aus, fehler = curl(['-T', q, '-o', '/dev/null', '-w', '%{http_code}', ziel])
            if code != 0 or not aus.decode().startswith('2'):
                sys.exit(f'Error at {ziel}: {fehler.strip() or aus.decode()}')
            zeile = f'good {os.path.getsize(q):>8} bytes  {time.time()-t0:5.1f} s  {ziel}'
            if pruefen:
                zurueck = os.path.join(tmp, 'zurueck')
                code, _, fehler = curl(['-o', zurueck, ziel])
                if code != 0 or open(zurueck, 'rb').read() != open(q, 'rb').read():
                    sys.exit(f'Read-back failed: {ziel} {fehler.strip()}')
                zeile += '  (read back)'
            print(zeile)


def main():
    a = sys.argv[1:]
    echt, pruefen = '--echt' in a, '--pruefen' in a
    a = [x for x in a if not x.startswith('--')]
    zeilen = tabellen_lesen()
    if not a or a[0] == 'zeigen':
        zeigen(zeilen)
        return
    zeigen(zeilen)
    print()
    alte_namen_pruefen(zeilen)
    if a[0] == 'ordner' and len(a) <= 2:
        nach_ordner(zeilen, a[1] if len(a) == 2 else os.path.join(WURZEL, 'TEST'))
    elif a[0] == 'karte' and len(a) == 2:
        nach_karte(zeilen, a[1], echt)
    elif a[0] == 'falcon':
        nach_falcon(zeilen, echt, pruefen)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
