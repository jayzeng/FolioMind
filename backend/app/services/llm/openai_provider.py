"""OpenAI LLM provider implementation."""

import json
from typing import Any

from loguru import logger
from openai import AsyncOpenAI

from app.services.llm.base import LLMProvider


class OpenAIProvider(LLMProvider):
    """OpenAI GPT provider implementation."""

    def __init__(self, api_key: str, model_name: str):
        """Initialize OpenAI provider.

        Args:
            api_key: OpenAI API key
            model_name: Model name (e.g., "gpt-4-turbo-preview")
        """
        super().__init__(api_key, model_name)
        self.client = AsyncOpenAI(api_key=api_key)
        logger.info(f"Initialized OpenAI provider | model={model_name}")

    async def complete(
        self,
        prompt: str,
        system_prompt: str | None = None,
        temperature: float = 0.0,
        max_tokens: int = 1000,
    ) -> str:
        """Generate a completion using OpenAI API.

        Args:
            prompt: User prompt
            system_prompt: Optional system prompt
            temperature: Sampling temperature
            max_tokens: Maximum tokens to generate

        Returns:
            Generated text completion
        """
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        try:
            logger.debug(
                f"OpenAI completion request | model={self.model_name} | "
                f"temp={temperature} | max_tokens={max_tokens} | "
                f"prompt_length={len(prompt)}"
            )
            response = await self.client.chat.completions.create(
                model=self.model_name,
                messages=messages,
                temperature=temperature,
                max_tokens=max_tokens,
            )
            result = response.choices[0].message.content or ""
            logger.success(
                f"OpenAI completion | result_length={len(result)} | "
                f"tokens_used={response.usage.total_tokens if response.usage else 'unknown'}"
            )
            return result
        except Exception as e:
            logger.error(f"OpenAI API error: {e}")
            logger.exception("Full traceback:")
            raise

    async def extract_json(
        self,
        prompt: str,
        system_prompt: str | None = None,
        schema: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Extract structured JSON using OpenAI API.

        Args:
            prompt: User prompt with text to analyze
            system_prompt: Optional system prompt
            schema: Optional JSON schema (not enforced by OpenAI)

        Returns:
            Parsed JSON object
        """
        # Enhance prompt to request JSON output
        json_prompt = f"{prompt}\n\nRespond with valid JSON only, no additional text."
        if schema:
            json_prompt += f"\n\nJSON Schema:\n{json.dumps(schema, indent=2)}"

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": json_prompt})

        try:
            logger.debug(
                f"OpenAI JSON extraction request | model={self.model_name} | "
                f"prompt_length={len(prompt)}"
            )
            response = await self.client.chat.completions.create(
                model=self.model_name,
                messages=messages,
                temperature=0.0,
                response_format={"type": "json_object"},
            )
            result = response.choices[0].message.content or "{}"
            parsed = json.loads(result)
            logger.success(
                f"OpenAI JSON extraction | result_size={len(result)} chars | "
                f"keys={list(parsed.keys())} | "
                f"tokens_used={response.usage.total_tokens if response.usage else 'unknown'}"
            )
            return parsed
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse JSON from OpenAI: {e}")
            logger.error(f"Raw response: {result if 'result' in locals() else 'N/A'}")
            raise
        except Exception as e:
            logger.error(f"OpenAI API error: {e}")
            logger.exception("Full traceback:")
            raise

    def get_provider_name(self) -> str:
        """Get provider name."""
        return "openai"
