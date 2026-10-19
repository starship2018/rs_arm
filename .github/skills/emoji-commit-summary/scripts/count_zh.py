#!/usr/bin/env python3
"""Count CJK characters and visible characters in a commit summary."""

import sys
import unicodedata


def is_cjk(char: str) -> bool:
    return unicodedata.name(char, "").startswith(
        ("CJK UNIFIED IDEOGRAPH", "CJK COMPATIBILITY IDEOGRAPH")
    )


def main() -> int:
    text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else sys.stdin.read()
    cjk = sum(1 for char in text if is_cjk(char))
    visible = sum(1 for char in text if not char.isspace())
    print(f"中文字数: {cjk}")
    print(f"非空白字符: {visible}")
    return 0 if cjk <= 50 else 1


if __name__ == "__main__":
    raise SystemExit(main())
