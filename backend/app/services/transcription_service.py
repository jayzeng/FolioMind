"""Transcription service for converting audio to text using OpenAI Whisper API."""

from pathlib import Path
from typing import Optional

from loguru import logger
from openai import AsyncOpenAI

from app.core.config import settings


class TranscriptionService:
    """Service for transcribing audio files using OpenAI Whisper API."""

    # Supported audio formats
    SUPPORTED_FORMATS = {".wav", ".mp3", ".m4a", ".ogg", ".flac", ".webm", ".mp4"}

    # Max file size: 25MB (Whisper API limit)
    MAX_FILE_SIZE = 25 * 1024 * 1024

    def __init__(self):
        """Initialize transcription service with OpenAI client."""
        if not settings.openai_api_key:
            raise ValueError("OpenAI API key is required for transcription service")

        self.client = AsyncOpenAI(api_key=settings.openai_api_key)
        self.model = settings.whisper_model
        logger.info(f"Transcription service initialized with model: {self.model}")

    async def transcribe(
        self,
        audio_path: str | Path,
        language: Optional[str] = None,
        prompt: Optional[str] = None,
        temperature: float = 0.0
    ) -> str:
        """Transcribe an audio file using OpenAI Whisper API.

        Args:
            audio_path: Path to the audio file
            language: Optional language code (e.g., "en", "es")
            prompt: Optional prompt to guide transcription
            temperature: Sampling temperature (0.0 = deterministic)

        Returns:
            Transcribed text from the audio

        Raises:
            ValueError: If file format is not supported or file is too large
            Exception: If transcription fails
        """
        audio_path = Path(audio_path)

        # Validate file exists
        if not audio_path.exists():
            raise ValueError(f"Audio file not found: {audio_path}")

        # Validate file format
        if audio_path.suffix.lower() not in self.SUPPORTED_FORMATS:
            raise ValueError(
                f"Unsupported audio format: {audio_path.suffix}. "
                f"Supported formats: {', '.join(self.SUPPORTED_FORMATS)}"
            )

        # Validate file size
        file_size = audio_path.stat().st_size
        if file_size > self.MAX_FILE_SIZE:
            raise ValueError(
                f"Audio file too large: {file_size / 1024 / 1024:.2f}MB. "
                f"Maximum size: {self.MAX_FILE_SIZE / 1024 / 1024}MB"
            )

        logger.info(
            f"Starting audio transcription | file={audio_path.name} | "
            f"size={file_size / 1024:.2f}KB | format={audio_path.suffix} | "
            f"language={language or 'auto'}"
        )

        try:
            logger.debug(f"Calling OpenAI Whisper API with model: {self.model}")

            # Open audio file and transcribe
            with open(audio_path, "rb") as audio_file:
                # Build transcription parameters
                transcription_params = {
                    "model": self.model,
                    "file": audio_file,
                    "response_format": "text",
                    "temperature": temperature,
                }

                # Add optional parameters
                if language:
                    transcription_params["language"] = language
                if prompt:
                    transcription_params["prompt"] = prompt

                # Call Whisper API
                transcript = await self.client.audio.transcriptions.create(
                    **transcription_params
                )

            # Extract text (response format is "text" so it returns string directly)
            transcribed_text = transcript if isinstance(transcript, str) else str(transcript)
            text_length = len(transcribed_text)

            logger.success(
                f"Transcription completed | transcribed_length={text_length} | "
                f"file={audio_path.name}"
            )
            logger.debug(f"Transcribed text preview: {transcribed_text[:200]}...")

            return transcribed_text.strip()

        except Exception as e:
            logger.error(f"Transcription failed: {e}")
            logger.exception("Full traceback:")
            raise Exception(f"Failed to transcribe audio: {str(e)}")

    async def transcribe_from_bytes(
        self,
        audio_bytes: bytes,
        filename: str,
        language: Optional[str] = None,
        prompt: Optional[str] = None,
        temperature: float = 0.0
    ) -> str:
        """Transcribe audio from bytes (useful for uploaded files).

        Args:
            audio_bytes: Audio file bytes
            filename: Original filename (for format detection)
            language: Optional language code (e.g., "en", "es")
            prompt: Optional prompt to guide transcription
            temperature: Sampling temperature (0.0 = deterministic)

        Returns:
            Transcribed text from the audio

        Raises:
            ValueError: If file format is not supported or file is too large
            Exception: If transcription fails
        """
        # Validate file format from filename
        file_ext = Path(filename).suffix.lower()
        if file_ext not in self.SUPPORTED_FORMATS:
            raise ValueError(
                f"Unsupported audio format: {file_ext}. "
                f"Supported formats: {', '.join(self.SUPPORTED_FORMATS)}"
            )

        # Validate file size
        file_size = len(audio_bytes)
        if file_size > self.MAX_FILE_SIZE:
            raise ValueError(
                f"Audio file too large: {file_size / 1024 / 1024:.2f}MB. "
                f"Maximum size: {self.MAX_FILE_SIZE / 1024 / 1024}MB"
            )

        logger.info(
            f"Starting audio transcription from bytes | filename={filename} | "
            f"size={file_size / 1024:.2f}KB | format={file_ext} | "
            f"language={language or 'auto'}"
        )

        try:
            logger.debug(f"Calling OpenAI Whisper API with model: {self.model}")

            # Create a tuple that mimics a file object for the API
            # Format: (filename, file_content, content_type)
            file_tuple = (filename, audio_bytes, self._get_content_type(file_ext))

            # Build transcription parameters
            transcription_params = {
                "model": self.model,
                "file": file_tuple,
                "response_format": "text",
                "temperature": temperature,
            }

            # Add optional parameters
            if language:
                transcription_params["language"] = language
            if prompt:
                transcription_params["prompt"] = prompt

            # Call Whisper API
            transcript = await self.client.audio.transcriptions.create(
                **transcription_params
            )

            # Extract text
            transcribed_text = transcript if isinstance(transcript, str) else str(transcript)
            text_length = len(transcribed_text)

            logger.success(
                f"Transcription completed | transcribed_length={text_length} | "
                f"filename={filename}"
            )
            logger.debug(f"Transcribed text preview: {transcribed_text[:200]}...")

            return transcribed_text.strip()

        except Exception as e:
            logger.error(f"Transcription failed: {e}")
            logger.exception("Full traceback:")
            raise Exception(f"Failed to transcribe audio: {str(e)}")

    @staticmethod
    def _get_content_type(file_ext: str) -> str:
        """Get content type from file extension.

        Args:
            file_ext: File extension (including dot)

        Returns:
            Content type string
        """
        content_types = {
            ".mp3": "audio/mpeg",
            ".mp4": "audio/mp4",
            ".m4a": "audio/m4a",
            ".wav": "audio/wav",
            ".ogg": "audio/ogg",
            ".flac": "audio/flac",
            ".webm": "audio/webm",
        }
        return content_types.get(file_ext.lower(), "audio/mpeg")

    @staticmethod
    def validate_file_format(filename: str) -> bool:
        """Validate if file format is supported.

        Args:
            filename: Filename to validate

        Returns:
            True if format is supported, False otherwise
        """
        file_ext = Path(filename).suffix.lower()
        return file_ext in TranscriptionService.SUPPORTED_FORMATS

    @staticmethod
    def validate_file_size(file_size: int) -> bool:
        """Validate if file size is within limits.

        Args:
            file_size: File size in bytes

        Returns:
            True if size is acceptable, False otherwise
        """
        return file_size <= TranscriptionService.MAX_FILE_SIZE
