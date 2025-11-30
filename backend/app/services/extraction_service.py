"""Field extraction service with context-aware refinement.

Extracts structured fields from documents using pattern matching and LLM assistance.
Based on lines 1133-1198 of the classification strategy.
"""

import re
from typing import Any

from loguru import logger

from app.models import DocumentType, FieldModel
from app.services.llm import LLMProviderFactory


class ExtractionService:
    """Service for extracting structured fields from documents."""

    def __init__(self):
        """Initialize extraction service."""
        self.llm_provider = LLMProviderFactory.get_provider()

    async def extract_fields(
        self, ocr_text: str, document_type: DocumentType
    ) -> list[FieldModel]:
        """Extract fields from document with context-aware refinement.

        Args:
            ocr_text: OCR-extracted text
            document_type: Classified document type for context

        Returns:
            List of extracted fields
        """
        logger.info(
            f"Starting field extraction | doc_type={document_type.value} | "
            f"text_length={len(ocr_text)}"
        )

        # Extract basic fields using pattern matching
        logger.debug("Extracting pattern-based fields...")
        fields = self._extract_pattern_fields(ocr_text)
        logger.debug(f"Found {len(fields)} pattern-based fields")

        # Refine fields based on document type
        logger.debug(f"Refining fields for {document_type.value}...")
        fields = self._refine_fields_by_type(fields, document_type, ocr_text)

        # Extract document-specific fields
        logger.debug(f"Extracting {document_type.value}-specific fields...")
        if document_type == DocumentType.PROMOTIONAL:
            promo_fields = self._extract_promotional_fields(ocr_text)
            logger.debug(f"Found {len(promo_fields)} promotional fields")
            fields.extend(promo_fields)
        elif document_type == DocumentType.RECEIPT:
            receipt_fields = self._extract_receipt_fields(ocr_text)
            logger.debug(f"Found {len(receipt_fields)} receipt fields")
            fields.extend(receipt_fields)
        elif document_type == DocumentType.BILL_STATEMENT:
            bill_fields = self._extract_bill_fields(ocr_text)
            logger.debug(f"Found {len(bill_fields)} bill fields")
            fields.extend(bill_fields)

        # Use LLM for additional extraction if needed
        # llm_fields = await self._extract_with_llm(ocr_text, document_type)
        # fields.extend(llm_fields)

        logger.success(f"Extraction complete | total_fields={len(fields)}")
        for field in fields[:5]:  # Log first 5 fields
            logger.debug(f"  • {field.key}: {field.value} (confidence={field.confidence:.2%})")

        return fields

    def _extract_pattern_fields(self, text: str) -> list[FieldModel]:
        """Extract basic fields using regex patterns.

        Args:
            text: Text to extract from

        Returns:
            List of extracted fields
        """
        fields = []

        # Extract dollar amounts
        amount_pattern = r"\$\s*(\d+(?:\.\d{2})?)"
        for match in re.finditer(amount_pattern, text):
            fields.append(
                FieldModel(
                    key="amount",
                    value=f"${match.group(1)}",
                    confidence=0.85,
                    source="pattern",
                )
            )

        # Extract dates (MM/DD/YYYY, MM-DD-YYYY)
        date_pattern = r"\b(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})\b"
        for match in re.finditer(date_pattern, text):
            fields.append(
                FieldModel(
                    key="date",
                    value=match.group(1),
                    confidence=0.90,
                    source="pattern",
                )
            )

        # Extract email addresses
        email_pattern = r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"
        for match in re.finditer(email_pattern, text):
            fields.append(
                FieldModel(
                    key="email",
                    value=match.group(0),
                    confidence=0.95,
                    source="pattern",
                )
            )

        # Extract phone numbers
        phone_pattern = r"\b(\d{3}[-.\s]?\d{3}[-.\s]?\d{4}|\(\d{3}\)\s*\d{3}[-.\s]?\d{4})\b"
        for match in re.finditer(phone_pattern, text):
            fields.append(
                FieldModel(
                    key="phone",
                    value=match.group(0),
                    confidence=0.85,
                    source="pattern",
                )
            )

        return fields

    def _refine_fields_by_type(
        self, fields: list[FieldModel], document_type: DocumentType, text: str
    ) -> list[FieldModel]:
        """Refine fields based on document type context.

        Args:
            fields: Initial extracted fields
            document_type: Document type
            text: Original text

        Returns:
            Refined fields list
        """
        refined = []

        for field in fields:
            if document_type == DocumentType.PROMOTIONAL:
                # Relabel amounts as promotional offers
                if field.key == "amount":
                    refined.append(
                        FieldModel(
                            key="offer_amount",
                            value=field.value,
                            confidence=field.confidence * 0.9,
                            source=field.source,
                        )
                    )
                else:
                    refined.append(field)

            elif document_type == DocumentType.RECEIPT:
                # Keep amounts as transaction amounts
                refined.append(field)

            elif document_type == DocumentType.BILL_STATEMENT:
                # Relabel amounts as due amounts
                if field.key == "amount":
                    refined.append(
                        FieldModel(
                            key="amount_due",
                            value=field.value,
                            confidence=field.confidence * 0.9,
                            source=field.source,
                        )
                    )
                else:
                    refined.append(field)

            else:
                refined.append(field)

        return refined

    def _extract_promotional_fields(self, text: str) -> list[FieldModel]:
        """Extract promotional-specific fields.

        Args:
            text: Text to extract from

        Returns:
            Promotional fields
        """
        fields = []

        # Extract promo codes
        promo_patterns = [
            r"promo\s*code:?\s*([A-Z0-9]+)",
            r"use\s*code:?\s*([A-Z0-9]+)",
            r"code:?\s*([A-Z0-9]{4,})",
        ]
        for pattern in promo_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                fields.append(
                    FieldModel(
                        key="promo_code",
                        value=match.group(1),
                        confidence=0.95,
                        source="pattern",
                    )
                )
                break

        # Extract offer expiration
        expiry_patterns = [
            r"expires?:?\s*([A-Za-z]+\s+\d{1,2},?\s+\d{4})",
            r"ends?:?\s*([A-Za-z]+\s+\d{1,2},?\s+\d{4})",
            r"by\s+(\d{1,2}/\d{1,2}/\d{4})",
        ]
        for pattern in expiry_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                fields.append(
                    FieldModel(
                        key="offer_expiry",
                        value=match.group(1),
                        confidence=0.90,
                        source="pattern",
                    )
                )
                break

        return fields

    def _extract_receipt_fields(self, text: str) -> list[FieldModel]:
        """Extract receipt-specific fields.

        Args:
            text: Text to extract from

        Returns:
            Receipt fields
        """
        fields = []

        # Extract receipt/transaction number
        receipt_patterns = [
            r"receipt\s*#:?\s*([A-Z0-9-]+)",
            r"transaction\s*#:?\s*([A-Z0-9-]+)",
            r"order\s*#:?\s*([A-Z0-9-]+)",
        ]
        for pattern in receipt_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                fields.append(
                    FieldModel(
                        key="transaction_id",
                        value=match.group(1),
                        confidence=0.95,
                        source="pattern",
                    )
                )
                break

        # Extract total amount (more specific for receipts)
        total_pattern = r"total:?\s*\$\s*(\d+\.\d{2})"
        match = re.search(total_pattern, text, re.IGNORECASE)
        if match:
            fields.append(
                FieldModel(
                    key="total_amount",
                    value=f"${match.group(1)}",
                    confidence=0.95,
                    source="pattern",
                )
            )

        return fields

    def _extract_bill_fields(self, text: str) -> list[FieldModel]:
        """Extract bill-specific fields.

        Args:
            text: Text to extract from

        Returns:
            Bill fields
        """
        fields = []

        # Extract due date
        due_date_patterns = [
            r"due\s*date:?\s*(\d{1,2}/\d{1,2}/\d{4})",
            r"payment\s*due:?\s*(\d{1,2}/\d{1,2}/\d{4})",
        ]
        for pattern in due_date_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                fields.append(
                    FieldModel(
                        key="due_date",
                        value=match.group(1),
                        confidence=0.95,
                        source="pattern",
                    )
                )
                break

        # Extract account number
        account_pattern = r"account\s*#?:?\s*([A-Z0-9-]+)"
        match = re.search(account_pattern, text, re.IGNORECASE)
        if match:
            fields.append(
                FieldModel(
                    key="account_number",
                    value=match.group(1),
                    confidence=0.90,
                    source="pattern",
                )
            )

        return fields

    async def _extract_with_llm(
        self, text: str, document_type: DocumentType
    ) -> list[FieldModel]:
        """Use LLM to extract additional fields.

        Args:
            text: Text to extract from
            document_type: Document type for context

        Returns:
            LLM-extracted fields
        """
        try:
            system_prompt = f"You are an expert at extracting structured information from {document_type.value} documents."

            prompt = f"""Extract key fields from this {document_type.value} document:

{text}

Return a JSON object with extracted fields in this format:
{{
    "fields": [
        {{"key": "field_name", "value": "extracted_value", "confidence": 0.95}}
    ]
}}
"""

            result = await self.llm_provider.extract_json(prompt, system_prompt)

            fields = []
            for field_data in result.get("fields", []):
                fields.append(
                    FieldModel(
                        key=field_data["key"],
                        value=field_data["value"],
                        confidence=field_data.get("confidence", 0.8),
                        source="llm",
                    )
                )

            logger.success(f"LLM extracted {len(fields)} additional fields")
            return fields

        except Exception as e:
            logger.error(f"LLM extraction failed: {e}")
            logger.exception("Full traceback:")
            return []
