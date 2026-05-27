import subprocess, sys
from pathlib import Path
venv_dir = Path(".venv")
if not venv_dir.exists():
    subprocess.run([sys.executable, "-m", "venv", str(venv_dir)], check=True)
pip = str(venv_dir / "bin" / "pip")
req = Path("environment/requirements.txt")
if req.exists():
    subprocess.run([pip, "install", "--upgrade", "pip"], check=True)
    subprocess.run([pip, "install", "-r", str(req)], check=True)
    print("Done.")
