#!/usr/bin/env python3
"""Membuat expected-state.json: keadaan sistem yang seharusnya setelah TGOS diterapkan.

File itu dibaca Test-TgosResult.ps1 di Windows untuk memeriksa hasil instalasi butir
demi butir. Karena dibuat dari YAML yang sama dengan yang dijalankan AME Wizard, daftar
pemeriksaan tidak bisa berbeda dari playbook.

Yang dimasukkan:
  - setiap !registryValue  -> nilai registry harus sama (atau tidak ada, untuk delete)
  - setiap !appx hapus     -> paket tidak boleh terpasang
  - setiap !service change -> nilai Start layanan
  - setiap baris di Executables/TGOS/scheduled-tasks.txt -> tugas harus Disabled

Syarat tiap aksi (option, builds) ikut disimpan; skrip pemeriksa menilainya di Windows.

Pemakaian:
    python tools/make-expected-state.py           # tulis ulang file
    python tools/make-expected-state.py --check   # kode keluar 1 bila file usang
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path, PureWindowsPath

import yaml

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "src" / "Configuration"
TASK_LIST = ROOT / "src" / "Executables" / "TGOS" / "scheduled-tasks.txt"
OUTPUT = ROOT / "src" / "Executables" / "TGOS Toolbox" / "Support" / "expected-state.json"


def load_validator():
    spec = importlib.util.spec_from_file_location("tgos_validate", ROOT / "tools" / "validate.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["tgos_validate"] = module
    spec.loader.exec_module(module)
    return module


def read_task_list() -> list[str]:
    if not TASK_LIST.is_file():
        return []
    lines = [line.strip() for line in TASK_LIST.read_text(encoding="utf-8").splitlines()]
    return [line for line in lines if line and not line.startswith("#")]


def walk(validator, file: str, checks: list[dict]) -> None:
    path = CONFIG / Path(*PureWindowsPath(file).parts)
    document = yaml.load(path.read_text(encoding="utf-8"), Loader=validator.PlaybookLoader)
    source = path.name

    for action in document.get("actions", []):
        body = action.body if isinstance(action.body, dict) else {}
        where = f"{source}:{action.line}"
        condition = {
            "option": body.get("option"),
            "builds": body.get("builds"),
        }
        operation = str(body.get("operation", "")).lower()

        if action.tag == "task":
            walk(validator, body["path"], checks)
        elif action.tag == "registryValue":
            check = {"type": "registry", "path": body["path"], "value": body.get("value", ""),
                     "source": where, **condition}
            if operation == "delete":
                check["absent"] = True
            else:
                check["absent"] = False
                check["data"] = str(body.get("data", ""))
                check["regType"] = body.get("type")
            checks.append(check)
        elif action.tag == "appx" and operation in ("", "remove"):
            checks.append({"type": "appx", "name": body["name"], "source": where, **condition})
        elif action.tag == "service" and operation == "change":
            checks.append({"type": "service", "name": body["name"], "startup": body["startup"],
                           "source": where, **condition})


def build(validator) -> str:
    report = validator.Report()
    _, version = validator.validate_conf(report)

    checks: list[dict] = []
    walk(validator, "main.yml", checks)
    for task in read_task_list():
        checks.append({"type": "task", "path": task, "source": "scheduled-tasks.txt",
                       "option": None, "builds": None})

    state = {"schema": 1, "version": version, "checks": checks}
    return json.dumps(state, indent=1, ensure_ascii=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Membuat expected-state.json dari YAML playbook.")
    parser.add_argument("--check", action="store_true", help="hanya periksa apakah file masih sesuai")
    args = parser.parse_args()

    content = build(load_validator())
    relative = OUTPUT.relative_to(ROOT).as_posix()

    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.is_file() else ""
        if current.replace("\r\n", "\n") != content:
            print(f"{relative} usang. Jalankan: python tools/make-expected-state.py")
            return 1
        print(f"{relative} sesuai dengan playbook")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(content, encoding="utf-8", newline="\n")
    print(f"Dibuat: {relative} ({content.count(chr(34) + 'type' + chr(34))} pemeriksaan)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
