"""Insurance card detector - Phase 5 strengthened implementation.

Detects health/dental/vision insurance cards with multi-signal requirements.
Based on lines 1051-1074 of the classification strategy.
"""

import logging

logger = logging.getLogger(__name__)


def is_insurance_card(text: str, field_keys: list[str]) -> tuple[bool, dict]:
    """Detect insurance cards using multi-signal analysis.

    Requires 2+ signal types OR very specific RX BIN field.
    This prevents false positives on insurance-related documents that aren't cards.

    Args:
        text: Lowercased haystack text
        field_keys: Extracted field keys

    Returns:
        Tuple of (is_insurance_card, details_dict)
    """
    # Anti-patterns first (explicit NOT insurance card statements)
    anti_patterns = [
        "this is not an insurance card",
        "summary of benefits",
        "explanation of benefits",
        "eob",
        "claim statement",
        "billing statement",
    ]
    if any(pattern in text for pattern in anti_patterns):
        logger.debug("Insurance card rejected: anti-pattern detected")
        return False, {"rejected_reason": "anti_pattern"}

    # Signal categories

    # Card identifiers
    card_indicators = ["member id", "subscriber id", "policy number", "certificate number"]
    has_card_indicator = any(indicator in text for indicator in card_indicators)

    # Insurance-specific terms
    insurance_terms = ["copay", "rx bin", "rx grp", "deductible", "payer id"]
    has_insurance_term = any(term in text for term in insurance_terms)

    # Network/plan types
    network_terms = ["ppo", "hmo", "epo", "pos"]
    has_network_term = any(term in text for term in network_terms)

    # Known insurers (strong signal)
    known_insurers = [
        "blue cross",
        "blue shield",
        "premera",
        "regence",
        "aetna",
        "cigna",
        "kaiser",
        "vsp",
        "delta dental",
    ]
    has_known_insurer = any(insurer in text for insurer in known_insurers)

    # Count signal types
    signal_count = sum(
        [has_card_indicator, has_insurance_term, has_network_term, has_known_insurer]
    )

    # RX BIN is VERY specific to insurance cards (instant match)
    has_rx_bin = "rx bin" in text or "rxbin" in text

    is_insurance = signal_count >= 2 or has_rx_bin

    details = {
        "signal_count": signal_count,
        "has_card_indicator": has_card_indicator,
        "has_insurance_term": has_insurance_term,
        "has_network_term": has_network_term,
        "has_known_insurer": has_known_insurer,
        "has_rx_bin": has_rx_bin,
    }

    if is_insurance:
        logger.debug(f"Insurance card detected: {signal_count} signals or RX BIN")

    return is_insurance, details
