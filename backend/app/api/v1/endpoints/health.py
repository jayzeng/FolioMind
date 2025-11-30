"""Health check and metadata endpoints."""

import logging

from fastapi import APIRouter

from app.core.config import settings
from app.models import DOCUMENT_TYPE_DESCRIPTIONS, DocumentTypesResponse, HealthResponse

logger = logging.getLogger(__name__)
router = APIRouter()

API_VERSION = "0.1.0"


@router.get("/health", response_model=HealthResponse)
async def health_check() -> HealthResponse:
    """Health check endpoint.

    Returns basic service status and configuration information.

    Returns:
        Health status with version and LLM provider info
    """
    return HealthResponse(
        status="healthy",
        version=API_VERSION,
        llm_provider=settings.llm_provider.value,
    )


@router.get("/types", response_model=DocumentTypesResponse)
async def get_document_types() -> DocumentTypesResponse:
    """Get list of supported document types.

    Returns information about all supported document types and their
    descriptions for client reference.

    Returns:
        List of document types with descriptions
    """
    types = [
        {"type": doc_type.value, "description": description}
        for doc_type, description in DOCUMENT_TYPE_DESCRIPTIONS.items()
    ]

    return DocumentTypesResponse(types=types)
