"""Anthropic Claude LLM provider implementation."""

import json
import logging
from typing import Any

from anthropic import AsyncAnthropic

from app.services.llm.base import LLMProvider

logger = logging.getLogger(__name__)


class AnthropicProvider(LLMProvider):
    """Anthropic Claude provider implementation."""

    def __init__(self, api_key: str, model_name: str):
        """Initialize Anthropic provider.

        Args:
            api_key: Anthropic API key
            model_name: Model name (e.g., "claude-3-sonnet-20240229")
        """
        super().__init__(api_key, model_name)
        self.client = AsyncAnthropic(api_key=api_key)
        logger.info(f"Initialized Anthropic provider with model: {model_name}")

    async def complete(
        self,
        prompt: str,
        system_prompt: str | None = None,
        temperature: float = 0.0,
        max_tokens: int = 1000,
    ) -> str:
        """Generate a completion using Anthropic API.

        Args:
            prompt: User prompt
            system_prompt: Optional system prompt
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate

        Returns:
            Generated text completion
        """
        try:
            kwargs = {
                "model": self.model_name,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": temperature,
                "max_tokens": max_tokens,
            }
            if system_prompt:
                kwargs["system"] = system_prompt

            response = await self.client.messages.create(**kwargs)
            result = response.content[0].text if response.content else ""
            logger.debug(f"Anthropic completion generated: {len(result)} chars")
            return result
        except Exception as e:
            logger.error(f"Anthropic API error: {e}")
            raise

    async def extract_json(
        self,
        prompt: str,
        system_prompt: str | None = None,
        schema: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Extract structured JSON using Anthropic API.

        Args:
            prompt: User prompt with text to analyze
            system_prompt: Optional system prompt
            schema: Optional JSON schema

        Returns:
            Parsed JSON object
        """
        # Enhance prompt to request JSON output
        json_prompt = f"{prompt}\n\nRespond with valid JSON only, no additional text."
        if schema:
            json_prompt += f"\n\nJSON Schema:\n{json.dumps(schema, indent=2)}"

        try:
            kwargs = {
                "model": self.model_name,
                "messages": [{"role": "user", "content": json_prompt}],
                "temperature": 0.0,
                "max_tokens": 2000,
            }
            if system_prompt:
                kwargs["system"] = system_prompt

            response = await self.client.messages.create(**kwargs)
            result = response.content[0].text if response.content else "{}"

            # Extract JSON from response (Claude sometimes adds markdown)
            if "```json" in result:
                result = result.split("```json")[1].split("```")[0].strip()
            elif "```" in result:
                result = result.split("```")[1].split("```")[0].strip()

            logger.debug(f"Anthropic JSON extraction: {len(result)} chars")
            return json.loads(result)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from Anthropic: {e}")
            raise
        except Exception as e:
            logger.error(f"Anthropic API error: {e}")
            raise

    def get_provider_name(self) -> str:
        """Get provider name."""
        return "anthropic"
