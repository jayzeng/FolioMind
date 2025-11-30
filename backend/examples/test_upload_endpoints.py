#!/usr/bin/env python3
"""Test script for upload endpoints.

This script demonstrates how to use the image and audio upload endpoints.
"""

import asyncio
import sys
from pathlib import Path

import httpx

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# API base URL
BASE_URL = "http://localhost:8000/api/v1"


async def test_image_upload(image_path: str):
    """Test image upload endpoint.

    Args:
        image_path: Path to image file to upload
    """
    print(f"\n{'='*80}")
    print(f"Testing Image Upload: {image_path}")
    print(f"{'='*80}\n")

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            # Read image file
            with open(image_path, "rb") as f:
                files = {"file": (Path(image_path).name, f, "image/jpeg")}

                # Upload image
                print("Uploading image...")
                response = await client.post(
                    f"{BASE_URL}/upload/image",
                    files=files
                )

            # Check response
            if response.status_code == 200:
                result = response.json()
                print("✓ Upload successful!\n")

                # Print results
                print(f"Document Type: {result['document_type']}")
                print(f"Confidence: {result['confidence']:.2%}")
                print(f"\nExtracted Text ({len(result['extracted_text'])} chars):")
                print("-" * 80)
                print(result['extracted_text'][:500])
                if len(result['extracted_text']) > 500:
                    print("...")
                print("-" * 80)

                print(f"\nExtracted Fields ({len(result['fields'])} fields):")
                for field in result['fields']:
                    print(f"  • {field['key']}: {field['value']} (confidence: {field['confidence']:.2%})")

                print(f"\nMetadata:")
                print(f"  • Filename: {result['metadata']['filename']}")
                print(f"  • File size: {result['metadata']['file_size'] / 1024:.2f} KB")
                print(f"  • File type: {result['metadata']['file_type']}")
                print(f"  • Processing time: {result['metadata']['processing_time_ms']:.2f} ms")

            else:
                print(f"✗ Upload failed with status code: {response.status_code}")
                print(f"Error: {response.text}")

    except FileNotFoundError:
        print(f"✗ Error: File not found: {image_path}")
    except Exception as e:
        print(f"✗ Error: {e}")


async def test_audio_upload(audio_path: str, language: str = None):
    """Test audio upload endpoint.

    Args:
        audio_path: Path to audio file to upload
        language: Optional language code (e.g., "en", "es")
    """
    print(f"\n{'='*80}")
    print(f"Testing Audio Upload: {audio_path}")
    if language:
        print(f"Language: {language}")
    print(f"{'='*80}\n")

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            # Read audio file
            with open(audio_path, "rb") as f:
                files = {"file": (Path(audio_path).name, f, "audio/mpeg")}

                # Build parameters
                params = {}
                if language:
                    params["language"] = language

                # Upload audio
                print("Uploading audio...")
                response = await client.post(
                    f"{BASE_URL}/upload/audio",
                    files=files,
                    params=params
                )

            # Check response
            if response.status_code == 200:
                result = response.json()
                print("✓ Upload successful!\n")

                # Print results
                print(f"Document Type: {result['document_type']}")
                print(f"Confidence: {result['confidence']:.2%}")
                print(f"\nTranscribed Text ({len(result['extracted_text'])} chars):")
                print("-" * 80)
                print(result['extracted_text'][:500])
                if len(result['extracted_text']) > 500:
                    print("...")
                print("-" * 80)

                print(f"\nExtracted Fields ({len(result['fields'])} fields):")
                for field in result['fields']:
                    print(f"  • {field['key']}: {field['value']} (confidence: {field['confidence']:.2%})")

                print(f"\nMetadata:")
                print(f"  • Filename: {result['metadata']['filename']}")
                print(f"  • File size: {result['metadata']['file_size'] / 1024:.2f} KB")
                print(f"  • File type: {result['metadata']['file_type']}")
                print(f"  • Processing time: {result['metadata']['processing_time_ms']:.2f} ms")

            else:
                print(f"✗ Upload failed with status code: {response.status_code}")
                print(f"Error: {response.text}")

    except FileNotFoundError:
        print(f"✗ Error: File not found: {audio_path}")
    except Exception as e:
        print(f"✗ Error: {e}")


async def test_error_cases():
    """Test various error cases."""
    print(f"\n{'='*80}")
    print("Testing Error Cases")
    print(f"{'='*80}\n")

    async with httpx.AsyncClient(timeout=30.0) as client:
        # Test 1: Unsupported image format
        print("Test 1: Unsupported image format (.txt)")
        try:
            files = {"file": ("test.txt", b"Not an image", "text/plain")}
            response = await client.post(f"{BASE_URL}/upload/image", files=files)
            print(f"  Status: {response.status_code}")
            if response.status_code == 400:
                print(f"  ✓ Correctly rejected: {response.json()}")
        except Exception as e:
            print(f"  ✗ Error: {e}")

        # Test 2: File too large (simulated)
        print("\nTest 2: Very large file check")
        print("  (Skipped - would take too long to upload)")

        # Test 3: Empty file
        print("\nTest 3: Empty file")
        try:
            files = {"file": ("empty.jpg", b"", "image/jpeg")}
            response = await client.post(f"{BASE_URL}/upload/image", files=files)
            print(f"  Status: {response.status_code}")
            if response.status_code >= 400:
                print(f"  ✓ Correctly handled: {response.json()}")
        except Exception as e:
            print(f"  ✗ Error: {e}")


async def main():
    """Main test function."""
    print("\n" + "="*80)
    print("FolioMind Upload Endpoints Test Suite")
    print("="*80)

    # Check if server is running
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{BASE_URL}/health")
            if response.status_code == 200:
                print("✓ Server is running")
                health = response.json()
                print(f"  • Status: {health['status']}")
                print(f"  • Version: {health['version']}")
                print(f"  • LLM Provider: {health['llm_provider']}")
            else:
                print("✗ Server health check failed")
                return
    except Exception as e:
        print(f"✗ Cannot connect to server at {BASE_URL}")
        print(f"  Error: {e}")
        print("\nPlease start the server with: python -m uvicorn app.main:app --reload")
        return

    # Test image upload (if image file provided)
    if len(sys.argv) > 1 and sys.argv[1].lower().endswith(('.png', '.jpg', '.jpeg', '.webp')):
        await test_image_upload(sys.argv[1])

    # Test audio upload (if audio file provided)
    elif len(sys.argv) > 1 and sys.argv[1].lower().endswith(('.mp3', '.wav', '.m4a', '.ogg')):
        language = sys.argv[2] if len(sys.argv) > 2 else None
        await test_audio_upload(sys.argv[1], language)

    # Test error cases
    else:
        print("\nNo test file provided. Testing error cases only.")
        await test_error_cases()

    print("\n" + "="*80)
    print("Test suite completed!")
    print("="*80 + "\n")

    # Print usage
    if len(sys.argv) == 1:
        print("Usage:")
        print("  Test image upload:")
        print("    python examples/test_upload_endpoints.py path/to/image.jpg")
        print("\n  Test audio upload:")
        print("    python examples/test_upload_endpoints.py path/to/audio.mp3 [language_code]")
        print("\nExample:")
        print("  python examples/test_upload_endpoints.py receipt.jpg")
        print("  python examples/test_upload_endpoints.py recording.mp3 en")


if __name__ == "__main__":
    asyncio.run(main())
