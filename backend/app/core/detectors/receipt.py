"""Receipt detector - Phase 4 strengthened implementation.

Detects proof of purchase transactions with strengthened requirements.
Based on lines 977-1036 of the classification strategy.
"""

import logging
import re

logger = logging.getLogger(__name__)


def count_amounts(text: str) -> int:
    """Count dollar amount occurrences in text.

    Args:
        text: Text to search

    Returns:
        Number of dollar amounts found
    """
    # Match $X.XX, $X, $ X.XX patterns
    pattern = r"\$\s*\d+(?:\.\d{2})?"
    matches = re.findall(pattern, text)
    return len(matches)


def is_receipt(text: str, field_keys: list[str], is_promotional: bool) -> tuple[bool, dict]:
    """Detect receipt with strengthened transaction structure requirements.

    CRITICAL: If promotional, cannot be receipt (prevents WA529 problem).
    Requires evidence of completed transaction: ID + payment method.

    Args:
        text: Lowercased haystack text
        field_keys: Extracted field keys
        is_promotional: Whether promotional signals detected

    Returns:
        Tuple of (is_receipt, details_dict)
    """
    # ANTI-PATTERN: If promotional, cannot be receipt
    if is_promotional:
        logger.debug("Receipt rejected: promotional content detected")
        return False, {"rejected_reason": "promotional"}

    # STRONG TRANSACTION INDICATORS

    # Transaction identifiers
    transaction_patterns = [
        "receipt #",
        "receipt number",
        "transaction #",
        "order #",
        "order number",
        "confirmation #",
    ]
    has_transaction_id = any(pattern in text for pattern in transaction_patterns)

    # Payment methods
    card_types = ["visa", "mastercard", "amex", "discover"]
    payment_indicators = ["auth code", "approval", "paid with"]
    has_card_payment = any(card in text for card in card_types) or any(
        indicator in text for indicator in payment_indicators
    )

    cash_indicators = ["cash", "change:", "tendered", "amount paid"]
    has_cash_payment = any(indicator in text for indicator in cash_indicators)

    has_payment_method = has_card_payment or has_cash_payment

    # Merchant context
    merchant_indicators = ["store #", "cashier", "terminal", "server:", "table:"]
    has_merchant_context = any(indicator in text for indicator in merchant_indicators)

    # CLASSIFICATION RULES (tiered by confidence)

    # Rule 1: STRONG - Transaction ID + Payment Method
    if has_transaction_id and has_payment_method:
        logger.debug("Receipt match: transaction ID + payment method (strong)")
        return True, {
            "rule": "strong_transaction",
            "has_transaction_id": True,
            "has_payment_method": True,
        }

    # Rule 2: MEDIUM - Merchant context + Payment Method
    if has_merchant_context and has_payment_method:
        logger.debug("Receipt match: merchant context + payment method (medium)")
        return True, {
            "rule": "merchant_payment",
            "has_merchant_context": True,
            "has_payment_method": True,
        }

    # Rule 3: WEAK - Requires multiple signals
    receipt_keywords = ["receipt", "thank you for shopping"]
    has_receipt_word = any(keyword in text for keyword in receipt_keywords)

    payment_complete_words = ["tendered", "change:", "change due"]
    has_payment_complete = any(word in text for word in payment_complete_words)

    has_multiple_amounts = count_amounts(text) >= 3

    if has_receipt_word and has_payment_complete and has_multiple_amounts:
        logger.debug("Receipt match: receipt word + payment complete + amounts (weak)")
        return True, {
            "rule": "weak_combined",
            "has_receipt_word": True,
            "has_payment_complete": True,
            "amount_count": count_amounts(text),
        }

    # Default: Not confident it's a receipt
    logger.debug("Receipt not detected: insufficient signals")
    return False, {
        "has_transaction_id": has_transaction_id,
        "has_payment_method": has_payment_method,
        "has_merchant_context": has_merchant_context,
    }
