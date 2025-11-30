"""Field extraction endpoints."""

from fastapi import APIRouter, HTTPException
from loguru import logger

from app.models import AnalyzeRequest, AnalyzeResponse, ExtractRequest, ExtractResponse
from app.services import ClassificationService, ExtractionService

router = APIRouter()


@router.post("/extract", response_model=ExtractResponse)
async def extract_fields(request: ExtractRequest) -> ExtractResponse:
    """Extract structured fields from a document.

    This endpoint performs context-aware field extraction based on the
    document type. Different extractors are used for different document types.

    Args:
        request: Extraction request with OCR text and document type

    Returns:
        Extracted fields with confidence scores

    Raises:
        HTTPException: If extraction fails
    """
    try:
        logger.info(
            f"🔍 /extract endpoint | type={request.document_type.value} | "
            f"text_length={len(request.ocr_text)}"
        )

        extraction_service = ExtractionService()
        fields = await extraction_service.extract_fields(
            ocr_text=request.ocr_text,
            document_type=request.document_type,
        )

        logger.success(f"✓ /extract completed | fields_count={len(fields)}")
        return ExtractResponse(fields=fields)

    except Exception as e:
        logger.error(f"✗ /extract failed: {e}")
        logger.exception("Full traceback:")
        raise HTTPException(status_code=500, detail=f"Extraction failed: {str(e)}")


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze_document(request: AnalyzeRequest) -> AnalyzeResponse:
    """Perform full document analysis (classify + extract).

    This endpoint is a convenience method that performs both classification
    and field extraction in a single request.

    Args:
        request: Analysis request with OCR text

    Returns:
        Complete analysis with classification and extracted fields

    Raises:
        HTTPException: If analysis fails
    """
    try:
        logger.info(
            f"🔬 /analyze endpoint | text_length={len(request.ocr_text)} | "
            f"hint={request.hint.value if request.hint else None}"
        )

        # Step 1: Classify
        logger.debug("Step 1: Classifying document...")
        doc_type, confidence, signals = ClassificationService.classify(
            ocr_text=request.ocr_text,
            hint=request.hint,
        )
        logger.debug(f"Classification: {doc_type.value} (confidence={confidence:.2%})")

        # Step 2: Extract fields
        logger.debug("Step 2: Extracting fields...")
        extraction_service = ExtractionService()
        fields = await extraction_service.extract_fields(
            ocr_text=request.ocr_text,
            document_type=doc_type,
        )

        logger.success(
            f"✓ /analyze completed | type={doc_type.value} | fields_count={len(fields)}"
        )

        return AnalyzeResponse(
            document_type=doc_type,
            confidence=confidence,
            signals=signals,
            fields=fields,
        )

    except Exception as e:
        logger.error(f"✗ /analyze failed: {e}")
        logger.exception("Full traceback:")
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")
