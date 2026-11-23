from pathlib import Path
import hashlib
import json
from zipfile import ZIP_DEFLATED, ZipFile

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
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
output = root / "dist" / f"{name}-{tag}.zip"
output.parent.mkdir(exist_ok=True)
with ZipFile(output, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted((*program, "Setup.cmd", "setup.ps1", manifest_path.name)):
        archive.write(root / path, f"{name}/{path}")
print(output)
