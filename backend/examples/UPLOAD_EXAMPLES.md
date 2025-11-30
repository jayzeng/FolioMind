# Upload Endpoints Usage Examples

This guide provides practical examples for using the upload endpoints.

## Quick Start

### 1. Start the Server

```bash
# From backend directory
cd /Users/jay/designland/FolioMind/backend

# Make sure dependencies are installed
pip install -e .

# Set up environment variables
export OPENAI_API_KEY="your-api-key-here"

# Start the server
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 2. Test the Endpoints

```bash
# Using the test script
python examples/test_upload_endpoints.py path/to/image.jpg
python examples/test_upload_endpoints.py path/to/audio.mp3 en
```

---

## cURL Examples

### Upload Image (Receipt)

```bash
curl -X POST "http://localhost:8000/api/v1/upload/image" \
  -H "accept: application/json" \
  -F "file=@receipt.jpg" \
  | jq '.'
```

### Upload Image (Promotional Flyer)

```bash
curl -X POST "http://localhost:8000/api/v1/upload/image" \
  -H "accept: application/json" \
  -F "file=@promo_flyer.png" \
  | jq '{document_type, confidence, fields}'
```

### Upload Audio (English)

```bash
curl -X POST "http://localhost:8000/api/v1/upload/audio?language=en" \
  -H "accept: application/json" \
  -F "file=@voice_memo.mp3" \
  | jq '.'
```

### Upload Audio (Spanish)

```bash
curl -X POST "http://localhost:8000/api/v1/upload/audio?language=es" \
  -H "accept: application/json" \
  -F "file=@mensaje.m4a" \
  | jq '{extracted_text, document_type}'
```

---

## Python Examples

### Example 1: Upload Image with httpx

```python
import asyncio
import httpx

async def upload_image(file_path: str):
    async with httpx.AsyncClient(timeout=60.0) as client:
        with open(file_path, "rb") as f:
            files = {"file": (file_path, f, "image/jpeg")}
            response = await client.post(
                "http://localhost:8000/api/v1/upload/image",
                files=files
            )

        if response.status_code == 200:
            result = response.json()
            print(f"Type: {result['document_type']}")
            print(f"Confidence: {result['confidence']:.2%}")
            print(f"Text: {result['extracted_text'][:200]}...")
            print(f"Fields: {len(result['fields'])}")
        else:
            print(f"Error: {response.status_code}")
            print(response.json())

asyncio.run(upload_image("receipt.jpg"))
```

### Example 2: Upload Audio with requests

```python
import requests

def upload_audio(file_path: str, language: str = "en"):
    with open(file_path, "rb") as f:
        files = {"file": (file_path, f, "audio/mpeg")}
        params = {"language": language}

        response = requests.post(
            "http://localhost:8000/api/v1/upload/audio",
            files=files,
            params=params,
            timeout=120
        )

    if response.status_code == 200:
        result = response.json()
        print(f"Transcription: {result['extracted_text']}")
        print(f"Type: {result['document_type']}")
        print(f"Fields: {result['fields']}")
    else:
        print(f"Error: {response.status_code}")
        print(response.json())

upload_audio("recording.mp3", language="en")
```

### Example 3: Batch Upload with Progress

```python
import asyncio
from pathlib import Path
import httpx

async def batch_upload_images(image_dir: str):
    """Upload all images in a directory."""
    image_paths = list(Path(image_dir).glob("*.jpg"))

    async with httpx.AsyncClient(timeout=60.0) as client:
        for i, image_path in enumerate(image_paths, 1):
            print(f"[{i}/{len(image_paths)}] Uploading {image_path.name}...")

            with open(image_path, "rb") as f:
                files = {"file": (image_path.name, f, "image/jpeg")}
                response = await client.post(
                    "http://localhost:8000/api/v1/upload/image",
                    files=files
                )

            if response.status_code == 200:
                result = response.json()
                print(f"  ✓ {result['document_type']} (confidence: {result['confidence']:.2%})")
            else:
                print(f"  ✗ Failed: {response.status_code}")

asyncio.run(batch_upload_images("./receipts"))
```

### Example 4: Error Handling

```python
import asyncio
import httpx

async def upload_with_error_handling(file_path: str):
    """Upload file with comprehensive error handling."""
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            with open(file_path, "rb") as f:
                files = {"file": (file_path, f)}
                response = await client.post(
                    "http://localhost:8000/api/v1/upload/image",
                    files=files
                )

            if response.status_code == 200:
                result = response.json()
                return result

            elif response.status_code == 400:
                error = response.json()
                if error.get("detail", {}).get("error") == "InvalidFileFormat":
                    print(f"Invalid format: {error['detail']['message']}")
                else:
                    print(f"Bad request: {error}")

            elif response.status_code == 413:
                error = response.json()
                print(f"File too large: {error['detail']['message']}")

            elif response.status_code == 422:
                error = response.json()
                print(f"No text extracted: {error['detail']['message']}")

            elif response.status_code == 500:
                error = response.json()
                print(f"Server error: {error['detail']['message']}")

            else:
                print(f"Unexpected error: {response.status_code}")

    except FileNotFoundError:
        print(f"File not found: {file_path}")
    except httpx.TimeoutException:
        print("Request timed out")
    except Exception as e:
        print(f"Error: {e}")

asyncio.run(upload_with_error_handling("receipt.jpg"))
```

---

## JavaScript/TypeScript Examples

### Example 1: Node.js with fetch

```javascript
const FormData = require('form-data');
const fs = require('fs');

async function uploadImage(filePath) {
  const form = new FormData();
  form.append('file', fs.createReadStream(filePath));

  const response = await fetch('http://localhost:8000/api/v1/upload/image', {
    method: 'POST',
    body: form,
  });

  if (response.ok) {
    const result = await response.json();
    console.log('Document Type:', result.document_type);
    console.log('Confidence:', result.confidence);
    console.log('Fields:', result.fields);
  } else {
    console.error('Upload failed:', response.status);
    const error = await response.json();
    console.error(error);
  }
}

uploadImage('receipt.jpg');
```

### Example 2: Browser Upload with React

```typescript
import React, { useState } from 'react';

interface UploadResult {
  extracted_text: string;
  document_type: string;
  confidence: number;
  fields: Array<{
    key: string;
    value: string;
    confidence: number;
    source: string;
  }>;
  metadata: {
    filename: string;
    file_size: number;
    file_type: string;
    processing_time_ms: number;
  };
}

export const ImageUpload: React.FC = () => {
  const [result, setResult] = useState<UploadResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setLoading(true);
    setError(null);

    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await fetch('http://localhost:8000/api/v1/upload/image', {
        method: 'POST',
        body: formData,
      });

      if (response.ok) {
        const data = await response.json();
        setResult(data);
      } else {
        const errorData = await response.json();
        setError(errorData.detail?.message || 'Upload failed');
      }
    } catch (err) {
      setError('Network error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <input type="file" accept="image/*" onChange={handleFileUpload} />
      {loading && <p>Processing...</p>}
      {error && <p style={{ color: 'red' }}>{error}</p>}
      {result && (
        <div>
          <h3>Results</h3>
          <p><strong>Type:</strong> {result.document_type}</p>
          <p><strong>Confidence:</strong> {(result.confidence * 100).toFixed(1)}%</p>
          <p><strong>Text:</strong> {result.extracted_text}</p>
          <h4>Fields:</h4>
          <ul>
            {result.fields.map((field, i) => (
              <li key={i}>
                {field.key}: {field.value} ({(field.confidence * 100).toFixed(1)}%)
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
};
```

---

## Testing Different Document Types

### Receipt Example

```bash
# Upload a receipt image
curl -X POST "http://localhost:8000/api/v1/upload/image" \
  -F "file=@receipt.jpg" | jq '{
    document_type,
    confidence,
    fields: [.fields[] | select(.key | test("total|transaction|date"))]
  }'
```

### Promotional Material Example

```bash
# Upload a promotional flyer
curl -X POST "http://localhost:8000/api/v1/upload/image" \
  -F "file=@promo.png" | jq '{
    document_type,
    confidence,
    promo_fields: [.fields[] | select(.key | test("promo|offer|expir"))]
  }'
```

### Bill Statement Example

```bash
# Upload a utility bill
curl -X POST "http://localhost:8000/api/v1/upload/image" \
  -F "file=@bill.jpg" | jq '{
    document_type,
    confidence,
    bill_fields: [.fields[] | select(.key | test("due|amount|account"))]
  }'
```

---

## Advanced Usage

### Custom Processing with Results

```python
import asyncio
import httpx
from datetime import datetime

async def process_and_save(file_path: str, output_dir: str):
    """Upload file, process, and save results."""
    async with httpx.AsyncClient(timeout=60.0) as client:
        with open(file_path, "rb") as f:
            files = {"file": (file_path, f, "image/jpeg")}
            response = await client.post(
                "http://localhost:8000/api/v1/upload/image",
                files=files
            )

        if response.status_code == 200:
            result = response.json()

            # Save results to JSON
            output_file = f"{output_dir}/{datetime.now().isoformat()}.json"
            with open(output_file, "w") as f:
                json.dump(result, f, indent=2)

            # Extract and save specific fields
            if result['document_type'] == 'receipt':
                total = next(
                    (f['value'] for f in result['fields'] if f['key'] == 'total_amount'),
                    None
                )
                print(f"Receipt total: {total}")

            elif result['document_type'] == 'promotional':
                promo_code = next(
                    (f['value'] for f in result['fields'] if f['key'] == 'promo_code'),
                    None
                )
                print(f"Promo code: {promo_code}")

            return result

asyncio.run(process_and_save("receipt.jpg", "./processed"))
```

### Retry Logic for Failed Uploads

```python
import asyncio
import httpx
from tenacity import retry, stop_after_attempt, wait_exponential

@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10)
)
async def upload_with_retry(file_path: str):
    """Upload file with automatic retry on failure."""
    async with httpx.AsyncClient(timeout=60.0) as client:
        with open(file_path, "rb") as f:
            files = {"file": (file_path, f, "image/jpeg")}
            response = await client.post(
                "http://localhost:8000/api/v1/upload/image",
                files=files
            )

        response.raise_for_status()
        return response.json()

# Usage
try:
    result = asyncio.run(upload_with_retry("receipt.jpg"))
    print("Success:", result['document_type'])
except Exception as e:
    print("Failed after retries:", e)
```

---

## Performance Optimization

### Compress Images Before Upload

```python
from PIL import Image
import io

def compress_image(input_path: str, max_size_kb: int = 500) -> bytes:
    """Compress image to target size."""
    img = Image.open(input_path)

    # Convert to RGB if necessary
    if img.mode != 'RGB':
        img = img.convert('RGB')

    # Try different quality levels
    for quality in range(95, 20, -5):
        buffer = io.BytesIO()
        img.save(buffer, format='JPEG', quality=quality, optimize=True)
        size_kb = len(buffer.getvalue()) / 1024

        if size_kb <= max_size_kb:
            return buffer.getvalue()

    # If still too large, resize
    img.thumbnail((1920, 1920))
    buffer = io.BytesIO()
    img.save(buffer, format='JPEG', quality=85, optimize=True)
    return buffer.getvalue()

# Usage
compressed = compress_image("large_receipt.jpg", max_size_kb=500)
# Upload compressed bytes instead of file
```

---

## Integration Examples

### Integrate with FastAPI Application

```python
from fastapi import FastAPI, UploadFile, File
import httpx

app = FastAPI()

@app.post("/process-document")
async def process_document(file: UploadFile = File(...)):
    """Proxy endpoint that uses the upload service."""
    async with httpx.AsyncClient() as client:
        # Forward to upload service
        response = await client.post(
            "http://localhost:8000/api/v1/upload/image",
            files={"file": (file.filename, await file.read(), file.content_type)}
        )

        if response.status_code == 200:
            result = response.json()

            # Process results
            # ... your business logic here ...

            return {
                "status": "success",
                "document_type": result['document_type'],
                "fields": result['fields']
            }
        else:
            return {"status": "error", "detail": response.json()}
```

---

## Monitoring and Logging

```python
import asyncio
import httpx
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def upload_with_logging(file_path: str):
    """Upload file with detailed logging."""
    start_time = datetime.now()

    try:
        logger.info(f"Starting upload: {file_path}")

        async with httpx.AsyncClient(timeout=60.0) as client:
            with open(file_path, "rb") as f:
                files = {"file": (file_path, f, "image/jpeg")}
                response = await client.post(
                    "http://localhost:8000/api/v1/upload/image",
                    files=files
                )

        elapsed = (datetime.now() - start_time).total_seconds()

        if response.status_code == 200:
            result = response.json()
            logger.info(
                f"Upload successful | "
                f"type={result['document_type']} | "
                f"confidence={result['confidence']:.2%} | "
                f"fields={len(result['fields'])} | "
                f"time={elapsed:.2f}s"
            )
            return result
        else:
            logger.error(f"Upload failed | status={response.status_code} | time={elapsed:.2f}s")
            return None

    except Exception as e:
        elapsed = (datetime.now() - start_time).total_seconds()
        logger.exception(f"Upload error | file={file_path} | time={elapsed:.2f}s")
        raise

asyncio.run(upload_with_logging("receipt.jpg"))
```

---

## Summary

The upload endpoints provide a powerful and flexible way to process images and audio files with automatic OCR/transcription, classification, and field extraction. Use these examples as a starting point for integrating the endpoints into your applications.

For more information, see [UPLOAD_ENDPOINTS.md](UPLOAD_ENDPOINTS.md).
