"""Allow running as: python -m ttfa_harness.cli"""

import sys

from .cli import main

sys.exit(main())
