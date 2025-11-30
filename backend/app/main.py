"""FastAPI application entry point."""

import sys
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from loguru import logger

from app.api.v1.router import api_router
from app.core.config import settings

# Configure loguru
logger.remove()  # Remove default handler

# Console handler with colored output
logger.add(
    sys.stderr,
    level=settings.log_level,
    format=(
        "<green>{time:YYYY-MM-DD HH:mm:ss}</green> | "
        "<level>{level: <8}</level> | "
        "<cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> | "
        "<level>{message}</level>"
    ),
    colorize=True,
)

# File handler for persistent logs
log_dir = Path("logs")
log_dir.mkdir(exist_ok=True)

logger.add(
    log_dir / "foliomind_{time:YYYY-MM-DD}.log",
    rotation="00:00",  # New file at midnight
    retention="30 days",  # Keep logs for 30 days
    compression="zip",  # Compress old logs
    level=settings.log_level,
    format=(
        "{time:YYYY-MM-DD HH:mm:ss} | "
        "{level: <8} | "
        "{name}:{function}:{line} | "
        "{message}"
    ),
)

# Separate error log file
logger.add(
    log_dir / "errors_{time:YYYY-MM-DD}.log",
    rotation="00:00",
    retention="90 days",  # Keep error logs longer
    compression="zip",
    level="ERROR",
    format=(
        "{time:YYYY-MM-DD HH:mm:ss} | "
        "{level: <8} | "
        "{name}:{function}:{line} | "
        "{message}\n"
        "{exception}"
    ),
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events.

    Args:
        app: FastAPI application instance

    Yields:
        None
    """
    # Startup
    logger.info("=" * 80)
    logger.info("🚀 Starting FolioMind Backend API")
    logger.info("=" * 80)
    logger.info(f"LLM Provider: {settings.llm_provider.value}")
    logger.info(f"LLM Model: {settings.get_model_name(settings.llm_provider)}")
    logger.info(f"Log Level: {settings.log_level}")
    logger.info(f"API Host: {settings.api_host}:{settings.api_port}")
    logger.info(f"Reload Mode: {settings.api_reload}")
    logger.info("=" * 80)

    yield

    # Shutdown
    logger.info("=" * 80)
    logger.info("🛑 Shutting down FolioMind Backend API")
    logger.info("=" * 80)


# Create FastAPI application
app = FastAPI(
    title="FolioMind Document Classification API",
    description="""
    FolioMind Backend API for document classification and field extraction.

    ## Features

    * **Document Classification**: Automatically classify documents into types
      (receipt, promotional, bill, insurance card, credit card, letter, generic)
    * **Field Extraction**: Extract structured fields from documents with
      context-aware extraction based on document type
    * **Full Analysis**: Combined classification and extraction in one request
    * **Multi-LLM Support**: Flexible LLM provider support (OpenAI, Anthropic, Google)

    ## Classification Strategy

    The classification follows a carefully designed priority order to prevent
    false positives:

    1. Promotional content (checked first to prevent WA529-style misclassifications)
    2. High-specificity types (insurance cards, credit cards)
    3. Transactional types (receipts, bills)
    4. Generic types (letters)
    5. Default (generic)

    Each detector uses multi-signal analysis requiring combinations of
    indicators rather than single keyword matches.
    """,
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API router
app.include_router(api_router, prefix="/api/v1")


# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Handle uncaught exceptions.

    Args:
        request: The request that caused the exception
        exc: The exception that was raised

    Returns:
        JSON error response
    """
    logger.error(f"❌ Unhandled exception on {request.method} {request.url.path}: {exc}")
    logger.exception("Full traceback:")
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "detail": str(exc) if settings.log_level == "DEBUG" else None,
        },
    )


# Root endpoint
@app.get("/")
async def root():
    """Root endpoint with API information.

    Returns:
        API metadata
    """
    return {
        "name": "FolioMind Document Classification API",
        "version": "0.1.0",
        "status": "running",
        "docs": "/docs",
        "api_prefix": "/api/v1",
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.api_reload,
        log_level=settings.log_level.lower(),
    )
