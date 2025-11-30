"""Request models for API endpoints."""

from typing import Optional

from pydantic import BaseModel, Field

from app.models.document import DocumentType
from app.models.responses import FieldModel


class ClassifyRequest(BaseModel):
    """Request to classify a document from OCR text.

    Attributes:
        ocr_text: The extracted text from the document (required)
        fields: Optional pre-extracted fields to enhance classification
        hint: Optional hint about the expected document type
    """

    ocr_text: str = Field(
        ...,
        description="OCR-extracted text from the document",
        min_length=1,
        examples=[
            "CVS Pharmacy\nReceipt #12345\nAdvil $12.99\nTotal: $12.99\nVISA ****1234"
        ],
    )
    fields: Optional[list[FieldModel]] = Field(
        default=None,
        description="Pre-extracted fields to enhance classification accuracy",
    )
    hint: Optional[DocumentType] = Field(
        default=None,
        description="Optional hint about expected document type",
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "ocr_text": "Get $50 when you open a WA529 account by 12/12/2025.\nUse promo code Offer25.",
                    "fields": [
                        {"key": "amount", "value": "$50", "confidence": 0.95, "source": "ocr"}
                    ],
                }
            ]
        }
    }


class ExtractRequest(BaseModel):
    """Request to extract structured fields from a document.

    Attributes:
        ocr_text: The extracted text from the document (required)
        document_type: The classified document type (required for context-aware extraction)
    """

    ocr_text: str = Field(
        ...,
        description="OCR-extracted text from the document",
        min_length=1,
    )
    document_type: DocumentType = Field(
        ...,
        description="Document type for context-aware field extraction",
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "ocr_text": "CVS Pharmacy\nReceipt #12345\nAdvil $12.99\nTotal: $12.99",
                    "document_type": "receipt",
                }
            ]
        }
    }


class AnalyzeRequest(BaseModel):
    """Request to perform full document analysis (classify + extract).

    Attributes:
        ocr_text: The extracted text from the document (required)
        hint: Optional hint about expected document type
    """

    ocr_text: str = Field(
        ...,
        description="OCR-extracted text from the document",
        min_length=1,
    )
    hint: Optional[DocumentType] = Field(
        default=None,
        description="Optional hint about expected document type",
    )

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "ocr_text": "Make this the season you start saving!\nGet $50 when you open a WA529 account.",
                }
            ]
        }
    }
