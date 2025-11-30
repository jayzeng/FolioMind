"""Response models for API endpoints."""

from typing import Any, Optional

from pydantic import BaseModel, Field

from app.models.document import DocumentType


class FieldModel(BaseModel):
    """Represents an extracted field from a document.

    Attributes:
        key: Field identifier (e.g., "amount", "date", "merchant")
        value: Extracted value
        confidence: Confidence score (0.0-1.0)
        source: Source of extraction (e.g., "ocr", "llm", "pattern")
    """

    key: str = Field(..., description="Field identifier")
    value: str = Field(..., description="Extracted field value")
    confidence: float = Field(
        ..., ge=0.0, le=1.0, description="Confidence score between 0 and 1"
    )
    source: str = Field(..., description="Source of extraction (ocr, llm, pattern)")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "key": "total_amount",
                    "value": "$12.99",
                    "confidence": 0.95,
                    "source": "pattern",
                }
            ]
        }
    }


class ClassificationSignals(BaseModel):
    """Signals used in classification decision.

    Attributes:
        promotional: Whether promotional signals were detected
        receipt: Whether receipt signals were detected
        bill: Whether bill statement signals were detected
        insurance_card: Whether insurance card signals were detected
        credit_card: Whether credit card signals were detected
        letter: Whether letter signals were detected
        details: Additional details about the classification decision
    """

    promotional: bool = Field(default=False, description="Promotional signals detected")
    receipt: bool = Field(default=False, description="Receipt signals detected")
    bill: bool = Field(default=False, description="Bill statement signals detected")
    insurance_card: bool = Field(default=False, description="Insurance card signals detected")
    credit_card: bool = Field(default=False, description="Credit card signals detected")
    letter: bool = Field(default=False, description="Letter signals detected")
    details: dict[str, Any] = Field(
        default_factory=dict, description="Additional classification details"
    )


class ClassifyResponse(BaseModel):
    """Response from document classification.

    Attributes:
        document_type: Classified document type
        confidence: Classification confidence score (0.0-1.0)
        signals: Detailed signals used in classification
    """

    document_type: DocumentType = Field(..., description="Classified document type")
    confidence: float = Field(
        ..., ge=0.0, le=1.0, description="Classification confidence score"
    )
    signals: ClassificationSignals = Field(..., description="Classification signals")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "document_type": "promotional",
                    "confidence": 0.92,
                    "signals": {
                        "promotional": True,
                        "receipt": False,
                        "bill": False,
                        "insurance_card": False,
                        "credit_card": False,
                        "letter": False,
                        "details": {
                            "promotional_signal_count": 3,
                            "has_promo_code": True,
                            "has_conditional_offer": True,
                        },
                    },
                }
            ]
        }
    }


class ExtractResponse(BaseModel):
    """Response from field extraction.

    Attributes:
        fields: List of extracted fields
    """

    fields: list[FieldModel] = Field(..., description="Extracted fields from document")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "fields": [
                        {
                            "key": "promo_code",
                            "value": "Offer25",
                            "confidence": 0.98,
                            "source": "pattern",
                        },
                        {
                            "key": "offer_amount",
                            "value": "$50",
                            "confidence": 0.95,
                            "source": "pattern",
                        },
                    ]
                }
            ]
        }
    }


class AnalyzeResponse(BaseModel):
    """Response from full document analysis.

    Attributes:
        document_type: Classified document type
        confidence: Classification confidence score
        signals: Classification signals
        fields: Extracted fields
    """

    document_type: DocumentType = Field(..., description="Classified document type")
    confidence: float = Field(
        ..., ge=0.0, le=1.0, description="Classification confidence score"
    )
    signals: ClassificationSignals = Field(..., description="Classification signals")
    fields: list[FieldModel] = Field(..., description="Extracted fields")


class HealthResponse(BaseModel):
    """Health check response.

    Attributes:
        status: Service status
        version: API version
        llm_provider: Active LLM provider
    """

    status: str = Field(..., description="Service status")
    version: str = Field(..., description="API version")
    llm_provider: str = Field(..., description="Active LLM provider")


class DocumentTypesResponse(BaseModel):
    """Response listing supported document types.

    Attributes:
        types: List of supported document types with descriptions
    """

    types: list[dict[str, str]] = Field(..., description="Supported document types")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "types": [
                        {
                            "type": "receipt",
                            "description": "Proof of purchase with transaction ID",
                        },
                        {
                            "type": "promotional",
                            "description": "Marketing materials and offers",
                        },
                    ]
                }
            ]
        }
    }


class ErrorResponse(BaseModel):
    """Error response model.

    Attributes:
        error: Error message
        detail: Optional detailed error information
    """

    error: str = Field(..., description="Error message")
    detail: Optional[str] = Field(default=None, description="Detailed error information")
