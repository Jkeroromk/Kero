#!/usr/bin/env python3
"""Builds Kero's bundled game database from No-Intro data.

Inputs (not checked in; fetch with Tools/metadata/fetch.sh):
  libretro-database/metadat/no-intro/Nintendo - Game Boy*.dat   (CC BY-SA 4.0, libretro / No-Intro)
  boxarts-<system>.txt   file list of libretro-thumbnails' Named_Boxarts (to know which covers exist)

Output: Kero/Resources/GameDB/{gba,gbc,gb,nds}.tsv, one game per line:
  sha1  serial  title  region  languages  flags  boxart
- title: display title in English ("The Legend of Zelda: The Minish Cap")
- languages: comma-separated ISO 639-1 codes
- flags: comma-separated subset of beta, proto, demo, unl, hack, alt
- boxart: name of the cover in libretro-thumbnails (without .png), possibly borrowed from another
  release of the same game, or empty

The generated files are derived from libretro-database and are therefore CC BY-SA 4.0.
"""

import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

SYSTEMS = {
    "gba": ("Nintendo - Game Boy Advance", "Nintendo_-_Game_Boy_Advance"),
    "gbc": ("Nintendo - Game Boy Color", "Nintendo_-_Game_Boy_Color"),
    "gb": ("Nintendo - Game Boy", "Nintendo_-_Game_Boy"),
    "nds": ("Nintendo - Nintendo DS", "Nintendo_-_Nintendo_DS"),
}

REGION_LANGUAGES = {
    "USA": "en", "Europe": "en", "World": "en", "Australia": "en", "UK": "en", "Canada": "en",
    "Japan": "ja", "Germany": "de", "France": "fr", "Spain": "es", "Italy": "it", "Netherlands": "nl",
    "Sweden": "sv", "Brazil": "pt", "Portugal": "pt", "Korea": "ko", "China": "zh", "Taiwan": "zh",
    "Hong Kong": "zh", "Russia": "ru", "Denmark": "da", "Norway": "no", "Finland": "fi", "Poland": "pl",
}

REGION_PRIORITY = ["USA", "World", "Europe", "Australia", "UK", "Japan"]

LANGUAGE_TAG = re.compile(r"^[A-Z][a-z](?:-[A-Z][a-z]+)?(?:,[A-Z][a-z](?:-[A-Z][a-z]+)?)*$")
GAME_BLOCK = re.compile(r'game \(\s*name "((?:[^"\\]|\\.)*)"(.*?)\n\)', re.S)


def parse_dat(path):
    with open(path, encoding="utf-8", errors="replace") as file:
        text = file.read()

    games = []
    for match in GAME_BLOCK.finditer(text):
        name, body = match.group(1), match.group(2)
        region = re.search(r'region "([^"]*)"', body)
        serial = re.search(r'serial "([^"]*)"', body)
        sha1 = re.search(r"sha1 ([0-9A-Fa-f]{40})", body)
        if not sha1:
            continue
        games.append({
            "name": name,
            "region": region.group(1) if region else "",
            "serial": serial.group(1).strip() if serial else "",
            "sha1": sha1.group(1).lower(),
        })
    return games


def tags(name):
    return re.findall(r"\(([^)]*)\)", name)


def base_title(name):
    return name.split(" (")[0].strip()


def display_title(name):
    title = base_title(name)

    # "Legend of Zelda, The - Minish Cap" → "The Legend of Zelda - Minish Cap"
    title = re.sub(r"^(.+?), (The|A|An)( - |$)", lambda m: f"{m.group(2)} {m.group(1)}{m.group(3)}", title)

    if title.startswith("Pokemon - "):
        title = "Pokémon " + title[len("Pokemon - "):]
    elif title.startswith("Pokemon "):
        title = "Pokémon " + title[len("Pokemon "):]

    return title.replace(" - ", ": ")


def languages(game):
    for tag in tags(game["name"]):
        if LANGUAGE_TAG.match(tag):
            return ",".join(code.split("-")[0].lower() for code in tag.split(","))

    codes = []
    for region in game["region"].split(","):
        code = REGION_LANGUAGES.get(region.strip())
        if code and code not in codes:
            codes.append(code)
    return ",".join(codes or ["en"])


def flags(game):
    result = []
    lowered = [t.lower() for t in tags(game["name"])]
    for tag in lowered:
        if tag.startswith("beta"): result.append("beta")
        if tag.startswith("proto"): result.append("proto")
        if tag.startswith("demo") or tag.startswith("sample") or tag.startswith("kiosk"): result.append("demo")
        if tag == "unl" or tag == "pirate": result.append("unl")
        if tag.startswith("hack"): result.append("hack")
        if tag.startswith("alt"): result.append("alt")
    return ",".join(dict.fromkeys(result))


def thumbnail_name(name):
    return re.sub(r'[&*/:`<>?\\|]', "_", name)


def rank(game):
    """Lower is better: clean retail releases from preferred regions first."""
    penalty = 0 if not flags(game) else 10
    regions = [r.strip() for r in game["region"].split(",")]
    best = min((REGION_PRIORITY.index(r) for r in regions if r in REGION_PRIORITY), default=len(REGION_PRIORITY))
    return (penalty, best, len(game["name"]))


def build(key):
    dat_name, thumbs_repo = SYSTEMS[key]
    dat = os.path.join(sys.argv[1], f"{dat_name}.dat")
    boxart_list = os.path.join(sys.argv[2], f"boxarts-{thumbs_repo}.txt")

    games = parse_dat(dat)

    with open(boxart_list, encoding="utf-8") as file:
        boxarts = {line.strip()[len("Named_Boxarts/"):-len(".png")] for line in file if line.strip().endswith(".png")}

    by_serial = defaultdict(list)
    by_title = defaultdict(list)
    for game in games:
        if game["serial"]:
            # Region letter differs between releases (BPEE, BPEJ…); the first three identify the game.
            by_serial[game["serial"][:3]].append(game)
        by_title[base_title(game["name"]).lower()].append(game)

    def cover_for(game):
        own = thumbnail_name(game["name"])
        if own in boxarts:
            return own

        # Borrow from another release of the same game (same serial, else same title), best region first.
        relatives = by_serial.get(game["serial"][:3], []) if game["serial"] else []
        relatives = relatives or by_title.get(base_title(game["name"]).lower(), [])
        for other in sorted(relatives, key=rank):
            candidate = thumbnail_name(other["name"])
            if candidate in boxarts:
                return candidate
        return ""

    rows = []
    seen = set()
    for game in sorted(games, key=lambda g: g["name"].lower()):
        if game["sha1"] in seen:
            continue
        seen.add(game["sha1"])
        rows.append("\t".join([
            game["sha1"], game["serial"], display_title(game["name"]), game["region"],
            languages(game), flags(game), cover_for(game),
        ]))

    out_dir = os.path.join(ROOT, "Kero", "Resources", "GameDB")
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, f"{key}.tsv"), "w", encoding="utf-8") as file:
        file.write("\n".join(rows) + "\n")

    with_cover = sum(1 for r in rows if r.rsplit("\t", 1)[1])
    print(f"{key}: {len(rows)} games, {with_cover} with covers")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: build_gamedb.py <no-intro dat dir> <boxart list dir>")
        sys.exit(2)
    for system in SYSTEMS:
        build(system)
