"""Document type models and enumerations."""

from enum import Enum


class DocumentType(str, Enum):
    """Supported document types for classification.

    Based on the classification strategy document, these types are ordered
    by detection priority in the classification algorithm.
    """

    RECEIPT = "receipt"
    """Proof of purchase transaction with payment evidence."""

    PROMOTIONAL = "promotional"
    """Marketing materials, offers, and promotional content."""

    BILL_STATEMENT = "billStatement"
    """Recurring service statements and invoices requiring payment."""

    CREDIT_CARD = "creditCard"
    """Physical payment cards (credit, debit)."""

    INSURANCE_CARD = "insuranceCard"
    """Health, dental, or vision insurance cards."""

    LETTER = "letter"
    """Personal or business correspondence."""

    GENERIC = "generic"
    """Documents that don't fit other categories."""

    def __str__(self) -> str:
        """Return the string value of the document type."""
        return self.value


# Document type metadata for API responses
DOCUMENT_TYPE_DESCRIPTIONS = {
    DocumentType.RECEIPT: "Proof of purchase with transaction ID and payment method",
    DocumentType.PROMOTIONAL: "Marketing materials, offers, coupons, and promotional content",
    DocumentType.BILL_STATEMENT: "Recurring service bills and statements requiring payment",
    DocumentType.CREDIT_CARD: "Physical payment cards (credit/debit) with PAN and expiry",
    DocumentType.INSURANCE_CARD: "Health/dental/vision insurance cards with member ID",
    DocumentType.LETTER: "Personal or business correspondence with salutation and closing",
    DocumentType.GENERIC: "Documents that don't fit other specific categories",
}
