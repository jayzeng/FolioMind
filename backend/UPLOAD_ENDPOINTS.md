# Upload Endpoints Documentation

This document describes the file upload endpoints for images and audio files with automatic OCR/transcription, classification, and field extraction.

## Overview

The upload endpoints provide a complete pipeline for processing document files:

1. **Image Upload** (`/api/v1/upload/image`): Upload images → OCR → Classify → Extract fields
2. **Audio Upload** (`/api/v1/upload/audio`): Upload audio → Transcribe → Classify → Extract fields

Both endpoints return comprehensive analysis results including extracted text, document classification, structured fields, and metadata.

## Endpoints

### POST /api/v1/upload/image

Upload an image file for OCR, classification, and field extraction.

**Request:**
- Method: `POST`
- Content-Type: `multipart/form-data`
- Body: Form data with `file` field containing the image

**Supported Formats:**
- PNG (`.png`)
- JPEG (`.jpg`, `.jpeg`)
- WebP (`.webp`)
- GIF (`.gif`)

**File Size Limit:** 10 MB

**Response:**
```json
{
  "extracted_text": "CVS Pharmacy\nReceipt #12345\nAdvil $12.99\nTotal: $12.99",
  "document_type": "receipt",
  "confidence": 0.95,
  "signals": {
    "promotional": false,
    "receipt": true,
    "bill": false,
    "insurance_card": false,
    "credit_card": false,
    "letter": false,
    "details": {}
  },
  "fields": [
    {
      "key": "transaction_id",
      "value": "12345",
      "confidence": 0.95,
      "source": "pattern"
    },
    {
      "key": "total_amount",
      "value": "$12.99",
      "confidence": 0.95,
      "source": "pattern"
    }
  ],
  "metadata": {
    "filename": "receipt.jpg",
    "file_size": 245760,
    "file_type": "image/jpeg",
    "processing_time_ms": 1250.5
  }
}
```

**cURL Example:**
```bash
curl -X POST "http://localhost:8000/api/v1/upload/image" \
  -H "accept: application/json" \
  -F "file=@receipt.jpg"
```

**Python Example:**
```python
import httpx

async with httpx.AsyncClient() as client:
    with open("receipt.jpg", "rb") as f:
        files = {"file": ("receipt.jpg", f, "image/jpeg")}
        response = await client.post(
            "http://localhost:8000/api/v1/upload/image",
            files=files
        )
    result = response.json()
    print(f"Document Type: {result['document_type']}")
    print(f"Extracted Text: {result['extracted_text']}")
```

---

### POST /api/v1/upload/audio

Upload an audio file for transcription, classification, and field extraction.

**Request:**
- Method: `POST`
- Content-Type: `multipart/form-data`
- Body: Form data with `file` field containing the audio
- Query Parameters:
  - `language` (optional): Language code (e.g., "en", "es", "fr")

**Supported Formats:**
- MP3 (`.mp3`)
- WAV (`.wav`)
- M4A (`.m4a`)
- OGG (`.ogg`)
- FLAC (`.flac`)
- WebM (`.webm`)
- MP4 (`.mp4`)

**File Size Limit:** 25 MB

**Response:**
```json
{
  "extracted_text": "This is a promotional message. Get fifty dollars when you open an account by December twelfth.",
  "document_type": "promotional",
  "confidence": 0.92,
  "signals": {
    "promotional": true,
    "receipt": false,
    "bill": false,
    "insurance_card": false,
    "credit_card": false,
    "letter": false,
    "details": {
      "promotional": {
        "signal_count": 3,
        "has_promo_code": false,
        "has_conditional_offer": true
      }
    }
  },
  "fields": [
    {
      "key": "offer_amount",
      "value": "$50",
      "confidence": 0.90,
      "source": "pattern"
    }
  ],
  "metadata": {
    "filename": "promo_message.mp3",
    "file_size": 512000,
    "file_type": "audio/mpeg",
    "processing_time_ms": 3420.8
  }
}
```

**cURL Example:**
```bash
curl -X POST "http://localhost:8000/api/v1/upload/audio?language=en" \
  -H "accept: application/json" \
  -F "file=@recording.mp3"
```

**Python Example:**
```python
import httpx

async with httpx.AsyncClient() as client:
    with open("recording.mp3", "rb") as f:
        files = {"file": ("recording.mp3", f, "audio/mpeg")}
        response = await client.post(
            "http://localhost:8000/api/v1/upload/audio",
            files=files,
            params={"language": "en"}
        )
    result = response.json()
    print(f"Document Type: {result['document_type']}")
    print(f"Transcription: {result['extracted_text']}")
```

---

## Error Responses

### 400 Bad Request - Invalid File Format
```json
{
  "detail": {
    "error": "InvalidFileFormat",
    "message": "Unsupported image format. Supported formats: .png, .jpg, .jpeg, .webp, .gif",
    "filename": "document.pdf"
  }
}
```

### 413 Payload Too Large - File Too Large
```json
{
  "detail": {
    "error": "FileTooLarge",
    "message": "Image file too large. Maximum size: 10MB",
    "file_size_mb": 12.5,
    "max_size_mb": 10
  }
}
```

### 422 Unprocessable Entity - No Text Extracted
```json
{
  "detail": {
    "error": "NoTextExtracted",
    "message": "No text could be extracted from the image. Please ensure the image contains readable text."
  }
}
```

### 500 Internal Server Error - Processing Failed
```json
{
  "detail": {
    "error": "OCRFailed",
    "message": "Failed to extract text from image",
    "detail": "OpenAI API error: Rate limit exceeded"
  }
}
```

---

## Configuration

The upload endpoints use the following configuration from environment variables:

```bash
# Required: OpenAI API key for Vision and Whisper APIs
OPENAI_API_KEY=sk-...

# Optional: Model configurations
OPENAI_VISION_MODEL=gpt-4o  # Default: gpt-4o
WHISPER_MODEL=whisper-1     # Default: whisper-1
```

Update your `.env` file:
```bash
OPENAI_API_KEY=your-api-key-here
OPENAI_VISION_MODEL=gpt-4o
WHISPER_MODEL=whisper-1
```

---

## Processing Pipeline

### Image Upload Pipeline

```
1. Validate file format and size
   ↓
2. OCR with OpenAI Vision API (gpt-4o)
   ↓
3. Classify document type
   ↓
4. Extract structured fields
   ↓
5. Return results + metadata
```

### Audio Upload Pipeline

```
1. Validate file format and size
   ↓
2. Transcribe with OpenAI Whisper API
   ↓
3. Classify document type from transcription
   ↓
4. Extract structured fields
   ↓
5. Return results + metadata
```

---

## Document Types

The endpoints classify documents into the following types:

- `receipt` - Proof of purchase transactions
- `promotional` - Marketing materials and offers
- `billStatement` - Recurring service bills
- `creditCard` - Physical payment cards
- `insuranceCard` - Health/dental/vision insurance cards
- `letter` - Personal or business correspondence
- `generic` - Other documents

---

## Field Extraction

Fields are automatically extracted based on document type:

### Receipt Fields
- `transaction_id` - Receipt/order number
- `total_amount` - Total payment amount
- `date` - Transaction date
- `amount` - Individual amounts

### Promotional Fields
- `promo_code` - Promotional code
- `offer_amount` - Offer value
- `offer_expiry` - Expiration date

### Bill Statement Fields
- `amount_due` - Amount due
- `due_date` - Payment due date
- `account_number` - Account number

### Common Fields
- `date` - Dates in various formats
- `email` - Email addresses
- `phone` - Phone numbers
- `amount` - Dollar amounts

---

## Testing

Use the provided test script:

```bash
# Test image upload
python examples/test_upload_endpoints.py receipt.jpg

# Test audio upload
python examples/test_upload_endpoints.py recording.mp3 en

# Test error cases
python examples/test_upload_endpoints.py
```

---

## Performance

**Typical Processing Times:**

- **Image Upload (OCR)**: 1-3 seconds
  - Small images (< 500KB): ~1-2 seconds
  - Large images (> 2MB): ~2-4 seconds

- **Audio Upload (Transcription)**: 2-10 seconds
  - Short audio (< 1 min): ~2-4 seconds
  - Long audio (> 5 min): ~5-10 seconds

**Note:** Processing time depends on:
- File size
- OpenAI API response time
- Network latency
- Document complexity

---

## Best Practices

1. **Image Quality**: Use high-resolution images for better OCR accuracy
2. **File Size**: Compress large files before upload to improve performance
3. **Language**: Specify language code for audio transcription for better accuracy
4. **Error Handling**: Always handle errors gracefully in your client code
5. **Timeouts**: Set appropriate timeouts (60s for images, 120s for audio)

---

## Security Considerations

1. **File Validation**: All files are validated for format and size
2. **Temporary Storage**: Files are not permanently stored
3. **API Keys**: OpenAI API key is securely managed via environment variables
4. **Rate Limiting**: Consider implementing rate limiting for production use

---

## Troubleshooting

### Issue: "OpenAI API key is required"
**Solution:** Set `OPENAI_API_KEY` in your `.env` file

### Issue: "Unsupported image format"
**Solution:** Convert to supported format (PNG, JPG, JPEG, WEBP, GIF)

### Issue: "File too large"
**Solution:**
- For images: Compress to < 10MB
- For audio: Compress to < 25MB or split into smaller files

### Issue: "No text extracted/transcribed"
**Solution:**
- For images: Ensure image is clear and contains visible text
- For audio: Ensure audio contains clear speech

### Issue: Slow processing
**Solution:**
- Reduce file size
- Use lower quality for images (set `detail="low"` in OCR service)
- Check OpenAI API status

---

## API Reference

### Services

- **OCRService**: `/app/services/ocr_service.py`
  - Extracts text from images using OpenAI Vision API
  - Supports PNG, JPG, JPEG, WebP, GIF
  - Max file size: 10MB

- **TranscriptionService**: `/app/services/transcription_service.py`
  - Transcribes audio using OpenAI Whisper API
  - Supports WAV, MP3, M4A, OGG, FLAC, WebM, MP4
  - Max file size: 25MB

### Models

- **UploadResponse**: Base response model
- **UploadResponseWithMetadata**: Response with file metadata
- **UploadMetadata**: File metadata (filename, size, type, processing time)

### Endpoints

- **POST /api/v1/upload/image**: Upload and process image
- **POST /api/v1/upload/audio**: Upload and process audio

---

## Future Enhancements

Potential improvements:

1. Batch upload support
2. Asynchronous processing with webhooks
3. Support for additional file formats (PDF, TIFF)
4. Custom OCR/transcription prompts
5. Result caching
6. File storage options (S3, local storage)
7. Advanced error recovery
8. Confidence threshold configuration

---

## Support

For issues or questions:
1. Check this documentation
2. Review the test script: `examples/test_upload_endpoints.py`
3. Check server logs for detailed error messages
4. Review OpenAI API documentation for Vision and Whisper APIs
