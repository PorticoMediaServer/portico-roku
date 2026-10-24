#!/usr/bin/env python3
"""Choose actual compiled Roku tests; full tests/package run once nightly."""
import os
from pathlib import Path
import subprocess
base = os.environ.get('CI_BASE', '')
if not base or set(base) == {'0'}:
    base = 'HEAD^'
paths = subprocess.check_output(['git','diff','--name-only',base,'HEAD','--'],text=True).splitlines()
filters = {'HostedPersistence','ViewerBinding','Session','DirectSignIn','Transport','TVSignIn','IdentityRecovery'}
for path in paths:
    file = Path(path)
    if file.suffix in {'.bs','.brs','.xml'}:
        filters.add(file.stem.removesuffix('.test'))
subprocess.run(['node','scripts/test.mjs',','.join(sorted(filters))],check=True)
