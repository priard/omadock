"""Drive labels are chosen by whoever formatted the drive, and the eject
notification renders markup, so labels are cleaned before display."""

import re

MAX_LABEL = 64
_UNSAFE = re.compile("[\x00-\x1f\x7f-\x9f\u061c\u200b-\u200f\u202a-\u202e\u2066-\u2069<>&]")


def clean_label(name, fallback="Drive"):
    """Without markup characters, control or bidi marks; at most MAX_LABEL."""
    text = " ".join(_UNSAFE.sub(lambda m: " " if m.group() in "\n\t" else "", str(name or "")).split())
    return text[:MAX_LABEL].strip() or fallback
