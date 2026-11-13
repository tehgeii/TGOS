#!/usr/bin/env python3
"""Validasi sumber playbook TGOS sebelum dikemas menjadi .apbx.

Playbook hanya bisa dijalankan AME Wizard di Windows, jadi salah ketik baru ketahuan
di tengah instalasi. Skrip ini menangkap kesalahan itu lebih awal dengan mencocokkan
src/ terhadap format yang dibaca AME Wizard (diturunkan dari source code
Ameliorated-LLC/trusted-uninstaller-cli) ditambah aturan proyek TGOS.

Pemakaian:
    python tools/validate.py                 # validasi, kode keluar 1 bila ada error
    python tools/validate.py --print-version # cetak versi dari playbook.conf saja

Butuh: Python 3.8+ dan PyYAML (pip install pyyaml).
"""
from __future__ import annotations

import argparse
import fnmatch
import re
import sys
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path, PureWindowsPath

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML belum terpasang. Jalankan: pip install pyyaml")

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

MIN_BUILD = 22621  # Windows 11 22H2

# --------------------------------------------------------------------------- #
# Format AME Wizard
# --------------------------------------------------------------------------- #

CONF_ELEMENTS = {
    "Name", "Username", "Title", "ShortDescription", "Description", "Details",
    "ProgressText", "Version", "SupportedBuilds", "UpgradableFrom", "Requirements",
    "UniqueId", "InstallGuide", "Overhaul", "UseKernelDriver",
    "AllowUnsupportedUpgrades", "ProductCode", "EstimatedMinutes", "Git", "Website",
    "DonateLink", "SupportsISO", "OOBE", "ISO", "FeaturePages", "Software",
    "PasswordReplace",
}
CONF_REQUIRED = [
    "Name", "Username", "Title", "ShortDescription", "Description", "Details",
    "Version", "UniqueId",
]
REQUIREMENTS = {
    "Internet", "NoInternet", "DefenderDisabled", "DefenderToggled",
    "NoPendingUpdates", "Activation", "NoAntivirus", "LocalAccounts", "PasswordSet",
    "AdministratorPasswordSet", "PluggedIn", "NoTweakware", "FreshInstall",
    "UCPDDisabled",
}
FEATURE_PAGES = {"RadioPage", "CheckboxPage", "RadioImagePage"}
OPTION_TAGS = {"RadioPage": "RadioOption", "CheckboxPage": "CheckboxOption",
               "RadioImagePage": "RadioImageOption"}
PAGE_ATTRIBUTES = {"Description", "IsRequired", "DependsOn", "WindowsVersion",
                   "DefaultOption", "CheckDefaultBrowser"}
OPTION_ATTRIBUTES = {"IsChecked", "IsEnabled", "DependsOn", "WindowsVersion", "None"}
BOOL_ATTRIBUTES = {"IsRequired", "IsChecked", "IsEnabled", "CheckDefaultBrowser", "None"}
MAX_PAGE_OPTIONS = 4  # batas AME Wizard; turun jadi 3 atau 2 bila ada TopLine/BottomLine
INVALID_NAME_CHARS = set('\\/:*?"<>|')

ROOT_KEYS = {
    "title", "description", "actions", "iso", "oobe", "priority", "privilege",
    "option", "options", "builds", "cpuArch", "onUpgrade", "onUpgradeVersions",
    "previousOption", "features", "tasks",
}
COMMON_KEYS = {
    "iso", "oobe", "ignoreErrors", "option", "status", "options", "builds",
    "cpuArch", "onUpgrade", "onUpgradeVersions", "previousOption", "errorAction",
    "allowRetries",
}
_SHELL_KEYS = {"runas", "command", "timeout", "wait", "exeDir", "handleExitCodes", "weight"}
ACTIONS = {
    "task": {"path"},
    "writeStatus": {"status"},
    "status": {"status"},
    "registryValue": {"path", "value", "data", "type", "scope", "operation", "weight"},
    "registryKey": {"path", "scope", "operation", "weight"},
    "service": {"operation", "name", "startup", "deleteStop", "deleteUsingRegistry",
                "device", "weight"},
    "appx": {"name", "type", "operation", "verboseOutput", "unregister", "weight"},
    "run": {"runas", "path", "exe", "args", "baseDir", "exeDir", "createWindow",
            "hideWindow", "showOutput", "showError", "timeout", "wait",
            "handleExitCodes", "weight"},
    "cmd": _SHELL_KEYS,
    "powerShell": _SHELL_KEYS,
    "scheduledTask": {"operation", "data", "path", "weight"},
    "file": {"path", "prioritizeExe", "weight", "useNSudoTI"},
    "taskKill": {"name", "pathContains", "weight"},
    "systemPackage": {"name", "arch", "language", "regexExcludeFiles",
                      "excludeDependents", "weight"},
}
# Dikenal AME Wizard tetapi belum dimodelkan di sini. Tambahkan skemanya dulu
# sebelum dipakai di TGOS.
UNMODELED_ACTIONS = {"software", "download"}

REQUIRED_KEYS = {
    "task": ["path"],
    "writeStatus": ["status"],
    "status": ["status"],
    "registryValue": ["path"],
    "registryKey": ["path"],
    "service": ["name"],
    "appx": ["name"],
    "run": ["exe"],
    "cmd": ["command"],
    "powerShell": ["command"],
    "scheduledTask": ["path"],
    "file": ["path"],
    "systemPackage": ["name"],
}

RUNAS = {"trustedinstaller", "system", "currentuser", "currentuserelevated",
         "currentusertrustedinstaller"}
EXIT_CODE_ACTIONS = {"log", "retry", "error", "retryerror", "halt"}
ERROR_ACTIONS = {"ignore", "log", "notify", "halt"}
SCOPES = {"allusers", "currentuser", "activeusers", "defaultuser"}
REG_TYPES = {"REG_SZ", "REG_MULTI_SZ", "REG_EXPAND_SZ", "REG_DWORD", "REG_QWORD",
             "REG_BINARY", "REG_NONE", "REG_UNKNOWN"}
OPERATIONS = {
    "registryValue": {"add", "set", "delete"},
    "registryKey": {"add", "delete"},
    "service": {"stop", "continue", "start", "pause", "delete", "change"},
    "appx": {"remove", "clearcache"},
    "scheduledTask": {"delete", "enable", "disable", "deletefolder"},
}
APPX_TYPES = {"family", "package", "app"}
REG_ROOTS = ("HKLM\\", "HKCU\\", "HKU\\", "HKCR\\", "HKEY_LOCAL_MACHINE\\",
             "HKEY_CURRENT_USER\\", "HKEY_USERS\\", "HKEY_CLASSES_ROOT\\")

# Paket AppX yang tidak boleh terhapus. Validasi gagal bila pola nama pada aksi
# !appx hapus cocok dengan salah satu nama keluarga paket ini. Daftar ini juga dipakai
# tools/compare-snapshots.py untuk mendeteksi paket penting yang hilang setelah instalasi.
PROTECTED_APPX = [
    # Store, pemasang aplikasi, dan pustaka yang dipakai hampir semua aplikasi
    "Microsoft.WindowsStore", "Microsoft.StorePurchaseApp", "Microsoft.DesktopAppInstaller",
    "Microsoft.VCLibs.140.00", "Microsoft.VCLibs.140.00.UWPDesktop",
    "Microsoft.NET.Native.Framework.2.2", "Microsoft.NET.Native.Runtime.2.2",
    "Microsoft.UI.Xaml.2.8", "Microsoft.UI.Xaml.CBS", "Microsoft.WindowsAppRuntime.1.5",
    "Microsoft.Services.Store.Engagement",
    # Komponen shell dan sistem
    "MicrosoftWindows.Client.CBS", "MicrosoftWindows.Client.Core",
    "Microsoft.Windows.ShellExperienceHost", "Microsoft.Windows.StartMenuExperienceHost",
    "Microsoft.Windows.Search", "Microsoft.Windows.CloudExperienceHost",
    "Microsoft.Windows.ContentDeliveryManager", "Microsoft.AAD.BrokerPlugin",
    "Microsoft.AccountsControl", "Microsoft.LockApp", "Microsoft.Win32WebViewHost",
    "Microsoft.SecHealthUI", "windows.immersivecontrolpanel",
    "Microsoft.ApplicationCompatibilityEnhancements",
    # Aplikasi yang sengaja dipertahankan
    "Microsoft.WindowsNotepad", "Microsoft.Paint", "Microsoft.Windows.Photos",
    "Microsoft.WindowsCalculator", "Microsoft.ScreenSketch", "Microsoft.WindowsTerminal",
    "Microsoft.WindowsCamera", "Microsoft.ZuneMusic",
    # Codec
    "Microsoft.HEIFImageExtension", "Microsoft.HEVCVideoExtension",
    "Microsoft.VP9VideoExtensions", "Microsoft.WebpImageExtension",
    "Microsoft.AV1VideoExtension", "Microsoft.RawImageExtension",
    "Microsoft.WebMediaExtensions", "Microsoft.MPEG2VideoExtension",
    "Microsoft.AVCEncoderVideoExtension",
    # Dibutuhkan game dari Microsoft Store / PC Game Pass
    "Microsoft.XboxIdentityProvider", "Microsoft.GamingServices",
    # Browser: baru disentuh di Fase 4 lewat opsi tersendiri
    "Microsoft.MicrosoftEdge.Stable", "Microsoft.MicrosoftEdgeDevToolsClient",
]
# Akhiran contoh untuk menguji pola terhadap nama keluarga paket (nama_idpenerbit).
_FAMILY_SUFFIX = "_8wekyb3d8bbwe"
MIN_APPX_PREFIX = 8  # panjang minimum awalan nama sebelum wildcard

# Aturan TGOS: aksi yang default-nya menghapus harus menulis `operation` eksplisit.
EXPLICIT_OPERATION = {"service", "scheduledTask", "registryKey"}

SCRIPT_REF = re.compile(r'-File\s+"?\.\\([^"\s]+)"?', re.IGNORECASE)
VERSION_RE = re.compile(r"^\d+(\.\d+){0,2}( .*)?$")
BUILD_FILTER_RE = re.compile(r"^!?(>=|<=|>|<)?\d+(\.\d+)?$")
ASCII_ONLY_SUFFIXES = {".ps1", ".psm1", ".cmd", ".bat"}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ICON_SIZE = 256  # sama dengan ikon playbook AtlasOS


# --------------------------------------------------------------------------- #
# Pengumpul hasil
# --------------------------------------------------------------------------- #

class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []
        # (path, value, filter) -> lokasi pertama; untuk mendeteksi nilai registry kembar
        self.registry_seen: dict[tuple, str] = {}

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def rel(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


# --------------------------------------------------------------------------- #
# playbook.conf
# --------------------------------------------------------------------------- #

def text_of(root: ET.Element, tag: str) -> str | None:
    node = root.find(tag)
    if node is None or node.text is None:
        return None
    return node.text.strip()


def validate_conf(report: Report) -> tuple[set[str], str | None]:
    """Mengembalikan (nama semua opsi, versi)."""
    path = SRC / "playbook.conf"
    where = rel(path)
    options: set[str] = set()

    if not path.is_file():
        report.error(where, "file tidak ditemukan")
        return options, None

    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as exc:
        report.error(where, f"XML tidak valid: {exc}")
        return options, None

    if root.tag != "Playbook":
        report.error(where, f"elemen akar harus <Playbook>, bukan <{root.tag}>")
        return options, None

    seen: set[str] = set()
    for child in root:
        if child.tag not in CONF_ELEMENTS:
            report.error(where, f"elemen <{child.tag}> tidak dikenal AME Wizard")
        if child.tag in seen:
            report.error(where, f"elemen <{child.tag}> ditulis lebih dari sekali")
        seen.add(child.tag)

    for tag in CONF_REQUIRED:
        if not text_of(root, tag):
            report.error(where, f"<{tag}> wajib diisi")

    name = text_of(root, "Name") or ""
    if any(ch in INVALID_NAME_CHARS for ch in name):
        report.error(where, "<Name> mengandung karakter yang tidak boleh ada di nama file")
    if len(name) > 12:
        report.warn(where, "<Name> lebih dari 12 karakter; Wizard menolak nama yang terlalu lebar")

    version = text_of(root, "Version")
    if version and not VERSION_RE.match(version):
        report.error(where, f"<Version> '{version}' harus berformat 1, 1.0, atau 1.0.0")

    title = text_of(root, "Title") or ""
    if version and version not in title:
        report.error(where, f"<Title> '{title}' tidak memuat versi '{version}'")

    unique_id = text_of(root, "UniqueId")
    if unique_id:
        try:
            if uuid.UUID(unique_id).int == 0:
                report.error(where, "<UniqueId> tidak boleh UUID kosong")
        except ValueError:
            report.error(where, f"<UniqueId> '{unique_id}' bukan UUID yang valid")

    builds_node = root.find("SupportedBuilds")
    if builds_node is None or not list(builds_node):
        report.error(where, "<SupportedBuilds> wajib berisi minimal satu build")
    else:
        seen_builds: set[str] = set()
        for item in builds_node:
            value = (item.text or "").strip()
            if item.tag != "string":
                report.error(where, f"<SupportedBuilds> hanya boleh berisi <string>, bukan <{item.tag}>")
            elif not value.isdigit():
                report.error(where, f"build '{value}' bukan bilangan bulat")
            elif int(value) < MIN_BUILD:
                report.error(where, f"build {value} lebih lama dari batas TGOS ({MIN_BUILD})")
            elif value in seen_builds:
                report.error(where, f"build {value} ditulis lebih dari sekali")
            seen_builds.add(value)

    requirements_node = root.find("Requirements")
    if requirements_node is not None:
        for item in requirements_node:
            value = (item.text or "").strip()
            if item.tag != "Requirement":
                report.error(where, f"<Requirements> hanya boleh berisi <Requirement>, bukan <{item.tag}>")
            elif value not in REQUIREMENTS:
                report.error(where, f"requirement '{value}' tidak dikenal AME Wizard")

    for tag in ("Overhaul", "UseKernelDriver", "AllowUnsupportedUpgrades", "SupportsISO"):
        value = text_of(root, tag)
        if value is not None and value not in ("true", "false"):
            report.error(where, f"<{tag}> harus 'true' atau 'false', bukan '{value}'")

    minutes = text_of(root, "EstimatedMinutes")
    if minutes is not None and not minutes.isdigit():
        report.error(where, f"<EstimatedMinutes> '{minutes}' bukan bilangan bulat")

    pages_node = root.find("FeaturePages")
    pages = list(pages_node) if pages_node is not None else []
    for page in pages:
        if page.tag not in FEATURE_PAGES:
            report.error(where, f"jenis halaman <{page.tag}> tidak dikenal AME Wizard")
            continue
        for attribute, value in page.attrib.items():
            if attribute not in PAGE_ATTRIBUTES:
                report.error(where, f"<{page.tag}>: atribut '{attribute}' tidak dikenal")
            elif attribute in BOOL_ATTRIBUTES and value not in ("true", "false"):
                report.error(where, f"<{page.tag}>: {attribute} harus 'true' atau 'false', bukan '{value}'")
        if page.tag == "CheckboxPage" and page.get("DefaultOption") is not None:
            report.error(where, "<CheckboxPage> tidak punya DefaultOption; pakai IsChecked pada opsinya")
        for child in page:
            if child.tag not in ("Options", "TopLine", "BottomLine"):
                report.error(where, f"<{page.tag}>: elemen <{child.tag}> tidak dikenal")

        page_options: list[str] = []
        options_node = page.find("Options")
        option_nodes = list(options_node) if options_node is not None else []
        lines = sum(1 for tag in ("TopLine", "BottomLine") if page.find(tag) is not None)
        limit = MAX_PAGE_OPTIONS - lines
        if page.tag != "RadioImagePage" and len(option_nodes) > limit:
            report.error(where, f"<{page.tag}> punya {len(option_nodes)} opsi; batas Wizard {limit} "
                                f"dengan {lines} baris TopLine/BottomLine")
        elif len(option_nodes) > MAX_PAGE_OPTIONS:
            report.error(where, f"<{page.tag}> punya {len(option_nodes)} opsi; batas Wizard {MAX_PAGE_OPTIONS}")
        for option in option_nodes:
            if option.tag != OPTION_TAGS[page.tag]:
                report.error(where, f"<{page.tag}> hanya boleh berisi <{OPTION_TAGS[page.tag]}>, bukan <{option.tag}>")
            for attribute, value in option.attrib.items():
                if attribute not in OPTION_ATTRIBUTES:
                    report.error(where, f"<{option.tag}>: atribut '{attribute}' tidak dikenal")
                elif attribute in BOOL_ATTRIBUTES and value not in ("true", "false"):
                    report.error(where, f"<{option.tag}>: {attribute} harus 'true' atau 'false', bukan '{value}'")
            option_name = text_of(option, "Name")
            if not option_name:
                report.error(where, f"<{option.tag}> tanpa <Name>")
                continue
            if not text_of(option, "Text"):
                report.error(where, f"opsi '{option_name}' tanpa <Text>")
            if not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*$", option_name):
                report.error(where, f"nama opsi '{option_name}' harus huruf kecil dipisah tanda hubung")
            if option_name in options:
                report.error(where, f"nama opsi '{option_name}' dipakai lebih dari sekali")
            options.add(option_name)
            page_options.append(option_name)
        if not page_options:
            report.error(where, f"<{page.tag}> tidak punya opsi")
        default = page.get("DefaultOption")
        if default is not None and default not in page_options:
            report.error(where, f"DefaultOption '{default}' tidak ada di halamannya")
        if page.tag != "CheckboxPage" and default is None:
            report.warn(where, f"<{page.tag}> tanpa DefaultOption")

    for page in pages:
        depends = page.get("DependsOn")
        if depends is not None and depends.lstrip("!") not in options:
            report.error(where, f"DependsOn '{depends}' merujuk opsi yang tidak ada")

    return options, version


# --------------------------------------------------------------------------- #
# YAML
# --------------------------------------------------------------------------- #

class Action:
    def __init__(self, tag: str, body: object, line: int) -> None:
        self.tag = tag
        self.body = body
        self.line = line


class PlaybookLoader(yaml.SafeLoader):
    """SafeLoader yang menolak kunci ganda dan menangkap tag aksi AME."""

    def construct_mapping(self, node, deep=False):  # type: ignore[override]
        seen: set[str] = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=True)
            if key in seen:
                raise yaml.constructor.ConstructorError(
                    None, None, f"kunci '{key}' ditulis lebih dari sekali", key_node.start_mark)
            seen.add(key)
        return super().construct_mapping(node, deep=deep)


def _construct_action(loader: PlaybookLoader, suffix: str, node: yaml.Node) -> Action:
    line = node.start_mark.line + 1
    if isinstance(node, yaml.MappingNode):
        body: object = loader.construct_mapping(node, deep=True)
    elif isinstance(node, yaml.ScalarNode) and node.value == "":
        body = {}
    else:
        body = None
    return Action(suffix.rstrip(":"), body, line)


PlaybookLoader.add_multi_constructor("!", _construct_action)


def check_option_ref(report: Report, where: str, ref: object, options: set[str]) -> None:
    if not isinstance(ref, str) or not ref:
        report.error(where, f"nilai opsi harus teks, bukan {ref!r}")
        return
    if "&" in ref and "!" in ref:
        report.error(where, f"opsi '{ref}' tidak boleh memakai & dan ! sekaligus")
        return
    for part in ref.split("&"):
        name = part.lstrip("!")
        if name not in options:
            report.error(where, f"opsi '{name}' tidak ada di playbook.conf")


def check_enum(report: Report, where: str, key: str, value: object, allowed: set[str]) -> None:
    if not isinstance(value, str) or value.lower() not in allowed:
        report.error(where, f"{key}: '{value}' tidak valid (pilihan: {', '.join(sorted(allowed))})")


def validate_action(report: Report, where: str, action: Action, options: set[str]) -> None:
    tag, body = action.tag, action.body

    if tag in UNMODELED_ACTIONS:
        report.error(where, f"!{tag}: belum dimodelkan di tools/validate.py; tambahkan skemanya dulu")
        return
    if tag not in ACTIONS:
        report.error(where, f"!{tag}: aksi tidak dikenal AME Wizard")
        return
    if not isinstance(body, dict):
        report.error(where, f"!{tag}: isi aksi harus berupa pemetaan kunci-nilai")
        return

    allowed = ACTIONS[tag] | COMMON_KEYS
    for key in body:
        if key not in allowed:
            report.error(where, f"!{tag}: properti '{key}' tidak dikenal")
    for key in REQUIRED_KEYS.get(tag, []):
        if body.get(key) in (None, ""):
            report.error(where, f"!{tag}: properti '{key}' wajib diisi")

    if tag == "taskKill" and not (body.get("name") or body.get("pathContains")):
        report.error(where, "!taskKill: butuh 'name' atau 'pathContains'")

    # Filter umum
    if "option" in body:
        check_option_ref(report, where, body["option"], options)
    if "options" in body:
        if not isinstance(body["options"], list) or not body["options"]:
            report.error(where, "options: harus berupa daftar yang tidak kosong")
        else:
            for ref in body["options"]:
                check_option_ref(report, where, ref, options)
    if "builds" in body:
        if not isinstance(body["builds"], list) or not body["builds"]:
            report.error(where, "builds: harus berupa daftar yang tidak kosong")
        else:
            for build in body["builds"]:
                if not isinstance(build, str) or not BUILD_FILTER_RE.match(build):
                    report.error(where, f"builds: '{build}' harus teks seperti '>=26100'")
                elif "." in build:
                    report.warn(where, f"builds: '{build}' dibandingkan sebagai desimal oleh Wizard; "
                                       "pakai nomor build utama saja")
    if "errorAction" in body:
        check_enum(report, where, "errorAction", body["errorAction"], ERROR_ACTIONS)

    # Per aksi
    if "runas" in body:
        check_enum(report, where, "runas", body["runas"], RUNAS)
    if "handleExitCodes" in body:
        codes = body["handleExitCodes"]
        if not isinstance(codes, dict) or not codes:
            report.error(where, "handleExitCodes: harus berupa pemetaan yang tidak kosong")
        else:
            for code, outcome in codes.items():
                if not isinstance(code, str) or not re.match(r"^!?-?\d+$", code):
                    report.error(where, f"handleExitCodes: kunci {code!r} harus teks dalam tanda kutip, mis. \"!0\"")
                check_enum(report, where, "handleExitCodes", outcome, EXIT_CODE_ACTIONS)
    if "scope" in body:
        check_enum(report, where, "scope", body["scope"], SCOPES)

    operation = body.get("operation")
    if tag in OPERATIONS and operation is not None:
        check_enum(report, where, "operation", operation, OPERATIONS[tag])
    if tag in EXPLICIT_OPERATION and operation is None:
        report.error(where, f"!{tag}: 'operation' wajib ditulis eksplisit (default AME adalah menghapus)")

    if tag in ("registryValue", "registryKey"):
        reg_path = body.get("path")
        if isinstance(reg_path, str) and not reg_path.upper().startswith(REG_ROOTS):
            report.error(where, f"!{tag}: path '{reg_path}' harus diawali HKLM\\, HKCU\\, HKU\\, atau HKCR\\")

    if tag == "registryValue":
        op = operation.lower() if isinstance(operation, str) else "add"
        if op != "delete":
            if "type" not in body:
                report.error(where, "!registryValue: 'type' wajib untuk operasi add/set")
            if "data" not in body:
                report.error(where, "!registryValue: 'data' wajib untuk operasi add/set")
        if "type" in body and body["type"] not in REG_TYPES:
            report.error(where, f"!registryValue: type '{body['type']}' tidak valid")
        if body.get("type") in ("REG_DWORD", "REG_QWORD") and "data" in body:
            # AME memakai Convert.ToUInt32/ToUInt64, yang hanya menerima desimal.
            data = str(body["data"])
            limit = 0xFFFFFFFF if body["type"] == "REG_DWORD" else 0xFFFFFFFFFFFFFFFF
            if not re.match(r"^\d+$", data):
                report.error(where, f"!registryValue: data '{data}' harus angka desimal untuk "
                                    f"{body['type']} (AME tidak menerima notasi 0x)")
            elif int(data) > limit:
                report.error(where, f"!registryValue: data {data} melebihi batas {body['type']}")
        if isinstance(body.get("path"), str) and isinstance(body.get("value"), str):
            key = (body["path"].lower(), body["value"].lower(), str(body.get("option")),
                   str(body.get("options")), str(body.get("builds")))
            first = report.registry_seen.get(key)
            if first:
                report.error(where, f"!registryValue: '{body['value']}' di '{body['path']}' sudah "
                                    f"ditulis di {first} dengan filter yang sama")
            else:
                report.registry_seen[key] = where

    if tag == "service" and isinstance(operation, str) and operation.lower() == "change":
        if body.get("startup") not in (0, 1, 2, 3, 4):
            report.error(where, "!service: operasi change butuh 'startup' bernilai 0 sampai 4")

    if tag == "appx" and "type" in body:
        check_enum(report, where, "type", body["type"], APPX_TYPES)

    if tag == "appx" and isinstance(body.get("name"), str):
        name = body["name"]
        removing = not (isinstance(operation, str) and operation.lower() == "clearcache")
        if removing:
            if name.startswith("*"):
                report.error(where, f"!appx: nama '{name}' tidak boleh diawali wildcard untuk "
                                    "penghapusan; tulis awalan nama paket lalu '*'")
            elif len(name.rstrip("*")) < MIN_APPX_PREFIX:
                report.error(where, f"!appx: nama '{name}' terlalu pendek; awalan minimal "
                                    f"{MIN_APPX_PREFIX} karakter supaya tidak mengenai paket lain")
            elif "*" in name.rstrip("*"):
                report.error(where, f"!appx: nama '{name}' hanya boleh memakai wildcard di akhir")
            for protected in PROTECTED_APPX:
                family = (protected + _FAMILY_SUFFIX).lower()
                if fnmatch.fnmatchcase(family, name.lower()):
                    report.error(where, f"!appx: nama '{name}' akan menghapus paket yang "
                                        f"dilindungi '{protected}'")

    if tag == "run" and body.get("exeDir") is True and isinstance(body.get("args"), str):
        for match in SCRIPT_REF.finditer(body["args"]):
            target = SRC / "Executables" / Path(*PureWindowsPath(match.group(1)).parts)
            if not target.is_file():
                report.error(where, f"!run: skrip '{match.group(1)}' tidak ada di src/Executables")


def validate_yaml(report: Report, options: set[str]) -> None:
    config = SRC / "Configuration"
    if not config.is_dir():
        report.error(rel(config), "folder tidak ditemukan")
        return

    entry = config / "main.yml"
    if not entry.is_file():
        report.error(rel(entry), "titik masuk playbook tidak ditemukan")
        return
    if (config / "custom.yml").exists():
        report.warn(rel(config / "custom.yml"), "diabaikan Wizard karena main.yml ada")

    visited: set[Path] = set()

    def walk(path: Path, stack: tuple[Path, ...]) -> None:
        where_file = rel(path)
        if path in stack:
            report.error(where_file, "file tugas saling memanggil (melingkar)")
            return
        if path in visited:
            report.warn(where_file, "dipanggil lebih dari sekali")
        visited.add(path)

        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            report.error(where_file, "file diawali BOM; simpan sebagai UTF-8 tanpa BOM")
        if b"\t" in raw:
            report.error(where_file, "berisi karakter tab; YAML harus memakai spasi")

        try:
            document = yaml.load(raw.decode("utf-8-sig"), Loader=PlaybookLoader)
        except (yaml.YAMLError, UnicodeDecodeError) as exc:
            report.error(where_file, f"YAML tidak valid: {exc}")
            return

        if not isinstance(document, dict):
            report.error(where_file, "isi file harus berupa pemetaan (title, description, actions)")
            return
        for key in document:
            if key not in ROOT_KEYS:
                report.error(where_file, f"kunci tingkat atas '{key}' tidak dikenal")
        if not document.get("title"):
            report.error(where_file, "'title' wajib diisi")
        actions = document.get("actions")
        if not isinstance(actions, list) or not actions:
            report.error(where_file, "'actions' wajib berupa daftar yang tidak kosong")
            return

        for index, action in enumerate(actions, start=1):
            if not isinstance(action, Action):
                report.error(f"{where_file} (aksi ke-{index})", "aksi tanpa tag, mis. '- !run:'")
                continue
            where = f"{where_file}:{action.line}"
            validate_action(report, where, action, options)
            if action.tag == "task" and isinstance(action.body, dict):
                target = action.body.get("path")
                if isinstance(target, str) and target:
                    child = config / Path(*PureWindowsPath(target).parts)
                    if not child.is_file():
                        report.error(where, f"!task: file '{target}' tidak ditemukan")
                    else:
                        walk(child, stack + (path,))

    walk(entry, ())

    for path in sorted(config.rglob("*.yml")):
        if path not in visited:
            report.warn(rel(path), "tidak dipanggil dari main.yml")


# --------------------------------------------------------------------------- #
# Executables
# --------------------------------------------------------------------------- #

def validate_executables(report: Report) -> None:
    folder = SRC / "Executables"
    if not folder.is_dir():
        report.error(rel(folder), "folder tidak ditemukan")
        return
    # Skrip di tools/ juga dijalankan Windows PowerShell 5.1 di mesin pengguna.
    candidates = sorted(folder.rglob("*")) + sorted((ROOT / "tools").glob("*.ps1"))
    for path in candidates:
        if not path.is_file() or path.suffix.lower() not in ASCII_ONLY_SUFFIXES:
            continue
        raw = path.read_bytes()
        try:
            raw.decode("ascii")
        except UnicodeDecodeError as exc:
            line = raw.count(b"\n", 0, exc.start) + 1
            report.error(f"{rel(path)}:{line}",
                         "karakter non-ASCII; Windows PowerShell 5.1 dan cmd salah membacanya")


# --------------------------------------------------------------------------- #
# Ikon
# --------------------------------------------------------------------------- #

def validate_icon(report: Report) -> None:
    path = SRC / "playbook.png"
    where = rel(path)
    if not path.is_file():
        report.error(where, "ikon playbook tidak ditemukan (buat dengan tools/make-icon.py)")
        return
    header = path.read_bytes()[:24]
    if len(header) < 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        report.error(where, "bukan file PNG yang valid")
        return
    width = int.from_bytes(header[16:20], "big")
    height = int.from_bytes(header[20:24], "big")
    if (width, height) != (ICON_SIZE, ICON_SIZE):
        report.error(where, f"ukuran {width}x{height}; harus {ICON_SIZE}x{ICON_SIZE}")


# --------------------------------------------------------------------------- #

def main() -> int:
    parser = argparse.ArgumentParser(description="Validasi sumber playbook TGOS.")
    parser.add_argument("--print-version", action="store_true",
                        help="cetak versi dari playbook.conf lalu keluar")
    args = parser.parse_args()

    report = Report()
    options, version = validate_conf(report)

    if args.print_version:
        if not version or not VERSION_RE.match(version):
            print("versi tidak bisa dibaca dari playbook.conf", file=sys.stderr)
            return 1
        print(version)
        return 0

    validate_yaml(report, options)
    validate_executables(report)
    validate_icon(report)

    for message in report.warnings:
        print(f"PERINGATAN  {message}")
    for message in report.errors:
        print(f"ERROR       {message}")

    summary = f"{len(report.errors)} error, {len(report.warnings)} peringatan"
    if report.errors:
        print(f"\nValidasi GAGAL: {summary}")
        return 1
    print(f"Validasi lolos: TGOS v{version} ({summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
