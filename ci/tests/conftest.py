import sys
from pathlib import Path

# Make `ci/` importable as a flat module directory (ci/db_plan.py -> `import db_plan`).
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
