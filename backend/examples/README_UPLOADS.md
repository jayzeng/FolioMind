# Upload Testing Examples

This directory contains scripts for testing the FolioMind upload endpoints.

## Quick Start

### 1. Generate a Sample Receipt Image

```bash
python examples/generate_sample_receipt.py
```

This creates `sample_receipt.png` - a realistic receipt image with text.

### 2. Test the Upload Endpoints

```bash
# Test with generated samples (image + audio)
python examples/upload_media_test.py

# Test with a specific image
python examples/upload_media_test.py --photo-path sample_receipt.png

# Test with a real receipt photo
python examples/upload_media_test.py --photo-path ~/Downloads/my_receipt.jpg

# Test only audio (skip image)
python examples/upload_media_test.py --skip-photo --audio-path recording.mp3
```

## Available Scripts

### `generate_sample_receipt.py`
Generates a sample CVS receipt image with text content suitable for OCR testing.

**Output**: A 400x600 PNG with:
- Store name and number
- Receipt number
- Items with prices
- Subtotal, tax, total
- Payment info (VISA card)

**Usage**:
```bash
# Generate to default location (sample_receipt.png)
python examples/generate_sample_receipt.py

# Generate to custom location
python examples/generate_sample_receipt.py my_receipt.png
```

### `upload_media_test.py`
Uploads images and audio files to test the classification pipeline.

**Features**:
- Auto-generates sample image and audio if not provided
- Tests both `/api/v1/upload/image` and `/api/v1/upload/audio`
- Shows full response including classification and extracted fields

**Usage**:
```bash
# Test with auto-generated samples
python examples/upload_media_test.py

# Test with real files
python examples/upload_media_test.py \
    --photo-path ~/receipts/cvs_receipt.jpg \
    --audio-path ~/recordings/bill_note.m4a

# Custom endpoint URLs
python examples/upload_media_test.py \
    --base-url https://api.foliomind.com \
    --photo-endpoint /v1/classify/image

# Skip image upload
python examples/upload_media_test.py --skip-photo

# Skip audio upload
python examples/upload_media_test.py --skip-audio
```

**Options**:
- `--base-url` - API base URL (default: http://localhost:8000)
- `--photo-endpoint` - Image upload endpoint (default: /api/v1/upload/image)
- `--audio-endpoint` - Audio upload endpoint (default: /api/v1/upload/audio)
- `--photo-path` - Path to image file to upload
- `--audio-path` - Path to audio file to upload
- `--file-field` - Form field name for file (default: file)
- `--api-key` - Bearer token if authentication required
- `--timeout` - Request timeout in seconds (default: 30)
- `--metadata` - Extra form fields (can specify multiple times)
- `--skip-photo` - Skip image upload
- `--skip-audio` - Skip audio upload

### `test_upload_endpoints.py`
Comprehensive test script with detailed validation.

**Usage**:
```bash
# Test with default generated files
python examples/test_upload_endpoints.py

# Test with specific files
python examples/test_upload_endpoints.py sample_receipt.png
python examples/test_upload_endpoints.py recording.mp3 en
```

## Expected Results

### Image Upload (Receipt)

**Input**: `sample_receipt.png` (CVS receipt)

**Expected Classification**: `receipt`

**Expected Fields**:
- `transaction_id`: "456789"
- `total_amount`: "$28.85"
- `date`: "11/30/2025"

**Example Response**:
```json
{
  "extracted_text": "CVS PHARMACY\nStore #1234\nReceipt #456789...",
  "document_type": "receipt",
  "confidence": 0.95,
  "fields": [
    {"key": "transaction_id", "value": "456789", "confidence": 0.95},
    {"key": "total_amount", "value": "$28.85", "confidence": 0.95}
  ]
}
```

### Audio Upload (Voice Note)

**Input**: `sample-tone.wav` (generated audio tone)

**Expected Classification**: `generic` (no meaningful speech)

**Expected Fields**: `[]` (empty)

For real audio with speech content, you'll get proper classification and fields based on what was said.

## Troubleshooting

### "Image parse error" from OpenAI

The image must be:
- Valid format (PNG, JPG, JPEG, WebP, GIF)
- Readable image data
- Not corrupt
- Contains visible content (not blank or 1x1 pixel)

**Solution**: Use the `generate_sample_receipt.py` script to create a valid test image.

### "File too large" error

**Image files**: Max 10MB
**Audio files**: Max 25MB

**Solution**: Compress or resize your files before uploading.

### 404 Not Found

Make sure the server is running:
```bash
cd /Users/jay/designland/FolioMind/backend
python main.py
```

### No text extracted from image

The image may be:
- Too blurry
- Text too small
- Poor contrast
- Rotated at wrong angle

**Solution**: Use a clear, well-lit image with readable text.

### Audio transcription returns "Oh" or gibberish

The generated audio tone is just a sine wave (440Hz), not actual speech.

**Solution**: Use a real audio recording with speech content, or test with:
```bash
# Record a quick voice note on Mac
# Then test with it
python examples/upload_media_test.py --audio-path ~/Desktop/voice_note.m4a
```

## Sample Files

### Generate Receipt Image
```bash
python examples/generate_sample_receipt.py receipt.png
```

### Generate More Sample Types

**Promotional Mailer**:
```python
# Create a promotional image with offers
# (Add similar PIL code with promotional text)
```

**Bill/Invoice**:
```python
# Create a utility bill image
# (Add similar PIL code with bill text)
```

## Integration Examples

### Using httpx (Async)
```python
import httpx
from pathlib import Path

async def upload_receipt(file_path: Path):
    async with httpx.AsyncClient() as client:
        with open(file_path, "rb") as f:
            files = {"file": (file_path.name, f, "image/jpeg")}
            response = await client.post(
                "http://localhost:8000/api/v1/upload/image",
                files=files
            )
        return response.json()

# Usage
result = await upload_receipt(Path("receipt.jpg"))
print(f"Document type: {result['document_type']}")
print(f"Confidence: {result['confidence']}")
```

### Using requests (Sync)
```python
import requests

def upload_receipt(file_path):
    with open(file_path, "rb") as f:
        files = {"file": f}
        response = requests.post(
            "http://localhost:8000/api/v1/upload/image",
            files=files
        )
    return response.json()

result = upload_receipt("receipt.jpg")
```

### Using cURL
```bash
# Upload image
curl -X POST "http://localhost:8000/api/v1/upload/image" \
  -F "file=@sample_receipt.png" \
  | jq '.'

# Upload audio
curl -X POST "http://localhost:8000/api/v1/upload/audio" \
  -F "file=@recording.mp3" \
  | jq '.'
```

## Performance Tips

1. **Image Resolution**: 1000-2000px width is optimal. Larger images take longer without improving OCR quality.

2. **Audio Quality**: 16kHz mono is sufficient. Higher quality doesn't improve transcription but increases processing time.

3. **Batch Processing**: Upload files sequentially to avoid rate limits. For parallel processing, implement proper rate limiting.

4. **File Formats**:
   - Images: PNG or JPG (avoid GIF for photos)
   - Audio: M4A or MP3 for compressed, WAV for best quality

## See Also

- [Upload Endpoints Documentation](../UPLOAD_ENDPOINTS.md)
- [Upload Examples](../examples/UPLOAD_EXAMPLES.md)
- [Main README](../README.md)
- [API Documentation](http://localhost:8000/docs)
