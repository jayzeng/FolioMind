# Test Upload Script

This directory contains the standalone test script for testing the FolioMind document classification API with example files.

## Overview

The `test_upload.py` script simulates uploading images and audio files to the API by:
1. Extracting text from files (using mock OCR/transcription)
2. Sending the text to the classification API
3. Extracting fields from the classified documents
4. Running full analysis pipeline

## Features

- **Mock OCR/Transcription**: Simulates text extraction from images and audio files
- **Comprehensive Testing**: Tests all document types (promotional, receipt, bill, insurance, letter, etc.)
- **Beautiful Logging**: Uses loguru for colored, structured logging
- **Full API Coverage**: Tests classify, extract, and analyze endpoints

## Prerequisites

1. **Install dependencies**:
   ```bash
   cd /Users/jay/designland/FolioMind/backend
   pip install -e .
   ```

2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env and add your OpenAI API key:
   # OPENAI_API_KEY=your-key-here
   ```

3. **Start the API server**:
   ```bash
   python main.py
   ```

   The server should start on http://localhost:8000

## Running the Tests

### Basic Usage

```bash
cd /Users/jay/designland/FolioMind/backend
python scripts/test_upload.py
```

### What It Tests

The script tests 9 different document scenarios:

**Images/PDFs:**
1. WA529 Promotional Mailer → Expected: `promotional`
2. CVS Receipt → Expected: `receipt`
3. Credit Card Offer → Expected: `promotional`
4. Utility Bill → Expected: `billStatement`
5. Insurance Card → Expected: `insuranceCard`
6. Business Letter → Expected: `letter`

**Audio Files:**
7. Receipt Voice Note → Expected: `receipt`
8. Bill Voice Note → Expected: `billStatement`
9. Promo Voice Note → Expected: `promotional`

### Sample Output

```
15:30:45 | INFO     | Starting document classification API tests
15:30:45 | SUCCESS  | ✓ Health check passed: {'status': 'healthy', ...}
15:30:45 | INFO     | Supported types: promotional, receipt, billStatement, ...

================================================================================
Testing: WA529 Promotional Mailer
================================================================================
15:30:46 | INFO     | Classifying document (280 chars)...
15:30:47 | SUCCESS  | ✓ Classification: promotional (confidence: 95.00%)
15:30:47 | SUCCESS  | ✓ Expected type matched: promotional
15:30:47 | SUCCESS  | ✓ Extracted 4 fields
15:30:48 | SUCCESS  | ✓ Analysis complete: promotional with 4 fields

================================================================================
TEST SUMMARY
================================================================================
✓ PASS: WA529 Promotional Mailer
✓ PASS: CVS Receipt
✓ PASS: Credit Card Offer
...
Results: 9/9 passed (100.0%)
```

## Mock Data

The script includes mock OCR/transcription data for the following document types:

### Mock OCR Text (Images)
- `wa529_mailer` - Promotional mailer with promo code
- `cvs_receipt` - Retail receipt with transaction details
- `credit_card_offer` - Credit card promotional offer
- `utility_bill` - Electric utility billing statement
- `insurance_card` - Health insurance card with RX info
- `business_letter` - Formal business correspondence

### Mock Transcriptions (Audio)
- `receipt_voice` - Spoken receipt details
- `bill_voice` - Spoken bill information
- `promo_voice` - Spoken promotional offer

## Adding New Test Cases

To add a new test case, update the mock data in the script:

```python
# In MockOCRExtractor.extract_from_image()
mock_texts = {
    "your_new_test": """
        Your test document text here...
    """,
}

# In test_cases list
test_cases = [
    ("Your Test Name", "your_new_test.jpg", "expected_type"),
]
```

## Log Files

Logs are saved to `logs/test_upload_{time}.log` with:
- Rotation: 10 MB per file
- Retention: 7 days
- Format: Timestamped, structured logs

## Troubleshooting

### Server Not Running
```
Error: API is not healthy
```
**Solution**: Start the server with `python main.py`

### API Key Missing
```
Error: OpenAI API key not configured
```
**Solution**: Add `OPENAI_API_KEY=your-key` to `.env`

### Test Failures
Check the detailed logs in `logs/` directory for:
- Request/response details
- Classification signals
- Error tracebacks

## Integration with Real Files

To test with real images/audio instead of mock data:

1. Add OCR integration (e.g., Tesseract, Google Vision)
2. Add audio transcription (e.g., Whisper, Google Speech-to-Text)
3. Update the `extract_from_image()` and `extract_from_audio()` methods

Example:
```python
from PIL import Image
import pytesseract

def extract_from_image(image_path: Path) -> str:
    image = Image.open(image_path)
    text = pytesseract.image_to_string(image)
    return text
```

## Advanced Usage

### Custom Base URL
```python
client = DocumentTestClient(base_url="http://localhost:8080")
```

### Individual Endpoint Testing
```python
# Test just classification
result = await client.classify_document(ocr_text)

# Test just extraction
result = await client.extract_fields(ocr_text, "receipt")

# Test full pipeline
result = await client.analyze_document(ocr_text)
```

## See Also

- [API Documentation](http://localhost:8000/docs)
- [Classification Strategy](../docs/CLASSIFICATION_STRATEGY.md)
- [Main README](../README.md)
