"""Base LLM provider interface."""

from abc import ABC, abstractmethod
from typing import Any


class LLMProvider(ABC):
    """Abstract base class for LLM providers.

    This interface allows swapping between different LLM providers
    (OpenAI, Anthropic, Google, etc.) without changing the application code.
    """

    def __init__(self, api_key: str, model_name: str):
        """Initialize the LLM provider.

        Args:
            api_key: API key for the provider
            model_name: Model name/identifier to use
        """
        self.api_key = api_key
        self.model_name = model_name

    @abstractmethod
    async def complete(
        self,
        prompt: str,
        system_prompt: str | None = None,
        temperature: float = 0.0,
        max_tokens: int = 1000,
    ) -> str:
        """Generate a completion from the LLM.

        Args:
            prompt: The user prompt/question
            system_prompt: Optional system prompt to set context
            temperature: Sampling temperature (0.0 = deterministic)
            max_tokens: Maximum tokens to generate

        Returns:
            The generated text completion

        Raises:
            Exception: If the API call fails
        """
        pass

    @abstractmethod
    async def extract_json(
        self,
        prompt: str,
        system_prompt: str | None = None,
        schema: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Extract structured JSON data from text.

        Args:
            prompt: The user prompt with text to analyze
            system_prompt: Optional system prompt
            schema: Optional JSON schema to validate against

        Returns:
            Parsed JSON object

        Raises:
            Exception: If the API call fails or JSON is invalid
        """
        pass

    @abstractmethod
    def get_provider_name(self) -> str:
        """Get the provider name.

        Returns:
            Provider identifier string
        """
        pass
