#!/usr/bin/env python3
"""
Standalone test script for document classification API.

This script uploads example images and audio files, extracts text (OCR/transcription),
and tests the classification API endpoints.
"""

import asyncio
import base64
import json
from pathlib import Path
from typing import Optional

import httpx
from loguru import logger
from PIL import Image

# Configure loguru
logger.remove()  # Remove default handler
logger.add(
    "logs/test_upload_{time}.log",
    rotation="10 MB",
    retention="7 days",
    level="DEBUG",
    format="{time:YYYY-MM-DD HH:mm:ss} | {level: <8} | {name}:{function}:{line} | {message}",
)
logger.add(
    lambda msg: print(msg, end=""),
    level="INFO",
    format="<green>{time:HH:mm:ss}</green> | <level>{level: <8}</level> | <level>{message}</level>",
    colorize=True,
)


class DocumentTestClient:
    """Client for testing document classification API."""

    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url
        self.client = httpx.AsyncClient(timeout=30.0)
        logger.info(f"Initialized test client with base URL: {base_url}")

    async def health_check(self) -> bool:
        """Check if API is healthy."""
        try:
            logger.debug("Performing health check...")
            response = await self.client.get(f"{self.base_url}/api/v1/health")
            response.raise_for_status()
            data = response.json()
            logger.success(f"✓ Health check passed: {data}")
            return True
        except Exception as e:
            logger.error(f"✗ Health check failed: {e}")
            return False

    async def get_document_types(self) -> list[str]:
        """Get list of supported document types."""
        try:
            logger.debug("Fetching supported document types...")
            response = await self.client.get(f"{self.base_url}/api/v1/types")
            response.raise_for_status()
            data = response.json()
            types = data.get("types", [])
            logger.info(f"Supported types: {', '.join(types)}")
            return types
        except Exception as e:
            logger.error(f"Failed to get document types: {e}")
            return []

    async def classify_document(
        self, ocr_text: str, fields: Optional[list] = None, hint: Optional[str] = None
    ) -> dict:
        """Classify a document."""
        try:
            logger.info(f"Classifying document ({len(ocr_text)} chars)...")
            logger.debug(f"OCR text preview: {ocr_text[:200]}...")

            payload = {"ocr_text": ocr_text}
            if fields:
                payload["fields"] = fields
            if hint:
                payload["hint"] = hint

            response = await self.client.post(
                f"{self.base_url}/api/v1/classify", json=payload
            )
            response.raise_for_status()
            result = response.json()

            logger.success(
                f"✓ Classification: {result['document_type']} "
                f"(confidence: {result['confidence']:.2%})"
            )
            logger.debug(f"Signals: {json.dumps(result.get('signals', {}), indent=2)}")

            return result
        except httpx.HTTPStatusError as e:
            logger.error(f"✗ Classification failed with status {e.response.status_code}")
            logger.error(f"Response: {e.response.text}")
            raise
        except Exception as e:
            logger.error(f"✗ Classification failed: {e}")
            raise

    async def extract_fields(self, ocr_text: str, document_type: str) -> dict:
        """Extract fields from document."""
        try:
            logger.info(f"Extracting fields for {document_type}...")

            payload = {"ocr_text": ocr_text, "document_type": document_type}

            response = await self.client.post(
                f"{self.base_url}/api/v1/extract", json=payload
            )
            response.raise_for_status()
            result = response.json()

            logger.success(f"✓ Extracted {len(result.get('fields', []))} fields")
            for field in result.get("fields", [])[:5]:  # Show first 5 fields
                logger.debug(
                    f"  - {field['key']}: {field['value']} "
                    f"(confidence: {field.get('confidence', 0):.2%})"
                )

            return result
        except Exception as e:
            logger.error(f"✗ Field extraction failed: {e}")
            raise

    async def analyze_document(
        self, ocr_text: str, fields: Optional[list] = None, hint: Optional[str] = None
    ) -> dict:
        """Full pipeline: classify and extract."""
        try:
            logger.info("Running full analysis pipeline...")

            payload = {"ocr_text": ocr_text}
            if fields:
                payload["fields"] = fields
            if hint:
                payload["hint"] = hint

            response = await self.client.post(
                f"{self.base_url}/api/v1/analyze", json=payload
            )
            response.raise_for_status()
            result = response.json()

            logger.success(
                f"✓ Analysis complete: {result['classification']['document_type']} "
                f"with {len(result['extraction']['fields'])} fields"
            )

            return result
        except Exception as e:
            logger.error(f"✗ Analysis failed: {e}")
            raise

    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()
        logger.debug("Closed HTTP client")


class MockOCRExtractor:
    """Mock OCR extractor for test documents."""

    @staticmethod
    def extract_from_image(image_path: Path) -> str:
        """Extract text from image (mock implementation)."""
        logger.info(f"Extracting text from image: {image_path.name}")

        # Mock OCR text based on filename
        mock_texts = {
            "wa529_mailer": """
                Make this the season you start saving!
                Get $50 when you open a WA529 Invest account by 12/3/2025 and 12/12/2025.*

                1. Make a deposit of $50 using promo code Offer25 when enrolling online.
                2. Set up recurring contributions of $50 or more for at least six consecutive months.
                3. We'll add $50 to your savings.

                Visit 529Invest.wa.gov/Offer25
                *Promotion ends 12/12/2025.
            """,
            "cvs_receipt": """
                CVS PHARMACY
                Store #1234
                Receipt #456789
                Date: 11/30/2025 14:32

                ADVIL TABLETS         $12.99
                VITAMIN C GUMMIES      $8.49
                HAND SANITIZER         $4.99

                Subtotal:             $26.47
                Sales Tax:             $2.38
                Total:                $28.85

                VISA ****1234
                Auth Code: 123456
                Thank you for shopping at CVS!
            """,
            "credit_card_offer": """
                Chase Sapphire Preferred Card

                Earn 60,000 bonus points when you spend $4,000 on purchases
                in the first 3 months from account opening.

                That's $750 toward travel when you redeem through Chase Ultimate Rewards.

                Apply now at chase.com/sapphire
                Offer expires March 31, 2025

                Terms and conditions apply.
            """,
            "utility_bill": """
                SEATTLE CITY LIGHT
                Billing Statement

                Account Number: 123-456-7890
                Statement Date: November 15, 2025
                Billing Period: Oct 15 - Nov 14, 2025

                Previous Balance:      $102.87
                Payment Received:     -$102.87
                Current Charges:       $118.54

                Amount Due:           $118.54
                Due Date: December 5, 2025

                Usage: 487 kWh
                Please pay by due date to avoid late fees.
            """,
            "insurance_card": """
                PREMERA BLUE CROSS
                Member ID: ABC123456789
                Group #: 12345

                JOHN DOE
                Plan: PPO Network

                Copay:
                  Primary Care: $25
                  Specialist: $45
                  Emergency: $150

                RX BIN: 610020
                RX PCN: PDMI
                RX GRP: BCBS123

                For benefits call: 1-800-PREMERA
            """,
            "business_letter": """
                Seattle Business Solutions
                123 Main Street, Seattle, WA 98101

                November 30, 2025

                Dear Mr. Johnson,

                Thank you for your inquiry regarding our services. We are pleased to provide
                you with information about our consulting packages.

                Our team has over 20 years of experience helping businesses like yours grow
                and succeed in today's competitive market.

                We look forward to the opportunity to work with you.

                Sincerely,

                Jane Smith
                Senior Account Manager
            """,
        }

        # Try to match filename to mock text
        for key, text in mock_texts.items():
            if key.lower() in image_path.stem.lower():
                logger.debug(f"Using mock OCR text for: {key}")
                return text.strip()

        # Default generic text
        logger.warning(f"No mock text found for {image_path.name}, using default")
        return "Generic document text. No specific content available."

    @staticmethod
    def extract_from_audio(audio_path: Path) -> str:
        """Extract text from audio (mock transcription)."""
        logger.info(f"Transcribing audio: {audio_path.name}")

        # Mock transcriptions based on filename
        mock_transcriptions = {
            "receipt_voice": """
                I just got a receipt from Starbucks.
                Grande latte was $5.75, plus a croissant for $3.95.
                Total came to $9.70. Paid with my Visa ending in 4321.
                Receipt number is 987654.
            """,
            "bill_voice": """
                Looking at my electric bill here.
                It's from Seattle City Light, account number is 555-123-4567.
                Amount due is $142.33, and it's due by December 1st.
                Says I used 523 kilowatt hours this month.
            """,
            "promo_voice": """
                I got this promotional flyer from Capital One.
                It says earn 75,000 bonus miles when you spend $4,000
                in the first three months.
                The offer expires on January 15th, 2026.
                You can apply at capitalone.com slash venture.
            """,
        }

        for key, text in mock_transcriptions.items():
            if key.lower() in audio_path.stem.lower():
                logger.debug(f"Using mock transcription for: {key}")
                return text.strip()

        logger.warning(f"No mock transcription found for {audio_path.name}, using default")
        return "Generic audio transcription. No specific content available."


async def test_document(
    client: DocumentTestClient,
    name: str,
    text: str,
    expected_type: Optional[str] = None
):
    """Test a single document classification."""
    logger.info(f"\n{'='*80}")
    logger.info(f"Testing: {name}")
    logger.info(f"{'='*80}")

    try:
        # Classify
        classify_result = await client.classify_document(text)

        if expected_type:
            actual_type = classify_result["document_type"]
            if actual_type == expected_type:
                logger.success(f"✓ Expected type matched: {expected_type}")
            else:
                logger.warning(
                    f"✗ Type mismatch! Expected: {expected_type}, Got: {actual_type}"
                )

        # Extract fields
        extract_result = await client.extract_fields(
            text, classify_result["document_type"]
        )

        # Full analysis
        analyze_result = await client.analyze_document(text)

        logger.info(f"Test '{name}' completed successfully\n")
        return True

    except Exception as e:
        logger.error(f"Test '{name}' failed: {e}\n")
        return False


async def run_tests():
    """Run all test cases."""
    logger.info("Starting document classification API tests")
    logger.info(f"{'='*80}\n")

    # Initialize client
    client = DocumentTestClient()

    # Check API health
    if not await client.health_check():
        logger.error("API is not healthy. Please start the server first.")
        logger.info("\nTo start the server, run:")
        logger.info("  cd /Users/jay/designland/FolioMind/backend")
        logger.info("  python main.py")
        return

    # Get supported types
    await client.get_document_types()

    # Create mock extractor
    ocr = MockOCRExtractor()

    # Test cases with expected types
    test_cases = [
        ("WA529 Promotional Mailer", "wa529_mailer.jpg", "promotional"),
        ("CVS Receipt", "cvs_receipt.jpg", "receipt"),
        ("Credit Card Offer", "credit_card_offer.jpg", "promotional"),
        ("Utility Bill", "utility_bill.pdf", "billStatement"),
        ("Insurance Card", "insurance_card.jpg", "insuranceCard"),
        ("Business Letter", "business_letter.pdf", "letter"),
        ("Receipt Voice Note", "receipt_voice.m4a", "receipt"),
        ("Bill Voice Note", "bill_voice.m4a", "billStatement"),
        ("Promo Voice Note", "promo_voice.m4a", "promotional"),
    ]

    results = []
    for name, filename, expected_type in test_cases:
        # Mock file path
        file_path = Path(f"test_data/{filename}")

        # Extract text based on file type
        if filename.endswith((".jpg", ".png", ".pdf")):
            text = ocr.extract_from_image(file_path)
        else:  # Audio files
            text = ocr.extract_from_audio(file_path)

        # Test the document
        success = await test_document(client, name, text, expected_type)
        results.append((name, success))

    # Summary
    logger.info(f"\n{'='*80}")
    logger.info("TEST SUMMARY")
    logger.info(f"{'='*80}")

    passed = sum(1 for _, success in results if success)
    total = len(results)

    for name, success in results:
        status = "✓ PASS" if success else "✗ FAIL"
        logger.info(f"{status}: {name}")

    logger.info(f"\nResults: {passed}/{total} passed ({passed/total:.1%})")

    await client.close()


if __name__ == "__main__":
    # Ensure logs directory exists
    Path("logs").mkdir(exist_ok=True)

    # Run tests
    try:
        asyncio.run(run_tests())
    except KeyboardInterrupt:
        logger.warning("\nTests interrupted by user")
    except Exception as e:
        logger.exception(f"Tests failed with error: {e}")
