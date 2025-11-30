"""Classification endpoints."""

from fastapi import APIRouter, HTTPException
from loguru import logger

from app.models import ClassifyRequest, ClassifyResponse
from app.services import ClassificationService

router = APIRouter()


@router.post("/classify", response_model=ClassifyResponse)
async def classify_document(request: ClassifyRequest) -> ClassifyResponse:
    """Classify a document from OCR text.

    This endpoint analyzes OCR-extracted text and optional pre-extracted fields
    to determine the document type using the classification strategy.

    Args:
        request: Classification request with OCR text and optional fields

    Returns:
        Classification result with document type, confidence, and signals

    Raises:
        HTTPException: If classification fails
    """
    try:
        logger.info(
            f"📄 /classify endpoint | text_length={len(request.ocr_text)} | "
            f"fields_count={len(request.fields) if request.fields else 0} | "
            f"hint={request.hint.value if request.hint else None}"
        )

        doc_type, confidence, signals = ClassificationService.classify(
            ocr_text=request.ocr_text,
            fields=request.fields,
            hint=request.hint,
        )

        logger.success(
            f"✓ /classify completed | type={doc_type.value} | confidence={confidence:.2%}"
        )

        return ClassifyResponse(
            document_type=doc_type,
            confidence=confidence,
            signals=signals,
        )

    except Exception as e:
        logger.error(f"✗ /classify failed: {e}")
        logger.exception("Full traceback:")
        raise HTTPException(status_code=500, detail=f"Classification failed: {str(e)}")
