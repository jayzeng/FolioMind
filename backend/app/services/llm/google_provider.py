"""Google Gemini LLM provider implementation."""

import json
import logging
from typing import Any

import google.generativeai as genai

from app.services.llm.base import LLMProvider

logger = logging.getLogger(__name__)


class GoogleProvider(LLMProvider):
    """Google Gemini provider implementation."""

    def __init__(self, api_key: str, model_name: str):
        """Initialize Google provider.

        Args:
            api_key: Google API key
            model_name: Model name (e.g., "gemini-pro")
        """
        super().__init__(api_key, model_name)
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel(model_name)
        logger.info(f"Initialized Google provider with model: {model_name}")

    async def complete(
        self,
        prompt: str,
        system_prompt: str | None = None,
        temperature: float = 0.0,
        max_tokens: int = 1000,
    ) -> str:
        """Generate a completion using Google Gemini API.

        Args:
            prompt: User prompt
            system_prompt: Optional system prompt (prepended to prompt)
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate

        Returns:
            Generated text completion
        """
        try:
            # Gemini doesn't have separate system prompt, so prepend it
            full_prompt = prompt
            if system_prompt:
                full_prompt = f"{system_prompt}\n\n{prompt}"

            generation_config = genai.types.GenerationConfig(
                temperature=temperature,
                max_output_tokens=max_tokens,
            )

            response = await self.model.generate_content_async(
                full_prompt, generation_config=generation_config
            )
            result = response.text if response.text else ""
            logger.debug(f"Google completion generated: {len(result)} chars")
            return result
        except Exception as e:
            logger.error(f"Google API error: {e}")
            raise

    async def extract_json(
        self,
        prompt: str,
        system_prompt: str | None = None,
        schema: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Extract structured JSON using Google Gemini API.

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

        full_prompt = json_prompt
        if system_prompt:
            full_prompt = f"{system_prompt}\n\n{json_prompt}"

        try:
            generation_config = genai.types.GenerationConfig(
                temperature=0.0,
                max_output_tokens=2000,
            )

            response = await self.model.generate_content_async(
                full_prompt, generation_config=generation_config
            )
            result = response.text if response.text else "{}"

            # Extract JSON from response (may have markdown)
            if "```json" in result:
                result = result.split("```json")[1].split("```")[0].strip()
            elif "```" in result:
                result = result.split("```")[1].split("```")[0].strip()

            logger.debug(f"Google JSON extraction: {len(result)} chars")
            return json.loads(result)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from Google: {e}")
            raise
        except Exception as e:
            logger.error(f"Google API error: {e}")
            raise

    def get_provider_name(self) -> str:
        """Get provider name."""
        return "google"
