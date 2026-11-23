from pathlib import Path
import hashlib
import json
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

root = Path(__file__).resolve().parent.parent
tag = (root / "scarlet-version.txt").read_text().strip()
name = "ScarletDawn-Local-Builder"
program = (
    "Launcher.cs", "Play Scarlet Dawn.exe", "README.md", "RELEASE-NOTES.md",
    "ScarletLightgun.dll", "build-scarlet-lightgun-patch.py", "scarlet-aim.S",
    "scarlet-aim-patch.json", "scarlet-lightgun-patch.json", "scarlet-lightgun.c",
    "scarlet-menu.ps1", "scarlet-menu.xaml", "scarlet-reticle.h", "scarlet-settings.ps1",
    "scarlet-update.ps1", "scarlet-version.txt",
)
manifest = {
    "format": 1,
    "version": tag,
    "files": [{"path": path, "sha256": hashlib.sha256((root / path).read_bytes()).hexdigest()}
              for path in sorted(program)],
}
manifest_path = root / "package-manifest.json"
manifest_json = json.dumps(manifest, indent=2) + "\n"
if manifest_path.exists() and b"\r\n" in manifest_path.read_bytes():
    manifest_json = manifest_json.replace("\n", "\r\n")
manifest_path.write_bytes(manifest_json.encode("utf-8"))
output = root / "dist" / f"{name}-{tag}.zip"
output.parent.mkdir(exist_ok=True)
paths = sorted((*program, "Setup.cmd", "setup.ps1", manifest_path.name))
with ZipFile(output, "w") as archive:
    for path in paths:
        info = ZipInfo(f"{name}/{path}", (2026, 11, 17, 0, 0, 0))
        info.external_attr = 0o100644 << 16
        archive.writestr(info, (root / path).read_bytes(), compress_type=ZIP_DEFLATED, compresslevel=9)
with ZipFile(output) as archive:
    if archive.namelist() != [f"{name}/{path}" for path in paths] or archive.testzip() is not None:
        raise ValueError("The generated release archive failed its integrity check.")
print(output)
