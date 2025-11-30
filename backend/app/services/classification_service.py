"""Document classification service - Phase 2 implementation.

Main classification logic following the exact priority order from the strategy.
Based on lines 866-909 of the classification strategy document.
"""

from typing import Optional

from loguru import logger

from app.core.detectors import (
    is_bill_statement,
    is_credit_card,
    is_insurance_card,
    is_letter,
    is_promotional,
    is_receipt,
)
from app.models import ClassificationSignals, DocumentType, FieldModel


class ClassificationService:
    """Service for classifying documents based on OCR text and extracted fields."""

    @staticmethod
    def classify(
        ocr_text: str,
        fields: Optional[list[FieldModel]] = None,
        hint: Optional[DocumentType] = None,
        default_type: DocumentType = DocumentType.GENERIC,
    ) -> tuple[DocumentType, float, ClassificationSignals]:
        """Classify a document following the strategy's priority order.

        CRITICAL: Order matters! Promotional must be checked FIRST to prevent
        false positives (WA529 problem).

        Args:
            ocr_text: OCR-extracted text from document
            fields: Optional pre-extracted fields
            hint: Optional hint about expected document type
            default_type: Default type if no matches found

        Returns:
            Tuple of (document_type, confidence, signals)
        """
        fields = fields or []
        text = ocr_text.lower()
        field_keys = [f.key.lower() for f in fields]
        field_values = [f.value.lower() for f in fields]

        # Create haystack: OCR text + field values
        haystack = (text + " " + " ".join(field_values)).lower()

        logger.info(
            f"Starting classification | text_length={len(ocr_text)} | "
            f"fields_count={len(fields)} | hint={hint.value if hint else None}"
        )
        logger.debug(f"Text preview: {ocr_text[:200]}...")

        # STEP 1: Check promotional EARLY to prevent false positives
        logger.debug("STEP 1: Checking promotional signals...")
        promotional_hit, promo_details = is_promotional(haystack)
        if promotional_hit:
            logger.debug(f"✓ Promotional detected | signals={promo_details}")

        # STEP 2: High-specificity types (strong unique patterns)
        logger.debug("STEP 2: Checking high-specificity types (insurance, credit)...")
        insurance_hit, insurance_details = is_insurance_card(haystack, field_keys)
        if insurance_hit:
            logger.debug(f"✓ Insurance card detected | signals={insurance_details}")
        credit_hit, credit_details = is_credit_card(haystack, field_values, field_keys)
        if credit_hit:
            logger.debug(f"✓ Credit card detected | signals={credit_details}")

        # STEP 3: Transactional types (require structure)
        logger.debug("STEP 3: Checking transactional types (receipt, bill)...")
        receipt_hit, receipt_details = is_receipt(haystack, field_keys, promotional_hit)
        if receipt_hit:
            logger.debug(f"✓ Receipt detected | signals={receipt_details}")
        bill_hit, bill_details = is_bill_statement(haystack)
        if bill_hit:
            logger.debug(f"✓ Bill detected | signals={bill_details}")

        # STEP 4: Generic types (weaker signals)
        logger.debug("STEP 4: Checking generic types (letter)...")
        letter_hit, letter_details = is_letter(haystack, promotional_hit)
        if letter_hit:
            logger.debug(f"✓ Letter detected | signals={letter_details}")

        # Build signals object
        signals = ClassificationSignals(
            promotional=promotional_hit,
            receipt=receipt_hit,
            bill=bill_hit,
            insurance_card=insurance_hit,
            credit_card=credit_hit,
            letter=letter_hit,
            details={
                "promotional": promo_details,
                "receipt": receipt_details,
                "insurance_card": insurance_details,
                "credit_card": credit_details,
                "bill": bill_details,
                "letter": letter_details,
            },
        )

        # PRIORITY ORDER (critical!)
        result: DocumentType
        confidence: float

        if promotional_hit:
            result = DocumentType.PROMOTIONAL
            confidence = ClassificationService._calculate_confidence(
                promo_details.get("signal_count", 0), max_signals=5
            )
            logger.success(
                f"Classification: PROMOTIONAL | confidence={confidence:.2%} | "
                f"signals={promo_details.get('signal_count', 0)}/5"
            )

        elif insurance_hit:
            result = DocumentType.INSURANCE_CARD
            confidence = ClassificationService._calculate_confidence(
                insurance_details.get("signal_count", 0), max_signals=4
            )
            # RX BIN is instant high confidence
            if insurance_details.get("has_rx_bin"):
                confidence = 0.95
            logger.success(
                f"Classification: INSURANCE_CARD | confidence={confidence:.2%} | "
                f"rx_bin={insurance_details.get('has_rx_bin', False)}"
            )

        elif credit_hit:
            result = DocumentType.CREDIT_CARD
            # High confidence if has issuer name
            confidence = 0.9 if credit_details.get("has_issuer_name") else 0.75
            logger.success(
                f"Classification: CREDIT_CARD | confidence={confidence:.2%} | "
                f"issuer={credit_details.get('has_issuer_name', False)}"
            )

        elif receipt_hit:
            result = DocumentType.RECEIPT
            # Tiered confidence based on rule strength
            rule = receipt_details.get("rule", "")
            if rule == "strong_transaction":
                confidence = 0.95
            elif rule == "merchant_payment":
                confidence = 0.85
            else:
                confidence = 0.70
            logger.success(
                f"Classification: RECEIPT | confidence={confidence:.2%} | rule={rule}"
            )

        elif bill_hit:
            result = DocumentType.BILL_STATEMENT
            # High confidence if has billing term
            confidence = 0.9 if bill_details.get("has_billing_term") else 0.75
            logger.success(
                f"Classification: BILL_STATEMENT | confidence={confidence:.2%} | "
                f"has_billing_term={bill_details.get('has_billing_term', False)}"
            )

        elif letter_hit:
            result = DocumentType.LETTER
            confidence = 0.80
            logger.success(f"Classification: LETTER | confidence={confidence:.2%}")

        else:
            result = default_type
            confidence = 0.3
            logger.warning(
                f"Classification: GENERIC (no strong signals) | confidence={confidence:.2%}"
            )

        # Log decision for debugging
        ClassificationService._log_decision(result, confidence, signals)

        return result, confidence, signals

    @staticmethod
    def _calculate_confidence(signal_count: int, max_signals: int) -> float:
        """Calculate confidence score based on signal count.

        Args:
            signal_count: Number of signals detected
            max_signals: Maximum possible signals

        Returns:
            Confidence score between 0.0 and 1.0
        """
        if signal_count >= max_signals:
            return 0.95
        elif signal_count >= max_signals - 1:
            return 0.85
        elif signal_count >= 2:
            return 0.75
        else:
            return 0.60

    @staticmethod
    def _log_decision(
        doc_type: DocumentType, confidence: float, signals: ClassificationSignals
    ) -> None:
        """Log classification decision for debugging.

        Args:
            doc_type: Classified document type
            confidence: Confidence score
            signals: Classification signals
        """
        logger.debug("─" * 80)
        logger.debug(f"FINAL RESULT: {doc_type.value} | confidence={confidence:.2%}")
        logger.debug("Signal Summary:")
        logger.debug(f"  • Promotional: {'✓' if signals.promotional else '✗'}")
        logger.debug(f"  • Receipt: {'✓' if signals.receipt else '✗'}")
        logger.debug(f"  • Bill: {'✓' if signals.bill else '✗'}")
        logger.debug(f"  • Insurance Card: {'✓' if signals.insurance_card else '✗'}")
        logger.debug(f"  • Credit Card: {'✓' if signals.credit_card else '✗'}")
        logger.debug(f"  • Letter: {'✓' if signals.letter else '✗'}")
        logger.debug("─" * 80)
