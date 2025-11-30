"""LLM provider factory for creating provider instances."""

import logging

from app.core.config import LLMProvider as LLMProviderEnum
from app.core.config import settings
from app.services.llm.anthropic_provider import AnthropicProvider
from app.services.llm.base import LLMProvider
from app.services.llm.google_provider import GoogleProvider
from app.services.llm.openai_provider import OpenAIProvider

logger = logging.getLogger(__name__)


class LLMProviderFactory:
    """Factory for creating LLM provider instances."""

    _instance: LLMProvider | None = None

    @classmethod
    def create_provider(
        cls, provider_type: LLMProviderEnum | None = None
    ) -> LLMProvider:
        """Create an LLM provider instance.

        Args:
            provider_type: Type of provider to create (uses config default if None)

        Returns:
            Configured LLM provider instance

        Raises:
            ValueError: If provider type is unknown or API key is missing
        """
        provider_type = provider_type or settings.llm_provider

        api_key = settings.get_api_key(provider_type)
        if not api_key:
            raise ValueError(
                f"API key not configured for provider: {provider_type}. "
                f"Please set the appropriate environment variable."
            )

        model_name = settings.get_model_name(provider_type)

        if provider_type == LLMProviderEnum.OPENAI:
            logger.info("Creating OpenAI provider")
            return OpenAIProvider(api_key=api_key, model_name=model_name)
        elif provider_type == LLMProviderEnum.ANTHROPIC:
            logger.info("Creating Anthropic provider")
            return AnthropicProvider(api_key=api_key, model_name=model_name)
        elif provider_type == LLMProviderEnum.GOOGLE:
            logger.info("Creating Google provider")
            return GoogleProvider(api_key=api_key, model_name=model_name)
        else:
            raise ValueError(f"Unknown LLM provider: {provider_type}")

    @classmethod
    def get_provider(cls) -> LLMProvider:
        """Get or create the singleton provider instance.

        Returns:
            The singleton LLM provider instance
        """
        if cls._instance is None:
            cls._instance = cls.create_provider()
        return cls._instance

    @classmethod
    def reset_provider(cls) -> None:
        """Reset the singleton provider instance (useful for testing)."""
        cls._instance = None
