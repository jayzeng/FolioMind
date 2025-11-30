"""Bill statement detector - Phase 5 strengthened implementation.

Detects recurring service bills and statements requiring payment.
Based on lines 1097-1109 of the classification strategy.
"""

import logging

logger = logging.getLogger(__name__)


def is_bill_statement(text: str) -> tuple[bool, dict]:
    """Detect bill statements using combination of signals.

    Single "amount due" is NOT enough - requires combination with billing/service context.
    This prevents false positives on receipts showing "$0.00 amount due".

    Args:
        text: Lowercased haystack text

    Returns:
        Tuple of (is_bill, details_dict)
    """
    # Billing-specific terminology
    billing_terms = [
        "billing statement",
        "statement of account",
        "billing period",
        "statement date",
    ]
    has_billing_term = any(term in text for term in billing_terms)

    # Payment request terminology
    payment_due = [
        "amount due",
        "total due",
        "balance due",
        "minimum payment",
        "please pay",
    ]
    has_payment_due = any(term in text for term in payment_due)

    # Account management terms
    account_terms = [
        "account number",
        "previous balance",
        "current charges",
        "new balance",
    ]
    has_account_term = any(term in text for term in account_terms)

    # Service-specific terms
    service_terms = [
        "utility bill",
        "service period",
        "usage",
        "kwh",
        "therms",
        "medical bill",
    ]
    has_service_term = any(term in text for term in service_terms)

    # Invoice patterns
    invoice_terms = ["invoice number", "invoice date"]
    has_invoice = any(term in text for term in invoice_terms)

    # REQUIRE COMBINATION (single "amount due" not enough)
    is_bill = False
    matched_rule = None

    if has_billing_term:
        is_bill = True
        matched_rule = "billing_term"
    elif has_invoice and has_payment_due:
        is_bill = True
        matched_rule = "invoice_payment"
    elif has_service_term and has_payment_due:
        is_bill = True
        matched_rule = "service_payment"
    elif has_account_term and has_payment_due:
        is_bill = True
        matched_rule = "account_payment"

    details = {
        "has_billing_term": has_billing_term,
        "has_payment_due": has_payment_due,
        "has_account_term": has_account_term,
        "has_service_term": has_service_term,
        "has_invoice": has_invoice,
        "matched_rule": matched_rule,
    }

    if is_bill:
        logger.debug(f"Bill statement detected: rule={matched_rule}")

    return is_bill, details
