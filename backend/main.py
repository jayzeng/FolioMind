"""Convenience entry point for running the FastAPI application."""

if __name__ == "__main__":
    import uvicorn

    from app.core.config import settings

    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.api_reload,
        log_level=settings.log_level.lower(),
    )
