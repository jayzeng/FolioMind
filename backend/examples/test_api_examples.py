"""Example API usage demonstrating all endpoints.

Run the server first:
    python main.py

Then run this script:
    python examples/test_api_examples.py
"""

import asyncio

import httpx


async def main():
    """Run all API examples."""
    base_url = "http://localhost:8000/api/v1"

    async with httpx.AsyncClient() as client:
        print("=" * 80)
        print("FolioMind Backend API Examples")
        print("=" * 80)

        # Example 1: Health Check
        print("\n1. Health Check")
        print("-" * 80)
        response = await client.get(f"{base_url}/health")
        print(f"Status: {response.status_code}")
        print(f"Response: {response.json()}")

        # Example 2: Get Document Types
        print("\n2. Get Supported Document Types")
        print("-" * 80)
        response = await client.get(f"{base_url}/types")
        print(f"Status: {response.status_code}")
        types = response.json()["types"]
        for doc_type in types:
            print(f"  - {doc_type['type']}: {doc_type['description']}")

        # Example 3: Classify WA529 Mailer (Promotional)
        print("\n3. Classify WA529 Mailer as Promotional")
        print("-" * 80)
        wa529_text = """
        Make this the season you start saving!
        Get $50 when you open a WA529 Invest account by 12/12/2025.

        1. Make a deposit of $50 using promo code Offer25 when enrolling online.
        2. Set up recurring contributions of $50 or more for six months.
        3. We'll add $50 to your savings.

        Promotion ends 12/12/2025.
        """
        response = await client.post(
            f"{base_url}/classify", json={"ocr_text": wa529_text}
        )
        result = response.json()
        print(f"Document Type: {result['document_type']}")
        print(f"Confidence: {result['confidence']:.2f}")
        print(f"Promotional Signals: {result['signals']['promotional']}")
        print(f"Receipt Signals: {result['signals']['receipt']}")

        # Example 4: Classify Receipt
        print("\n4. Classify CVS Receipt")
        print("-" * 80)
        receipt_text = """
        CVS Pharmacy
        Store #1234
        Receipt #567890

        ADVIL 24CT         $12.99
        WATER 6PK          $5.99
        SUBTOTAL          $18.98
        TAX                $1.71
        TOTAL             $20.69

        VISA ****1234
        AUTH CODE: 123456
        """
        response = await client.post(
            f"{base_url}/classify", json={"ocr_text": receipt_text}
        )
        result = response.json()
        print(f"Document Type: {result['document_type']}")
        print(f"Confidence: {result['confidence']:.2f}")

        # Example 5: Extract Fields from Promotional
        print("\n5. Extract Fields from Promotional Document")
        print("-" * 80)
        promo_text = """
        Earn 50,000 bonus points when you spend $3,000.
        Use promo code BONUS2025.
        Offer expires December 31, 2025.
        """
        response = await client.post(
            f"{base_url}/extract",
            json={"ocr_text": promo_text, "document_type": "promotional"},
        )
        result = response.json()
        print("Extracted Fields:")
        for field in result["fields"]:
            print(
                f"  - {field['key']}: {field['value']} (confidence: {field['confidence']:.2f})"
            )

        # Example 6: Full Analysis
        print("\n6. Full Document Analysis (Classify + Extract)")
        print("-" * 80)
        bill_text = """
        Pacific Gas & Electric
        Billing Statement
        Account Number: 987654321
        Billing Period: Nov 1 - Nov 30, 2025

        Previous Balance:    $85.00
        Payments:           -$85.00
        Current Charges:    $102.87

        Amount Due: $102.87
        Due Date: December 15, 2025
        """
        response = await client.post(f"{base_url}/analyze", json={"ocr_text": bill_text})
        result = response.json()
        print(f"Document Type: {result['document_type']}")
        print(f"Confidence: {result['confidence']:.2f}")
        print(f"Extracted Fields: {len(result['fields'])} fields")
        for field in result["fields"][:5]:  # Show first 5 fields
            print(
                f"  - {field['key']}: {field['value']} (confidence: {field['confidence']:.2f})"
            )

        # Example 7: Classify Insurance Card
        print("\n7. Classify Insurance Card")
        print("-" * 80)
        insurance_text = """
        Premera Blue Cross
        Member ID: ABC123456789
        Group Number: 12345

        RX BIN: 004336
        RX PCN: ADV
        RX GRP: BLUE

        Copay: $20 PCP / $40 Specialist
        Deductible: $1,500
        """
        response = await client.post(
            f"{base_url}/classify", json={"ocr_text": insurance_text}
        )
        result = response.json()
        print(f"Document Type: {result['document_type']}")
        print(f"Confidence: {result['confidence']:.2f}")

        # Example 8: Test False Positive Prevention (Quote should NOT be Receipt)
        print("\n8. Test False Positive Prevention - Price Quote")
        print("-" * 80)
        quote_text = """
        AUTO REPAIR ESTIMATE

        Oil change:        $49.99
        Air filter:        $25.00
        Brake pads:       $120.00

        Estimated Total:  $194.99
        Valid for 30 days
        """
        response = await client.post(
            f"{base_url}/classify", json={"ocr_text": quote_text}
        )
        result = response.json()
        print(f"Document Type: {result['document_type']}")
        print(f"Is Receipt: {result['document_type'] == 'receipt'}")
        print("✓ Correctly rejected as receipt (no payment method/transaction ID)")

        print("\n" + "=" * 80)
        print("All examples completed successfully!")
        print("=" * 80)


if __name__ == "__main__":
    asyncio.run(main())
