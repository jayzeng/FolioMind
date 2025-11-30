"""Application configuration management."""

from enum import Enum
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class LLMProvider(str, Enum):
    """Supported LLM providers."""

    OPENAI = "openai"
    ANTHROPIC = "anthropic"
    GOOGLE = "google"


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # API Configuration
    api_host: str = Field(default="0.0.0.0", description="API host")
    api_port: int = Field(default=8000, description="API port")
    api_reload: bool = Field(default=False, description="Enable auto-reload")
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = Field(
        default="INFO", description="Logging level"
    )

    # LLM Provider Configuration
    llm_provider: LLMProvider = Field(
        default=LLMProvider.OPENAI, description="LLM provider to use"
    )
    openai_api_key: str = Field(default="", description="OpenAI API key")
    anthropic_api_key: str = Field(default="", description="Anthropic API key")
    google_api_key: str = Field(default="", description="Google API key")

    # Model Configuration
    openai_model: str = Field(
        default="gpt-4-turbo-preview", description="OpenAI model name"
    )
    anthropic_model: str = Field(
        default="claude-3-sonnet-20240229", description="Anthropic model name"
    )
    google_model: str = Field(default="gemini-pro", description="Google model name")

    # OpenAI Vision and Whisper Configuration
    openai_vision_model: str = Field(
        default="gpt-4o", description="OpenAI Vision model for OCR"
    )
    whisper_model: str = Field(
        default="whisper-1", description="OpenAI Whisper model for audio transcription"
    )

    # Classification Configuration
    default_document_type: str = Field(
        default="generic", description="Default document type for unknown documents"
    )
    confidence_threshold: float = Field(
        default=0.6, description="Minimum confidence threshold"
    )

    def get_api_key(self, provider: LLMProvider) -> str:
        """Get API key for the specified provider."""
        if provider == LLMProvider.OPENAI:
            return self.openai_api_key
        elif provider == LLMProvider.ANTHROPIC:
            return self.anthropic_api_key
        elif provider == LLMProvider.GOOGLE:
            return self.google_api_key
        raise ValueError(f"Unknown provider: {provider}")

    def get_model_name(self, provider: LLMProvider) -> str:
        """Get model name for the specified provider."""
        if provider == LLMProvider.OPENAI:
            return self.openai_model
        elif provider == LLMProvider.ANTHROPIC:
            return self.anthropic_model
        elif provider == LLMProvider.GOOGLE:
            return self.google_model
        raise ValueError(f"Unknown provider: {provider}")


# Global settings instance
settings = Settings()
