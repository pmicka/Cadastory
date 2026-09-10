#!/usr/bin/env python3
"""Launch Scout's livestock evidence worker with bounded source coverage."""
from __future__ import annotations

import scout_livestock_document_evidence_entrypoint as entrypoint
import scout_document_evidence_source_coverage  # noqa: F401  # installs bounded discovery patches


if __name__ == "__main__":
    entrypoint.main()
