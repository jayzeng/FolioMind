"""Letter detector - Phase 5 implementation.

Detects personal or business correspondence with promotional check.
Based on lines 1114-1123 of the classification strategy.
"""

import logging

logger = logging.getLogger(__name__)


def is_letter(text: str, is_promotional: bool) -> tuple[bool, dict]:
    """Detect letters with promotional intent check.

    If promotional signals detected, defer to promotional classification.
    Requires BOTH salutation AND closing to be confident it's a letter.

    Args:
        text: Lowercased haystack text
        is_promotional: Whether promotional signals detected

    Returns:
        Tuple of (is_letter, details_dict)
    """
    # If already promotional, don't classify as letter
    # Intent (promotional offer) takes precedence over format (letter structure)
    if is_promotional:
        logger.debug("Letter rejected: promotional content takes precedence")
        return False, {"rejected_reason": "promotional"}

    # Salutations
    salutations = [
        "dear ",
        "to whom it may concern",
        "hello ",
        "hi ",
        "greetings",
    ]
    has_salutation = any(salutation in text for salutation in salutations)

    # Closings
    closings = [
        "sincerely",
        "regards",
        "best regards",
        "best",
        "yours truly",
        "respectfully",
        "cordially",
        "warm regards",
    ]
    has_closing = any(closing in text for closing in closings)

    # Require BOTH salutation and closing
    is_letter_format = has_salutation and has_closing

    details = {
        "has_salutation": has_salutation,
        "has_closing": has_closing,
    }

    if is_letter_format:
        logger.debug("Letter detected: salutation + closing")

    return is_letter_format, details
