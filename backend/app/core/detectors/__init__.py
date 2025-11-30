"""Document type detectors."""

from app.core.detectors.bill import is_bill_statement
from app.core.detectors.credit_card import is_credit_card
from app.core.detectors.insurance import is_insurance_card
from app.core.detectors.letter import is_letter
from app.core.detectors.promotional import is_promotional
from app.core.detectors.receipt import is_receipt

__all__ = [
    "is_promotional",
    "is_receipt",
    "is_insurance_card",
    "is_credit_card",
    "is_bill_statement",
    "is_letter",
]
