"""API v1 router configuration."""

from fastapi import APIRouter

from app.api.v1.endpoints import classification, extraction, health, upload

api_router = APIRouter()

# Include all endpoint routers
api_router.include_router(
    classification.router,
    tags=["classification"],
)

api_router.include_router(
    extraction.router,
    tags=["extraction"],
)

api_router.include_router(
    upload.router,
    tags=["upload"],
)

api_router.include_router(
    health.router,
    tags=["health"],
)
