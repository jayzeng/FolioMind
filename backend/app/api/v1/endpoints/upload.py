"""File upload endpoints for images and audio files."""

import tempfile
import time
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, File, HTTPException, UploadFile
from loguru import logger

from app.models.document import DocumentType
from app.models.upload import ErrorDetail, UploadResponse, UploadResponseWithMetadata, UploadMetadata
from app.services.classification_service import ClassificationService
from app.services.extraction_service import ExtractionService
from app.services.ocr_service import OCRService
from app.services.transcription_service import TranscriptionService

router = APIRouter()


@router.post("/upload/image", response_model=UploadResponseWithMetadata)
async def upload_image(
    file: UploadFile = File(..., description="Image file (PNG, JPG, JPEG, WEBP, GIF)")
) -> UploadResponseWithMetadata:
    """Upload an image file, perform OCR, classify, and extract fields.

    This endpoint:
    1. Validates the uploaded image file
    2. Extracts text using OpenAI Vision API (OCR)
    3. Classifies the document type
    4. Extracts structured fields
    5. Returns complete analysis with metadata

    Args:
        file: Uploaded image file

    Returns:
        Analysis results with extracted text, classification, fields, and metadata

    Raises:
        HTTPException: If file validation or processing fails
    """
    start_time = time.time()
    temp_file_path: Optional[Path] = None

    try:
        # Validate filename
        if not file.filename:
            raise HTTPException(
                status_code=400,
                detail="Filename is required"
            )

        logger.info(
            f"Image upload started | filename={file.filename} | "
            f"content_type={file.content_type}"
        )

        # Validate file format
        if not OCRService.validate_file_format(file.filename):
            logger.warning(f"Invalid image format: {file.filename}")
            raise HTTPException(
                status_code=400,
                detail={
                    "error": "InvalidFileFormat",
                    "message": f"Unsupported image format. Supported formats: {', '.join(OCRService.SUPPORTED_FORMATS)}",
                    "filename": file.filename
                }
            )

        # Read file content
        logger.debug("Reading uploaded file...")
        file_content = await file.read()
        file_size = len(file_content)

        # Validate file size
        if not OCRService.validate_file_size(file_size):
            logger.warning(f"Image file too large: {file_size / 1024 / 1024:.2f}MB")
            raise HTTPException(
                status_code=413,
                detail={
                    "error": "FileTooLarge",
                    "message": f"Image file too large. Maximum size: {OCRService.MAX_FILE_SIZE / 1024 / 1024}MB",
                    "file_size_mb": round(file_size / 1024 / 1024, 2),
                    "max_size_mb": OCRService.MAX_FILE_SIZE / 1024 / 1024
                }
            )

        logger.info(f"File validated | size={file_size / 1024:.2f}KB")

        # Step 1: Perform OCR
        logger.debug("Step 1: Performing OCR...")
        ocr_service = OCRService()

        try:
            extracted_text = await ocr_service.extract_text_from_bytes(
                image_bytes=file_content,
                filename=file.filename,
                detail="high"  # Use high detail for better accuracy
            )
        except ValueError as e:
            logger.error(f"OCR validation error: {e}")
            raise HTTPException(status_code=400, detail=str(e))
        except Exception as e:
            logger.error(f"OCR extraction failed: {e}")
            raise HTTPException(
                status_code=500,
                detail={
                    "error": "OCRFailed",
                    "message": "Failed to extract text from image",
                    "detail": str(e)
                }
            )

        if not extracted_text:
            logger.warning("No text extracted from image")
            raise HTTPException(
                status_code=422,
                detail={
                    "error": "NoTextExtracted",
                    "message": "No text could be extracted from the image. Please ensure the image contains readable text."
                }
            )

        logger.success(f"OCR completed | extracted_length={len(extracted_text)}")

        # Step 2: Classify document
        logger.debug("Step 2: Classifying document...")
        doc_type, confidence, signals = ClassificationService.classify(
            ocr_text=extracted_text
        )
        logger.debug(f"Classification: {doc_type.value} (confidence={confidence:.2%})")

        # Step 3: Extract fields
        logger.debug("Step 3: Extracting fields...")
        extraction_service = ExtractionService()
        fields = await extraction_service.extract_fields(
            ocr_text=extracted_text,
            document_type=doc_type
        )
        logger.success(f"Extraction completed | fields_count={len(fields)}")

        # Calculate processing time
        processing_time_ms = (time.time() - start_time) * 1000

        # Build response
        response = UploadResponseWithMetadata(
            extracted_text=extracted_text,
            document_type=doc_type,
            confidence=confidence,
            signals=signals,
            fields=fields,
            metadata=UploadMetadata(
                filename=file.filename,
                file_size=file_size,
                file_type=file.content_type or "image/jpeg",
                processing_time_ms=round(processing_time_ms, 2)
            )
        )

        logger.success(
            f"Image upload completed | type={doc_type.value} | "
            f"fields={len(fields)} | time={processing_time_ms:.2f}ms"
        )

        return response

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Image upload failed: {e}")
        logger.exception("Full traceback:")
        raise HTTPException(
            status_code=500,
            detail={
                "error": "ProcessingFailed",
                "message": "Failed to process image upload",
                "detail": str(e)
            }
        )

    finally:
        # Clean up temporary file if created
        if temp_file_path and temp_file_path.exists():
            try:
                temp_file_path.unlink()
                logger.debug(f"Cleaned up temp file: {temp_file_path}")
            except Exception as e:
                logger.warning(f"Failed to clean up temp file: {e}")


@router.post("/upload/audio", response_model=UploadResponseWithMetadata)
async def upload_audio(
    file: UploadFile = File(..., description="Audio file (WAV, MP3, M4A, OGG, FLAC, WEBM, MP4)"),
    language: Optional[str] = None
) -> UploadResponseWithMetadata:
    """Upload an audio file, transcribe, classify, and extract fields.

    This endpoint:
    1. Validates the uploaded audio file
    2. Transcribes audio using OpenAI Whisper API
    3. Classifies the document type based on transcription
    4. Extracts structured fields
    5. Returns complete analysis with metadata

    Args:
        file: Uploaded audio file
        language: Optional language code (e.g., "en", "es") for transcription

    Returns:
        Analysis results with transcription, classification, fields, and metadata

    Raises:
        HTTPException: If file validation or processing fails
    """
    start_time = time.time()
    temp_file_path: Optional[Path] = None

    try:
        # Validate filename
        if not file.filename:
            raise HTTPException(
                status_code=400,
                detail="Filename is required"
            )

        logger.info(
            f"Audio upload started | filename={file.filename} | "
            f"content_type={file.content_type} | language={language or 'auto'}"
        )

        # Validate file format
        if not TranscriptionService.validate_file_format(file.filename):
            logger.warning(f"Invalid audio format: {file.filename}")
            raise HTTPException(
                status_code=400,
                detail={
                    "error": "InvalidFileFormat",
                    "message": f"Unsupported audio format. Supported formats: {', '.join(TranscriptionService.SUPPORTED_FORMATS)}",
                    "filename": file.filename
                }
            )

        # Read file content
        logger.debug("Reading uploaded file...")
        file_content = await file.read()
        file_size = len(file_content)

        # Validate file size
        if not TranscriptionService.validate_file_size(file_size):
            logger.warning(f"Audio file too large: {file_size / 1024 / 1024:.2f}MB")
            raise HTTPException(
                status_code=413,
                detail={
                    "error": "FileTooLarge",
                    "message": f"Audio file too large. Maximum size: {TranscriptionService.MAX_FILE_SIZE / 1024 / 1024}MB",
                    "file_size_mb": round(file_size / 1024 / 1024, 2),
                    "max_size_mb": TranscriptionService.MAX_FILE_SIZE / 1024 / 1024
                }
            )

        logger.info(f"File validated | size={file_size / 1024:.2f}KB")

        # Step 1: Transcribe audio
        logger.debug("Step 1: Transcribing audio...")
        transcription_service = TranscriptionService()

        try:
            transcribed_text = await transcription_service.transcribe_from_bytes(
                audio_bytes=file_content,
                filename=file.filename,
                language=language,
                temperature=0.0  # Deterministic transcription
            )
        except ValueError as e:
            logger.error(f"Transcription validation error: {e}")
            raise HTTPException(status_code=400, detail=str(e))
        except Exception as e:
            logger.error(f"Transcription failed: {e}")
            raise HTTPException(
                status_code=500,
                detail={
                    "error": "TranscriptionFailed",
                    "message": "Failed to transcribe audio",
                    "detail": str(e)
                }
            )

        if not transcribed_text:
            logger.warning("No text transcribed from audio")
            raise HTTPException(
                status_code=422,
                detail={
                    "error": "NoTextTranscribed",
                    "message": "No text could be transcribed from the audio. Please ensure the audio contains speech."
                }
            )

        logger.success(f"Transcription completed | transcribed_length={len(transcribed_text)}")

        # Step 2: Classify document
        logger.debug("Step 2: Classifying document...")
        doc_type, confidence, signals = ClassificationService.classify(
            ocr_text=transcribed_text
        )
        logger.debug(f"Classification: {doc_type.value} (confidence={confidence:.2%})")

        # Step 3: Extract fields
        logger.debug("Step 3: Extracting fields...")
        extraction_service = ExtractionService()
        fields = await extraction_service.extract_fields(
            ocr_text=transcribed_text,
            document_type=doc_type
        )
        logger.success(f"Extraction completed | fields_count={len(fields)}")

        # Calculate processing time
        processing_time_ms = (time.time() - start_time) * 1000

        # Build response
        response = UploadResponseWithMetadata(
            extracted_text=transcribed_text,
            document_type=doc_type,
            confidence=confidence,
            signals=signals,
            fields=fields,
            metadata=UploadMetadata(
                filename=file.filename,
                file_size=file_size,
                file_type=file.content_type or "audio/mpeg",
                processing_time_ms=round(processing_time_ms, 2)
            )
        )

        logger.success(
            f"Audio upload completed | type={doc_type.value} | "
            f"fields={len(fields)} | time={processing_time_ms:.2f}ms"
        )

        return response

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Audio upload failed: {e}")
        logger.exception("Full traceback:")
        raise HTTPException(
            status_code=500,
            detail={
                "error": "ProcessingFailed",
                "message": "Failed to process audio upload",
                "detail": str(e)
            }
        )

    finally:
        # Clean up temporary file if created
        if temp_file_path and temp_file_path.exists():
            try:
                temp_file_path.unlink()
                logger.debug(f"Cleaned up temp file: {temp_file_path}")
            except Exception as e:
                logger.warning(f"Failed to clean up temp file: {e}")
