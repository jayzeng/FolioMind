"""OCR service for extracting text from images using OpenAI Vision API."""

import base64
from pathlib import Path
from typing import Optional

from loguru import logger
from openai import AsyncOpenAI

from app.core.config import settings


class OCRService:
    """Service for extracting text from images using OpenAI Vision API."""

    # Supported image formats
    SUPPORTED_FORMATS = {".png", ".jpg", ".jpeg", ".webp", ".gif"}

    # Max file size: 10MB
    MAX_FILE_SIZE = 10 * 1024 * 1024

    def __init__(self):
        """Initialize OCR service with OpenAI client."""
        if not settings.openai_api_key:
            raise ValueError("OpenAI API key is required for OCR service")

        self.client = AsyncOpenAI(api_key=settings.openai_api_key)
        self.model = settings.openai_vision_model
        logger.info(f"OCR service initialized with model: {self.model}")

    async def extract_text(
        self,
        image_path: str | Path,
        detail: str = "high"
    ) -> str:
        """Extract text from an image using OpenAI Vision API.

        Args:
            image_path: Path to the image file
            detail: Vision detail level ("low", "high", "auto")

        Returns:
            Extracted text from the image

        Raises:
            ValueError: If file format is not supported or file is too large
            Exception: If OCR extraction fails
        """
        image_path = Path(image_path)

        # Validate file exists
        if not image_path.exists():
            raise ValueError(f"Image file not found: {image_path}")

        # Validate file format
        if image_path.suffix.lower() not in self.SUPPORTED_FORMATS:
            raise ValueError(
                f"Unsupported image format: {image_path.suffix}. "
                f"Supported formats: {', '.join(self.SUPPORTED_FORMATS)}"
            )

        # Validate file size
        file_size = image_path.stat().st_size
        if file_size > self.MAX_FILE_SIZE:
            raise ValueError(
                f"Image file too large: {file_size / 1024 / 1024:.2f}MB. "
                f"Maximum size: {self.MAX_FILE_SIZE / 1024 / 1024}MB"
            )

        logger.info(
            f"Starting OCR extraction | file={image_path.name} | "
            f"size={file_size / 1024:.2f}KB | format={image_path.suffix}"
        )

        try:
            # Read and encode image
            logger.debug("Reading and encoding image...")
            image_data = image_path.read_bytes()
            base64_image = base64.b64encode(image_data).decode("utf-8")

            # Determine image MIME type
            mime_type = self._get_mime_type(image_path.suffix.lower())

            logger.debug(f"Calling OpenAI Vision API with model: {self.model}")

            # Call OpenAI Vision API
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are an expert OCR system. Extract ALL text from the image "
                            "exactly as it appears, preserving layout and formatting. "
                            "Include numbers, dates, amounts, and any other text visible. "
                            "Do not add explanations or commentary - only return the extracted text."
                        )
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": "Extract all text from this image:"
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:{mime_type};base64,{base64_image}",
                                    "detail": detail
                                }
                            }
                        ]
                    }
                ],
                max_tokens=4096,
                temperature=0.0,  # Deterministic for OCR
            )

            # Extract text from response
            extracted_text = response.choices[0].message.content or ""
            text_length = len(extracted_text)

            logger.success(
                f"OCR extraction completed | extracted_length={text_length} | "
                f"tokens_used={response.usage.total_tokens if response.usage else 'N/A'}"
            )
            logger.debug(f"Extracted text preview: {extracted_text[:200]}...")

            return extracted_text.strip()

        except Exception as e:
            logger.error(f"OCR extraction failed: {e}")
            logger.exception("Full traceback:")
            raise Exception(f"Failed to extract text from image: {str(e)}")

    async def extract_text_from_bytes(
        self,
        image_bytes: bytes,
        filename: str,
        detail: str = "high"
    ) -> str:
        """Extract text from image bytes (useful for uploaded files).

        Args:
            image_bytes: Image file bytes
            filename: Original filename (for format detection)
            detail: Vision detail level ("low", "high", "auto")

        Returns:
            Extracted text from the image

        Raises:
            ValueError: If file format is not supported or file is too large
            Exception: If OCR extraction fails
        """
        # Validate file format from filename
        file_ext = Path(filename).suffix.lower()
        if file_ext not in self.SUPPORTED_FORMATS:
            raise ValueError(
                f"Unsupported image format: {file_ext}. "
                f"Supported formats: {', '.join(self.SUPPORTED_FORMATS)}"
            )

        # Validate file size
        file_size = len(image_bytes)
        if file_size > self.MAX_FILE_SIZE:
            raise ValueError(
                f"Image file too large: {file_size / 1024 / 1024:.2f}MB. "
                f"Maximum size: {self.MAX_FILE_SIZE / 1024 / 1024}MB"
            )

        logger.info(
            f"Starting OCR extraction from bytes | filename={filename} | "
            f"size={file_size / 1024:.2f}KB | format={file_ext}"
        )

        try:
            # Encode image
            logger.debug("Encoding image bytes...")
            base64_image = base64.b64encode(image_bytes).decode("utf-8")

            # Determine image MIME type
            mime_type = self._get_mime_type(file_ext)

            logger.debug(f"Calling OpenAI Vision API with model: {self.model}")

            # Call OpenAI Vision API
            response = await self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are an expert OCR system. Extract ALL text from the image "
                            "exactly as it appears, preserving layout and formatting. "
                            "Include numbers, dates, amounts, and any other text visible. "
                            "Do not add explanations or commentary - only return the extracted text."
                        )
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": "Extract all text from this image:"
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:{mime_type};base64,{base64_image}",
                                    "detail": detail
                                }
                            }
                        ]
                    }
                ],
                max_tokens=4096,
                temperature=0.0,
            )

            # Extract text from response
            extracted_text = response.choices[0].message.content or ""
            text_length = len(extracted_text)

            logger.success(
                f"OCR extraction completed | extracted_length={text_length} | "
                f"tokens_used={response.usage.total_tokens if response.usage else 'N/A'}"
            )
            logger.debug(f"Extracted text preview: {extracted_text[:200]}...")

            return extracted_text.strip()

        except Exception as e:
            logger.error(f"OCR extraction failed: {e}")
            logger.exception("Full traceback:")
            raise Exception(f"Failed to extract text from image: {str(e)}")

    @staticmethod
    def _get_mime_type(file_ext: str) -> str:
        """Get MIME type from file extension.

        Args:
            file_ext: File extension (including dot)

        Returns:
            MIME type string
        """
        mime_types = {
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".webp": "image/webp",
            ".gif": "image/gif",
        }
        return mime_types.get(file_ext.lower(), "image/jpeg")

    @staticmethod
    def validate_file_format(filename: str) -> bool:
        """Validate if file format is supported.

        Args:
            filename: Filename to validate

        Returns:
            True if format is supported, False otherwise
        """
        file_ext = Path(filename).suffix.lower()
        return file_ext in OCRService.SUPPORTED_FORMATS

    @staticmethod
    def validate_file_size(file_size: int) -> bool:
        """Validate if file size is within limits.

        Args:
            file_size: File size in bytes

        Returns:
            True if size is acceptable, False otherwise
        """
        return file_size <= OCRService.MAX_FILE_SIZE
