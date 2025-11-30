# Logging Implementation with Loguru

This document describes the implementation of `loguru` logging throughout the FolioMind backend.

## Overview

Replaced standard Python `logging` with `loguru` for:
- Better structured logging
- Colored console output
- Automatic log rotation and compression
- Rich formatting and context
- Exception tracing

## Changes Made

### 1. Dependencies (`pyproject.toml`)

Added:
```toml
"loguru>=0.7.2"
"pillow>=10.2.0"  # For test script
"httpx>=0.26.0"   # For test script
```

### 2. Main Application (`app/main.py`)

**Loguru Configuration**:
- ✅ Console handler with colored output
- ✅ Daily rotating log files (`logs/foliomind_{time}.log`)
- ✅ Separate error log (`logs/errors_{time}.log`)
- ✅ 30-day retention for regular logs
- ✅ 90-day retention for error logs
- ✅ Automatic compression (zip)

**Enhanced Logging**:
- Startup banner with configuration details
- Shutdown messages
- Better exception handling with full tracebacks

### 3. Classification Service (`app/services/classification_service.py`)

**Added Logging**:
- Document classification start with metadata
- Step-by-step detection logging
- Signal detection confirmations (✓ markers)
- Final classification result with confidence
- Detailed decision summary

**Example Output**:
```
Starting classification | text_length=280 | fields_count=0 | hint=None
STEP 1: Checking promotional signals...
✓ Promotional detected | signals={'signal_count': 3, 'categories': [...]}
Classification: PROMOTIONAL | confidence=95.00% | signals=3/5
```

### 4. Extraction Service (`app/services/extraction_service.py`)

**Added Logging**:
- Field extraction start
- Pattern-based field discovery
- Document-type specific extraction
- Field counts and samples
- Success/error logging

**Example Output**:
```
Starting field extraction | doc_type=promotional | text_length=280
Extracting pattern-based fields...
Found 3 pattern-based fields
Extracting promotional-specific fields...
Found 2 promotional fields
Extraction complete | total_fields=5
  • offer_amount: $50 (confidence=85.00%)
  • promo_code: Offer25 (confidence=95.00%)
```

### 5. LLM Providers (`app/services/llm/openai_provider.py`)

**Added Logging**:
- Provider initialization
- API request details (model, temperature, tokens)
- Response metadata (length, token usage)
- Error logging with tracebacks

**Example Output**:
```
Initialized OpenAI provider | model=gpt-4-turbo-preview
OpenAI completion request | model=gpt-4-turbo-preview | temp=0.0 | max_tokens=1000
OpenAI completion | result_length=150 | tokens_used=250
```

### 6. API Endpoints

#### Classification Endpoint (`app/api/v1/endpoints/classification.py`)
```
📄 /classify endpoint | text_length=280 | fields_count=0 | hint=None
✓ /classify completed | type=promotional | confidence=95.00%
```

#### Extraction Endpoint (`app/api/v1/endpoints/extraction.py`)
```
🔍 /extract endpoint | type=receipt | text_length=450
✓ /extract completed | fields_count=8
```

#### Analyze Endpoint (`app/api/v1/endpoints/extraction.py`)
```
🔬 /analyze endpoint | text_length=450 | hint=None
Step 1: Classifying document...
Classification: receipt (confidence=95.00%)
Step 2: Extracting fields...
✓ /analyze completed | type=receipt | fields_count=8
```

## Test Script (`scripts/test_upload.py`)

Created comprehensive standalone test script with:

**Features**:
- Mock OCR extraction for images
- Mock transcription for audio
- Full API testing (classify, extract, analyze)
- Beautiful colored output
- Test summary and pass/fail reporting

**Test Coverage**:
- 9 test cases covering all document types
- Expected vs actual type validation
- Full pipeline testing

**Logging**:
- Test-specific log files in `logs/test_upload_{time}.log`
- 10 MB rotation, 7-day retention
- Colored console output
- Structured logs with emojis

**Usage**:
```bash
python scripts/test_upload.py
```

## Log File Structure

```
backend/
├── logs/
│   ├── foliomind_2025-11-30.log       # Daily application log
│   ├── foliomind_2025-11-30.log.zip   # Compressed old logs
│   ├── errors_2025-11-30.log          # Error-only log
│   └── test_upload_2025-11-30.log     # Test script logs
```

## Log Format

### Console (Colored)
```
2025-11-30 15:30:45 | INFO     | app.main:lifespan:78 | 🚀 Starting FolioMind Backend API
2025-11-30 15:30:45 | SUCCESS  | app.services.classification_service:classify:117 | Classification: PROMOTIONAL | confidence=95.00%
2025-11-30 15:30:45 | ERROR    | app.api.v1.endpoints.classification:classify_document:52 | ✗ /classify failed: Invalid input
```

### File (Structured)
```
2025-11-30 15:30:45 | INFO     | app.main:lifespan:78 | 🚀 Starting FolioMind Backend API
2025-11-30 15:30:45 | SUCCESS  | app.services.classification_service:classify:117 | Classification: PROMOTIONAL | confidence=95.00%
```

## Log Levels

| Level | Usage | Examples |
|-------|-------|----------|
| DEBUG | Detailed diagnostics | Signal detection, field patterns, API parameters |
| INFO | General events | Request received, service started, document classified |
| SUCCESS | Positive outcomes | Classification complete, fields extracted, test passed |
| WARNING | Warnings | No strong signals, fallback to generic, low confidence |
| ERROR | Errors | API failures, extraction errors, exceptions |

## Benefits

### 1. Better Debugging
- Full context in every log line (file, function, line number)
- Exception tracebacks automatically included
- Structured data (key=value format)

### 2. Better Operations
- Automatic log rotation prevents disk fill
- Compression saves space
- Separate error logs for quick issue identification
- Colored output for faster visual parsing

### 3. Better Testing
- Test logs separate from application logs
- Pass/fail indicators (✓/✗)
- Timing information
- Full request/response details

### 4. Better Analytics
- Structured format easy to parse
- Consistent key-value pairs
- JSON-friendly format
- Easy to integrate with log aggregators (Datadog, Splunk, etc.)

## Examples

### Successful Classification Flow
```
2025-11-30 15:30:45 | INFO     | 📄 /classify endpoint | text_length=280 | fields_count=0
2025-11-30 15:30:45 | DEBUG    | STEP 1: Checking promotional signals...
2025-11-30 15:30:45 | DEBUG    | ✓ Promotional detected | signals={'signal_count': 3}
2025-11-30 15:30:45 | SUCCESS  | Classification: PROMOTIONAL | confidence=95.00%
2025-11-30 15:30:45 | DEBUG    | FINAL RESULT: promotional | confidence=95.00%
2025-11-30 15:30:45 | SUCCESS  | ✓ /classify completed | type=promotional | confidence=95.00%
```

### Error Handling
```
2025-11-30 15:30:50 | ERROR    | ✗ /classify failed: Invalid input text
2025-11-30 15:30:50 | ERROR    | Full traceback:
Traceback (most recent call last):
  File "app/api/v1/endpoints/classification.py", line 35, in classify_document
    doc_type, confidence, signals = ClassificationService.classify(...)
ValueError: Invalid input text
```

### Test Execution
```
15:30:45 | INFO     | Starting document classification API tests
15:30:45 | SUCCESS  | ✓ Health check passed
================================================================================
Testing: WA529 Promotional Mailer
================================================================================
15:30:46 | SUCCESS  | ✓ Classification: promotional (confidence: 95.00%)
15:30:46 | SUCCESS  | ✓ Expected type matched: promotional
15:30:47 | SUCCESS  | ✓ Extracted 4 fields
```

## Migration Notes

### Before (Standard Logging)
```python
import logging
logger = logging.getLogger(__name__)
logger.info("Processing document")
```

### After (Loguru)
```python
from loguru import logger
logger.info("Processing document | text_length={length}", length=len(text))
```

### Key Differences
1. **No logger configuration needed** - loguru works out of the box
2. **Better formatting** - Use f-strings or format strings
3. **Automatic context** - Function, file, line automatically included
4. **Exception handling** - Use `logger.exception()` for full tracebacks
5. **Success level** - New `logger.success()` for positive outcomes

## Configuration

All loguru configuration is in `app/main.py`:

```python
# Console output
logger.add(sys.stderr, level="INFO", format="...", colorize=True)

# Daily rotating files
logger.add("logs/foliomind_{time}.log", rotation="00:00", retention="30 days")

# Error-only logs
logger.add("logs/errors_{time}.log", level="ERROR", retention="90 days")
```

## Best Practices

1. **Use structured logging**:
   ```python
   # Good
   logger.info(f"Classified document | type={doc_type} | confidence={conf:.2%}")

   # Avoid
   logger.info(f"Document classified as {doc_type} with confidence {conf}")
   ```

2. **Include context**:
   ```python
   logger.debug(f"API request | endpoint={endpoint} | params={params}")
   ```

3. **Use appropriate levels**:
   - `debug` - Detailed diagnostics
   - `info` - Normal operations
   - `success` - Positive outcomes
   - `warning` - Potential issues
   - `error` - Actual errors

4. **Log exceptions properly**:
   ```python
   try:
       # code
   except Exception as e:
       logger.error(f"Operation failed: {e}")
       logger.exception("Full traceback:")
       raise
   ```

## Future Enhancements

- [ ] Add JSON log format for production
- [ ] Integrate with log aggregation service
- [ ] Add performance metrics logging
- [ ] Add request ID tracking across services
- [ ] Add sampling for high-volume logs
- [ ] Add custom log filters

## References

- [Loguru Documentation](https://loguru.readthedocs.io/)
- [Test Script README](scripts/README.md)
- [Classification Strategy](docs/CLASSIFICATION_STRATEGY.md)
