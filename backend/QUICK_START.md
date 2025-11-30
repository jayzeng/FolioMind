# Quick Start Guide

Get the FolioMind Backend API running in 5 minutes.

## Prerequisites

- Python 3.12+
- pip or uv package manager

## 1. Install Dependencies

```bash
cd /Users/jay/designland/FolioMind/backend

# Using pip
pip install -e .

# Or using uv (faster)
uv pip install -e .
```

## 2. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit .env with your API key
nano .env
```

Minimal configuration:
```env
LLM_PROVIDER=openai
OPENAI_API_KEY=sk-your-actual-key-here
```

## 3. Run the Server

```bash
# Option 1: Direct run
python main.py

# Option 2: Using uvicorn
uvicorn app.main:app --reload

# Option 3: Using Docker
docker-compose up
```

Server starts at: **http://localhost:8000**

## 4. Test the API

### Option A: Interactive Documentation

Open in browser:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

### Option B: Command Line (curl)

```bash
# Classify a promotional document
curl -X POST http://localhost:8000/api/v1/classify \
  -H "Content-Type: application/json" \
  -d '{
    "ocr_text": "Get $50 when you open account. Use code SAVE2025."
  }'

# Response: {"document_type": "promotional", "confidence": 0.85, ...}
```

### Option C: Example Script

```bash
# Run all 8 examples
python examples/test_api_examples.py
```

## 5. Run Tests

```bash
# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific test
pytest tests/test_classification.py::TestPromotionalClassification::test_wa529_mailer
```

## Common Commands

```bash
# Development with auto-reload
uvicorn app.main:app --reload --log-level debug

# Production
uvicorn app.main:app --host 0.0.0.0 --port 8000

# Docker build
docker build -t foliomind-backend .

# Docker run
docker run -p 8000:8000 --env-file .env foliomind-backend
```

## Quick Test Examples

### Test 1: WA529 Promotional (Critical Test)
```bash
curl -X POST http://localhost:8000/api/v1/classify \
  -H "Content-Type: application/json" \
  -d '{
    "ocr_text": "Get $50 when you open a WA529 account by 12/12/2025. Use promo code Offer25. We will add $50 to your savings. Promotion ends 12/12/2025."
  }'
```

Expected: `"document_type": "promotional"` ✅

### Test 2: CVS Receipt
```bash
curl -X POST http://localhost:8000/api/v1/classify \
  -H "Content-Type: application/json" \
  -d '{
    "ocr_text": "CVS Pharmacy\nReceipt #12345\nADVIL $12.99\nTotal: $12.99\nVISA ****1234"
  }'
```

Expected: `"document_type": "receipt"` ✅

### Test 3: Full Analysis
```bash
curl -X POST http://localhost:8000/api/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "ocr_text": "Earn 50,000 points when you spend $3,000. Use code BONUS2025. Expires Dec 31."
  }'
```

Expected: Classification + extracted fields (promo_code, offer_amount, expiry)

## Troubleshooting

### Server won't start
```bash
# Check if port 8000 is in use
lsof -i :8000

# Kill existing process
kill -9 <PID>

# Or use different port
uvicorn app.main:app --port 8001
```

### Import errors
```bash
# Reinstall dependencies
pip install -e .

# Or with uv
uv pip install -e .
```

### API key errors
```bash
# Verify .env file exists
cat .env

# Check environment variable is loaded
python -c "from app.core.config import settings; print(settings.openai_api_key)"
```

### Tests failing
```bash
# Ensure test dependencies installed
pip install -e ".[dev]"

# Run with verbose output
pytest -v -s
```

## Next Steps

1. **Read Full Documentation**: See `README.md` for complete guide
2. **Review Strategy**: See `docs/CLASSIFICATION_STRATEGY.md` for classification logic
3. **Explore Examples**: Run `python examples/test_api_examples.py`
4. **Check Implementation**: See `IMPLEMENTATION_SUMMARY.md` for details

## Support

- Documentation: `README.md`
- Strategy Document: `docs/CLASSIFICATION_STRATEGY.md`
- Implementation Details: `IMPLEMENTATION_SUMMARY.md`
- API Reference: http://localhost:8000/docs (when running)

## Success Indicators

✅ Server starts without errors
✅ Health check returns 200: http://localhost:8000/api/v1/health
✅ WA529 classifies as "promotional" (not "receipt")
✅ CVS receipt classifies as "receipt"
✅ Tests pass: `pytest`

You're ready to go! 🚀
