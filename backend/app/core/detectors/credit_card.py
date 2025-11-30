"""Credit card detector - Phase 5 strengthened implementation.

Detects physical payment cards with Luhn validation and context requirements.
Based on lines 1079-1092 of the classification strategy.
"""

import logging
import re

logger = logging.getLogger(__name__)


def luhn_check(card_number: str) -> bool:
    """Validate credit card number using Luhn algorithm.

    Args:
        card_number: Card number string (digits only)

    Returns:
        True if valid according to Luhn algorithm
    """
    # Remove any spaces or dashes
    digits = re.sub(r"\D", "", card_number)

    if not digits or len(digits) < 13 or len(digits) > 19:
        return False

    # Luhn algorithm
    total = 0
    reverse_digits = digits[::-1]

    for i, digit in enumerate(reverse_digits):
        n = int(digit)
        if i % 2 == 1:  # Every second digit
            n *= 2
            if n > 9:
                n -= 9
        total += n

    return total % 10 == 0


def extract_card_numbers(text: str) -> list[str]:
    """Extract potential card numbers from text.

    Args:
        text: Text to search

    Returns:
        List of potential card numbers (13-19 digits)
    """
    # Match 13-19 digit sequences (with optional spaces/dashes)
    pattern = r"\b\d{4}[\s\-]?\d{4}[\s\-]?\d{4}[\s\-]?\d{3,7}\b"
    matches = re.findall(pattern, text)

    # Also try continuous digit sequences
    pattern2 = r"\b\d{13,19}\b"
    matches.extend(re.findall(pattern2, text))

    return matches


def is_credit_card(
    text: str, field_values: list[str], field_keys: list[str]
) -> tuple[bool, dict]:
    """Detect credit/debit cards with strengthened context requirements.

    Requires Luhn-valid PAN + strong context (issuer OR expiry OR card field).
    Explicitly excludes gift cards and membership cards.

    Args:
        text: Lowercased haystack text
        field_values: Extracted field values
        field_keys: Extracted field keys

    Returns:
        Tuple of (is_credit_card, details_dict)
    """
    # Exclude non-payment cards
    non_payment_card_terms = ["gift card", "member card", "membership card", "loyalty card"]
    is_non_payment_card = any(term in text for term in non_payment_card_terms)

    # Issuer names (strong signal)
    issuer_names = [
        "visa",
        "mastercard",
        "amex",
        "american express",
        "discover",
        "maestro",
        "jcb",
    ]
    has_issuer_name = any(issuer in text for issuer in issuer_names)

    # If it's a non-payment card without issuer name, reject
    if is_non_payment_card and not has_issuer_name:
        logger.debug("Credit card rejected: non-payment card without issuer")
        return False, {"rejected_reason": "non_payment_card"}

    # Check for Luhn-valid PAN in text
    has_valid_pan = False
    card_numbers = extract_card_numbers(text)
    for number in card_numbers:
        if luhn_check(number):
            has_valid_pan = True
            break

    # Check for expiry pattern (MM/YY or MM/YYYY)
    expiry_pattern = r"\b(0[1-9]|1[0-2])/(\d{2}|\d{4})\b"
    has_expiry = bool(re.search(expiry_pattern, text))

    # Check for card-specific field keys
    # More specific: "card number", "card pan", "credit card", not just "card"
    has_card_field = any(
        ("card" in key and ("number" in key or "pan" in key))
        or "credit" in key
        or "debit" in key
        for key in field_keys
    )

    # Card type keywords
    card_type_keywords = ["credit card", "debit card", "valid thru", "expires"]
    has_card_keyword = any(keyword in text for keyword in card_type_keywords)

    # Require strong context (not just Luhn valid)
    has_strong_context = has_issuer_name or has_expiry or has_card_field or has_card_keyword

    is_card = has_valid_pan and has_strong_context

    details = {
        "has_valid_pan": has_valid_pan,
        "has_issuer_name": has_issuer_name,
        "has_expiry": has_expiry,
        "has_card_field": has_card_field,
        "has_card_keyword": has_card_keyword,
        "is_non_payment_card": is_non_payment_card,
    }

    if is_card:
        logger.debug("Credit card detected: Luhn valid + strong context")

    return is_card, details
