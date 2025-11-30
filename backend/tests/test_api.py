"""API endpoint tests."""

import pytest
from httpx import AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_health_check():
    """Test health check endpoint."""
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/api/v1/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "version" in data
        assert "llm_provider" in data


@pytest.mark.asyncio
async def test_get_document_types():
    """Test document types endpoint."""
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/api/v1/types")
        assert response.status_code == 200
        data = response.json()
        assert "types" in data
        assert len(data["types"]) > 0
        # Check that promotional type is included
        types = [t["type"] for t in data["types"]]
        assert "promotional" in types
        assert "receipt" in types


@pytest.mark.asyncio
async def test_classify_wa529_promotional():
    """Test classification of WA529 mailer as promotional."""
    async with AsyncClient(app=app, base_url="http://test") as client:
        request_data = {
            "ocr_text": """
            Make this the season you start saving!
            Get $50 when you open a WA529 Invest account by 12/12/2025.
            Use promo code Offer25 when enrolling online.
            We'll add $50 to your savings.
            Promotion ends 12/12/2025.
            """
        }
        response = await client.post("/api/v1/classify", json=request_data)
        assert response.status_code == 200
        data = response.json()
        assert data["document_type"] == "promotional"
        assert data["confidence"] >= 0.7
        assert data["signals"]["promotional"] is True


@pytest.mark.asyncio
async def test_classify_receipt():
    """Test classification of receipt."""
    async with AsyncClient(app=app, base_url="http://test") as client:
        request_data = {
            "ocr_text": """
            CVS Pharmacy
            Receipt #12345
            Advil $12.99
            Total: $12.99
            VISA ****1234
            """
        }
        response = await client.post("/api/v1/classify", json=request_data)
        assert response.status_code == 200
        data = response.json()
        assert data["document_type"] == "receipt"
        assert data["signals"]["receipt"] is True
        assert data["signals"]["promotional"] is False


@pytest.mark.asyncio
async def test_extract_fields():
    """Test field extraction endpoint."""
    async with AsyncClient(app=app, base_url="http://test") as client:
        request_data = {
            "ocr_text": """
            Get $50 when you open account.
            Use promo code SAVE2025.
            Expires December 31, 2025.
            """,
            "document_type": "promotional",
        }
        response = await client.post("/api/v1/extract", json=request_data)
        assert response.status_code == 200
        data = response.json()
        assert "fields" in data
        # Should extract promo code
        field_keys = [f["key"] for f in data["fields"]]
        assert "promo_code" in field_keys or "offer_amount" in field_keys


@pytest.mark.asyncio
async def test_analyze_document():
    """Test full document analysis endpoint."""
    async with AsyncClient(app=app, base_url="http://test") as client:
        request_data = {
            "ocr_text": """
            Earn 50,000 bonus points when you spend $3,000.
            Apply now. Offer expires soon.
            """
        }
        response = await client.post("/api/v1/analyze", json=request_data)
        assert response.status_code == 200
        data = response.json()
        assert "document_type" in data
        assert "confidence" in data
        assert "signals" in data
        assert "fields" in data
        assert data["document_type"] == "promotional"


@pytest.mark.asyncio
async def test_root_endpoint():
    """Test root endpoint."""
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "running"
        assert "version" in data
