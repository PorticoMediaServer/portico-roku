#!/usr/bin/env python3
"""Assemble a versioned unsigned release with exact corresponding source."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
subprocess.run(["python3", "scripts/verify-package.py"], cwd=root, check=True)
metadata = json.loads((root / "build/metadata.json").read_text())
version = metadata["version"]
tag = f"v{version}"
assert os.environ.get("GITHUB_REF", f"refs/tags/{tag}") == f"refs/tags/{tag}", "Release requires matching version tag"
assert not subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=root, text=True).strip(), "Release source must be committed and clean"
commit = metadata["commit"]
assert subprocess.check_output(["git", "rev-parse", f"{tag}^{{commit}}"], cwd=root, text=True).strip() == commit, "Release tag must target this exact commit"
output = root / "build/release"
if output.exists():
    shutil.rmtree(output)
output.mkdir()
for file in ("portico-roku.zip", "portico-roku.zip.sha256"):
    shutil.copyfile(root / "build" / file, output / file)
for file in ("LICENSE", "THIRD_PARTY_NOTICES.txt", "licenses/Manrope-OFL.txt", "licenses/Lucide-LICENSE.txt", "licenses/BrighterScript-MIT.txt"):
    shutil.copyfile(root / file, output / Path(file).name)
source_name = f"portico-roku-{version}-source.tar.gz"
subprocess.run(["git", "archive", "--format=tar.gz", f"--prefix=portico-roku-{version}/", f"--output={output / source_name}", commit], cwd=root, check=True)
metadata["tag"] = tag
metadata["source"] = {"file": source_name, "commit": commit, "sha256": hashlib.sha256((output / source_name).read_bytes()).hexdigest()}
(output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
files = sorted(output.iterdir())
(output / "SHA256SUMS").write_text("".join(f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}\n" for file in files))
print(f"Release {tag} assembled from {commit}: {len(files) + 1} assets")
