"""Upload models for file upload endpoints."""

from typing import Optional

from pydantic import BaseModel, Field

from app.models.document import DocumentType
from app.models.responses import ClassificationSignals, FieldModel


class UploadResponse(BaseModel):
    """Response from file upload and analysis.

    Attributes:
        extracted_text: Text extracted from the uploaded file (OCR or transcription)
        document_type: Classified document type
        confidence: Classification confidence score
        signals: Classification signals used in the decision
        fields: Extracted fields from the document
    """

    extracted_text: str = Field(..., description="Extracted text from uploaded file")
    document_type: DocumentType = Field(..., description="Classified document type")
    confidence: float = Field(
        ..., ge=0.0, le=1.0, description="Classification confidence score"
    )
    signals: ClassificationSignals = Field(..., description="Classification signals")
    fields: list[FieldModel] = Field(..., description="Extracted fields from document")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "extracted_text": "CVS Pharmacy\nReceipt #12345\nAdvil $12.99\nTotal: $12.99",
                    "document_type": "receipt",
                    "confidence": 0.95,
                    "signals": {
                        "promotional": False,
                        "receipt": True,
                        "bill": False,
                        "insurance_card": False,
                        "credit_card": False,
                        "letter": False,
                        "details": {},
                    },
                    "fields": [
                        {
                            "key": "transaction_id",
                            "value": "12345",
                            "confidence": 0.95,
                            "source": "pattern",
                        },
                        {
                            "key": "total_amount",
                            "value": "$12.99",
                            "confidence": 0.95,
                            "source": "pattern",
                        },
                    ],
                }
            ]
        }
    }


class UploadMetadata(BaseModel):
    """Metadata about the uploaded file.

    Attributes:
        filename: Original filename
        file_size: File size in bytes
        file_type: MIME type of the file
        processing_time_ms: Time taken to process the file (in milliseconds)
    """

    filename: str = Field(..., description="Original filename")
    file_size: int = Field(..., description="File size in bytes")
    file_type: str = Field(..., description="MIME type of the file")
    processing_time_ms: Optional[float] = Field(
        default=None, description="Processing time in milliseconds"
    )


class UploadResponseWithMetadata(UploadResponse):
    """Upload response with additional metadata.

    Attributes:
        metadata: Metadata about the uploaded file
    """

    metadata: UploadMetadata = Field(..., description="File upload metadata")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {
                    "extracted_text": "CVS Pharmacy\nReceipt #12345\nAdvil $12.99\nTotal: $12.99",
                    "document_type": "receipt",
                    "confidence": 0.95,
                    "signals": {
                        "promotional": False,
                        "receipt": True,
                        "bill": False,
                        "insurance_card": False,
                        "credit_card": False,
                        "letter": False,
                        "details": {},
                    },
                    "fields": [
                        {
                            "key": "transaction_id",
                            "value": "12345",
                            "confidence": 0.95,
                            "source": "pattern",
                        }
                    ],
                    "metadata": {
                        "filename": "receipt.jpg",
                        "file_size": 245760,
                        "file_type": "image/jpeg",
                        "processing_time_ms": 1250.5,
                    },
                }
            ]
        }
    }


class ErrorDetail(BaseModel):
    """Detailed error information.

    Attributes:
        error: Error type/category
        message: Human-readable error message
        detail: Additional error details
    """

    error: str = Field(..., description="Error type")
    message: str = Field(..., description="Error message")
    detail: Optional[str] = Field(default=None, description="Additional details")
