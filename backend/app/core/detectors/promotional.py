"""Promotional content detector - Phase 3 implementation.

Detects marketing materials, offers, coupons, and promotional content.
Based on lines 922-966 of the classification strategy.
"""

import logging

logger = logging.getLogger(__name__)


def is_promotional(text: str) -> tuple[bool, dict]:
    """Detect promotional content using multi-signal analysis.

    Requires at least 2 different promotional signal types to classify as promotional.
    This prevents false positives while catching marketing materials.

    Args:
        text: Lowercased haystack text (OCR + field values)

    Returns:
        Tuple of (is_promotional, details_dict)
        - is_promotional: True if 2+ signal types detected
        - details_dict: Breakdown of detected signals
    """
    # Future-conditional verbs (offer contingent on action)
    incentive_verbs = [
        "get $",
        "earn",
        "save $",
        "receive",
        "win",
        "claim",
        "redeem",
    ]

    # Future/conditional grammar
    conditionals = [
        "when you",
        "if you",
        "after you",
        "you'll",
        "we'll",
        "you will",
        "you can",
    ]

    # Promotional terminology
    promo_terms = [
        "promo code",
        "promotional code",
        "offer code",
        "offer",
        "promotion",
        "deal",
        "bonus",
        "reward",
        "free",
        "gift",
    ]

    # Urgency/scarcity
    urgency = [
        "limited time",
        "expires",
        "ends",
        "by ",
        "hurry",
        "act now",
        "don't miss",
        "last chance",
    ]

    # Call-to-action
    ctas = [
        "sign up",
        "enroll",
        "apply now",
        "join now",
        "visit",
        "call now",
        "click here",
        "register",
    ]

    # Count distinct signal types
    has_incentive_verb = any(verb in text for verb in incentive_verbs)
    has_conditional = any(cond in text for cond in conditionals)
    has_promo_term = any(term in text for term in promo_terms)
    has_urgency = any(urg in text for urg in urgency)
    has_cta = any(cta in text for cta in ctas)

    signal_count = sum(
        [has_incentive_verb, has_conditional, has_promo_term, has_urgency, has_cta]
    )

    # Require at least 2 different promotional signal types
    is_promo = signal_count >= 2

    details = {
        "signal_count": signal_count,
        "has_incentive_verb": has_incentive_verb,
        "has_conditional": has_conditional,
        "has_promo_term": has_promo_term,
        "has_urgency": has_urgency,
        "has_cta": has_cta,
    }

    if is_promo:
        logger.debug(f"Promotional detected: {signal_count} signal types")

    return is_promo, details
