#!/usr/bin/env python3
"""Membandingkan dua potret sistem buatan tools/Get-SystemSnapshot.ps1.

Pemakaian:
    python tools/compare-snapshots.py TGOS-snapshot-before.json TGOS-snapshot-after.json

Mencetak:
  - selisih angka (proses, thread, RAM, disk, layanan berjalan),
  - paket AppX yang hilang dan yang baru muncul,
  - paket yang seharusnya dihapus modul 10 tetapi masih ada,
  - paket yang dilindungi tetapi ikut hilang (ini tanda bahaya),
  - perubahan layanan dan tugas terjadwal,
  - status Defender dan restore point.

Hanya butuh Python 3.8+ dan PyYAML (dipakai lewat tools/validate.py).
"""
from __future__ import annotations

import argparse
import fnmatch
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_validator():
    """Memuat tools/validate.py sebagai modul supaya daftar dan parser YAML-nya dipakai ulang."""
    spec = importlib.util.spec_from_file_location("tgos_validate", ROOT / "tools" / "validate.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["tgos_validate"] = module
    spec.loader.exec_module(module)
    return module


def as_list(value) -> list:
    """PowerShell menulis daftar berisi satu elemen sebagai objek, dan daftar kosong sebagai null."""
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def load_snapshot(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as exc:
        sys.exit(f"Tidak bisa membaca {path}: {exc}")
    if not isinstance(data, dict) or data.get("schema") != 1:
        sys.exit(f"{path} bukan potret TGOS versi 1")
    return data


def number(snapshot: dict, section: str, key: str):
    part = snapshot.get(section)
    if isinstance(part, dict) and isinstance(part.get(key), (int, float)):
        return part[key]
    return None


def print_metric(label: str, before, after, unit: str = "") -> None:
    if before is None or after is None:
        print(f"  {label:<26} tidak tersedia")
        return
    delta = round(after - before, 2)
    percent = f"{delta / before * 100:+.1f}%" if before else "n/a"
    print(f"  {label:<26} {before:>10} -> {after:>10} {unit:<3} ({delta:+} / {percent})")


def expected_removals(validator) -> list[tuple[str, str | None]]:
    """Daftar (pola nama, opsi) dari aksi !appx hapus di modul 10."""
    path = ROOT / "src" / "Configuration" / "Tasks" / "10-debloat-appx.yml"
    if not path.is_file():
        return []
    import yaml
    document = yaml.load(path.read_text(encoding="utf-8"), Loader=validator.PlaybookLoader)
    result = []
    for action in document.get("actions", []):
        if getattr(action, "tag", None) != "appx" or not isinstance(action.body, dict):
            continue
        if str(action.body.get("operation", "remove")).lower() != "remove":
            continue
        result.append((action.body["name"], action.body.get("option")))
    return result


def matches(pattern: str, family: str) -> bool:
    return fnmatch.fnmatchcase(family.lower(), pattern.lower())


def main() -> int:
    parser = argparse.ArgumentParser(description="Membandingkan dua potret sistem TGOS.")
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()

    validator = load_validator()
    before = load_snapshot(args.before)
    after = load_snapshot(args.after)

    print(f"Sebelum : {before.get('label')} ({before.get('collectedAt')})")
    print(f"Sesudah : {after.get('label')} ({after.get('collectedAt')})")
    for name, snapshot in (("sebelum", before), ("sesudah", after)):
        if not snapshot.get("isAdmin"):
            print(f"PERINGATAN: potret {name} tidak diambil sebagai Administrator; daftar AppX tidak lengkap")
        for error in as_list(snapshot.get("errors")):
            print(f"PERINGATAN: potret {name}: {error}")

    os_before, os_after = before.get("os") or {}, after.get("os") or {}
    print(f"\nWindows : {os_after.get('edition')} {os_after.get('displayVersion')} "
          f"build {os_after.get('build')}.{os_after.get('updateRevision')}")
    if (os_before.get("build"), os_before.get("updateRevision")) != \
            (os_after.get("build"), os_after.get("updateRevision")):
        print("PERINGATAN: build Windows berbeda antara dua potret; angka tidak sebanding")

    def running(snapshot: dict) -> int | None:
        services = as_list(snapshot.get("services"))
        if not services:
            return None
        return sum(1 for item in services if item.get("state") == "Running")

    print("\nAngka")
    print_metric("Proses", number(before, "counts", "processes"), number(after, "counts", "processes"))
    print_metric("Thread", number(before, "counts", "threads"), number(after, "counts", "threads"))
    print_metric("Handle", number(before, "counts", "handles"), number(after, "counts", "handles"))
    print_metric("RAM terpakai", number(before, "memory", "inUseMb"), number(after, "memory", "inUseMb"), "MB")
    print_metric("Disk terpakai", number(before, "disk", "usedGb"), number(after, "disk", "usedGb"), "GB")
    print_metric("Layanan berjalan", running(before), running(after))

    # --- AppX ---------------------------------------------------------------------
    families_before = {item["familyName"] for item in as_list(before.get("appx")) if item.get("familyName")}
    families_after = {item["familyName"] for item in as_list(after.get("appx")) if item.get("familyName")}
    removed = sorted(families_before - families_after)
    added = sorted(families_after - families_before)

    print(f"\nPaket AppX: {len(families_before)} -> {len(families_after)}")
    print(f"  Hilang ({len(removed)}):")
    for family in removed:
        print(f"    - {family}")
    if added:
        print(f"  Baru muncul ({len(added)}):")
        for family in added:
            print(f"    + {family}")

    problems = 0

    # Opsi yang dipilih saat instalasi tercatat di install-info.txt.
    selected = {line.split(":", 1)[1].strip()
                for line in as_list(after.get("tgosInstallInfo"))
                if isinstance(line, str) and line.startswith("Option selected")}

    still_present = []
    skipped = []
    for pattern, option in expected_removals(validator):
        for family in sorted(families_after):
            if matches(pattern, family):
                if option and option not in selected:
                    skipped.append((family, option))
                else:
                    still_present.append(family)
    if still_present:
        print("\n  Seharusnya dihapus tetapi masih ada:")
        for family in still_present:
            print(f"    ! {family}")
        problems += len(still_present)
    else:
        print("\n  Semua paket yang seharusnya dihapus sudah tidak ada.")
    if skipped:
        print("\n  Dibiarkan karena opsinya tidak dipilih:")
        for family, option in skipped:
            print(f"    . {family}  (opsi '{option}')")

    protected_lost = [family for family in removed
                      if any(matches(name + "_*", family) for name in validator.PROTECTED_APPX)]
    if protected_lost:
        print("\n  BAHAYA: paket yang dilindungi ikut hilang:")
        for family in protected_lost:
            print(f"    !! {family}")
        problems += len(protected_lost)

    # --- Layanan ------------------------------------------------------------------
    def service_map(snapshot: dict) -> dict:
        return {item["name"]: (item.get("state"), item.get("startMode"))
                for item in as_list(snapshot.get("services")) if item.get("name")}

    services_before, services_after = service_map(before), service_map(after)
    changed = [(name, services_before[name], services_after[name])
               for name in sorted(services_before.keys() & services_after.keys())
               if services_before[name][1] != services_after[name][1]]
    gone = sorted(services_before.keys() - services_after.keys())
    print(f"\nLayanan: start type berubah {len(changed)}, hilang {len(gone)}")
    for name, old, new in changed:
        print(f"    {name}: {old[1]} -> {new[1]}")
    for name in gone:
        print(f"    - {name}")

    # --- Tugas terjadwal ----------------------------------------------------------
    def task_map(snapshot: dict) -> dict:
        return {item["path"]: item.get("state")
                for item in as_list(snapshot.get("scheduledTasks")) if item.get("path")}

    tasks_before, tasks_after = task_map(before), task_map(after)
    task_changed = [(path, tasks_before[path], tasks_after[path])
                    for path in sorted(tasks_before.keys() & tasks_after.keys())
                    if tasks_before[path] != tasks_after[path]
                    and "Disabled" in (tasks_before[path], tasks_after[path])]
    task_gone = sorted(tasks_before.keys() - tasks_after.keys())
    print(f"\nTugas terjadwal: aktif/nonaktif berubah {len(task_changed)}, hilang {len(task_gone)}")
    for path, old, new in task_changed:
        print(f"    {path}: {old} -> {new}")
    for path in task_gone:
        print(f"    - {path}")

    # --- Defender dan restore point -----------------------------------------------
    defender_before, defender_after = before.get("defender") or {}, after.get("defender") or {}
    print("\nDefender (proteksi real-time): "
          f"{defender_before.get('realTimeProtectionEnabled')} -> "
          f"{defender_after.get('realTimeProtectionEnabled')}")
    if defender_before.get("realTimeProtectionEnabled") and \
            defender_after.get("realTimeProtectionEnabled") is False:
        print("  PERINGATAN: proteksi real-time mati setelah TGOS; seharusnya tetap aktif")
        problems += 1

    new_points = [point for point in as_list(after.get("restorePoints"))
                  if point not in as_list(before.get("restorePoints"))]
    print(f"Restore point baru: {', '.join(new_points) if new_points else 'tidak ada'}")

    info = as_list(after.get("tgosInstallInfo"))
    if info:
        print("\ninstall-info.txt:")
        for line in info:
            print(f"    {line}")

    print(f"\nSelesai: {problems} hal perlu diperiksa" if problems else "\nSelesai: tidak ada masalah terdeteksi")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
