#!/usr/bin/env python3
"""
Cross-check testdata links: series.json ↔ sets.json ↔ cards/*.json ↔ pricing/card-pricing ↔ pokemon.json.
Run from repo root: python3 scripts/validate_testdata_links.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def load_json(path: Path):
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    td = root / "testdata"
    cards_dir = td / "cards"
    pricing_dir = td / "pricing" / "card-pricing"

    errors: list[str] = []
    warnings: list[str] = []

    series_path = td / "series.json"
    sets_path = td / "sets.json"
    pokemon_path = td / "pokemon.json"

    for p in (series_path, sets_path, pokemon_path):
        if not p.exists():
            errors.append(f"Missing required file: {p.relative_to(root)}")
            return report(errors, warnings)

    series_rows = load_json(series_path)
    series_names = {r["name"] for r in series_rows}

    sets_raw = load_json(sets_path)
    set_keys = []
    set_keys_seen: dict[str, str] = {}  # setKey -> first set name for dup reporting

    for s in sets_raw:
        sk = s.get("setKey")
        if not sk:
            errors.append(f"Set missing setKey: id={s.get('id')!r} name={s.get('name')!r}")
            continue
        if sk in set_keys_seen:
            errors.append(
                f"Duplicate setKey {sk!r}: {s.get('name')!r} and {set_keys_seen[sk]!r}"
            )
        else:
            set_keys_seen[sk] = s.get("name", "")
        set_keys.append(sk)

        sn = s.get("seriesName")
        if sn and sn not in series_names:
            errors.append(
                f"sets.json set {sk!r} ({s.get('name')}) has seriesName {sn!r} not found in series.json names"
            )

    set_key_set = set(set_keys)

    # Card files on disk
    card_files = {p.stem for p in cards_dir.glob("*.json")}

    for sk in set_key_set:
        if sk not in card_files:
            errors.append(f"sets.json setKey {sk!r} has no {cards_dir.name}/{sk}.json")

    # Orphan card files (not referenced by any set)
    for stem in sorted(card_files - set_key_set):
        warnings.append(f"Card file {stem}.json is not referenced by any setKey in sets.json")

    # Pokemon dex numbers
    pokemon_rows = load_json(pokemon_path)
    dex_numbers = {int(r["nationalDexNumber"]) for r in pokemon_rows}

    master_ids: dict[str, tuple[str, str]] = {}  # masterCardId -> (setKey, externalId)

    for sk in sorted(set_key_set):
        cpath = cards_dir / f"{sk}.json"
        if not cpath.exists():
            continue
        try:
            cards = load_json(cpath)
        except json.JSONDecodeError as e:
            errors.append(f"Invalid JSON {cpath.relative_to(root)}: {e}")
            continue
        if not isinstance(cards, list):
            errors.append(f"{cpath.relative_to(root)}: expected top-level array")
            continue

        ext_ids_in_file: set[str] = set()
        external_id_prefix_mismatches = 0
        for i, card in enumerate(cards):
            if card.get("setCode") != sk:
                errors.append(
                    f"{cpath.name} card index {i}: setCode {card.get('setCode')!r} != file setKey {sk!r}"
                )
            ext = card.get("externalId")
            if ext:
                es = str(ext)
                # Most cards use "{setKey}-{local}"; some use a longer product prefix (e.g. swsh12pt5gg-GG01).
                if not (es.startswith(sk + "-") or es == sk):
                    external_id_prefix_mismatches += 1
                ext_ids_in_file.add(es)
        if external_id_prefix_mismatches:
            warnings.append(
                f"{cpath.name}: {external_id_prefix_mismatches} card(s) with externalId not prefixed {sk + '-'!r} "
                f"(often alternate product codes; OK if pricing keys match)."
            )

            mid = card.get("masterCardId")
            if mid is None:
                errors.append(f"{cpath.name} card index {i}: missing masterCardId")
            else:
                ms = str(mid)
                if ms in master_ids:
                    prev_sk, prev_ext = master_ids[ms]
                    errors.append(
                        f"Duplicate masterCardId {ms!r}: {prev_sk}/{prev_ext} and {sk}/{ext}"
                    )
                else:
                    master_ids[ms] = (sk, str(ext))

            for d in card.get("dexIds") or []:
                try:
                    dn = int(d)
                except (TypeError, ValueError):
                    errors.append(f"{cpath.name} card index {i}: bad dexIds entry {d!r}")
                    continue
                if dn not in dex_numbers:
                    errors.append(
                        f"{cpath.name} externalId {ext!r}: dexId {dn} not in pokemon.json"
                    )

        # Pricing file for this set
        ppath = pricing_dir / f"{sk}.json"
        if not ppath.exists():
            warnings.append(f"No pricing file for setKey {sk!r} ({pricing_dir.name}/{sk}.json)")
            continue

        try:
            pricing = load_json(ppath)
        except json.JSONDecodeError as e:
            errors.append(f"Invalid JSON {ppath.relative_to(root)}: {e}")
            continue
        if not isinstance(pricing, dict):
            errors.append(f"{ppath.relative_to(root)}: expected top-level object")
            continue

        price_keys = set(pricing.keys())
        missing_price = ext_ids_in_file - price_keys
        extra_price = price_keys - ext_ids_in_file
        for k in sorted(missing_price):
            errors.append(
                f"{ppath.name}: card {k!r} exists in {sk}.json but has no pricing entry"
            )
        for k in sorted(extra_price):
            errors.append(
                f"{ppath.name}: pricing key {k!r} has no matching card in {sk}.json"
            )

    # Orphan pricing files (stem not a setKey), excluding known non-set buckets
    skip_pricing_orphans = {"unlisted", "jumbo", "rc", "sp", "wp", "xya", "exu"}
    for p in pricing_dir.glob("*.json"):
        stem = p.stem
        if stem in set_key_set:
            continue
        if stem in skip_pricing_orphans:
            continue
        if stem.startswith("tk-"):
            continue  # Trainer kit pricing buckets; may not have a row in sets.json
        warnings.append(
            f"Pricing file {p.name} does not match any setKey in sets.json (not in skip list)"
        )

    return report(errors, warnings)


def report(errors: list[str], warnings: list[str]) -> int:
    if warnings:
        print("Warnings:\n", file=sys.stderr)
        for w in warnings:
            print(f"  - {w}", file=sys.stderr)
        print(file=sys.stderr)
    if errors:
        print("Errors:\n", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        print(f"\n{len(errors)} error(s), {len(warnings)} warning(s)", file=sys.stderr)
        return 1
    print(f"OK: all cross-file checks passed ({len(warnings)} warning(s)).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
