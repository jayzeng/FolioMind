"""Classification tests based on the strategy document test cases.

Tests cover lines 86-273 of the classification strategy, including:
- Receipts (test cases 1-6)
- Promotional content (test cases 7-11)
- Bills (test cases 12-18)
- Insurance cards (test cases 19-24)
- Credit cards (test cases 25-31)
- Letters (test cases 32-37)
- False positives (test cases 38-41)
- Edge cases (test cases 42-45)
"""

import pytest

from app.models import DocumentType
from app.services import ClassificationService


class TestReceiptClassification:
    """Test receipt classification - lines 86-108."""

    def test_cvs_receipt(self):
        """Test case 1: CVS receipt with full transaction."""
        text = """
        CVS Pharmacy
        Receipt #456
        ADVIL $12.99
        Total: $12.99
        VISA ****1234
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.RECEIPT
        assert confidence >= 0.85

    def test_restaurant_receipt(self):
        """Test case 2: Restaurant receipt."""
        text = """
        The Italian Kitchen
        Server: John
        Table: 5
        Pasta $18.99
        Wine $12.00
        Subtotal: $30.99
        Tax: $2.79
        Total: $33.78
        Tip: _______
        VISA ****5678
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.RECEIPT
        assert confidence >= 0.85

    def test_gas_station_receipt(self):
        """Test case 3: Gas station receipt."""
        text = """
        Shell Gas Station
        Pump #4
        Gallons: 12.5
        Price per gallon: $3.89
        Total: $48.63
        Approval Code: 123456
        MASTERCARD ****9012
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.RECEIPT
        assert confidence >= 0.85

    def test_receipt_with_promo_footer(self):
        """Test case 4: Receipt with promotional footer."""
        text = """
        WALGREENS Receipt #456
        TYLENOL $15.99
        Total: $15.99
        VISA ****1234

        *** SAVE $5 ON YOUR NEXT VISIT ***
        Use code: SAVE5
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        # Should be receipt (transaction takes precedence)
        assert doc_type == DocumentType.RECEIPT

    def test_receipt_with_applied_coupon(self):
        """Test case 6: Receipt with applied coupon."""
        text = """
        TARGET
        Receipt #789
        Item A: $25.00
        Coupon: -$3.00
        Subtotal: $22.00
        Tax: $1.98
        Total: $23.98
        VISA ****3456
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.RECEIPT


class TestPromotionalClassification:
    """Test promotional content classification - lines 110-140."""

    def test_wa529_mailer(self):
        """Test case 7: WA529 mailer (critical fix)."""
        text = """
        Make this the season you start saving!
        Get $50 when you open a WA529 Invest account by 12/3/2025 and 12/12/2025.

        1. Make a deposit of $50 using promo code Offer25 when enrolling online.
        2. Set up recurring contributions of $50 or more for at least six consecutive months.
        3. We'll add $50 to your savings.

        Visit 529Invest.wa.gov/Offer25
        Promotion ends 12/12/2025.
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.PROMOTIONAL
        assert confidence >= 0.75

    def test_credit_card_offer(self):
        """Test case 8: Credit card offer."""
        text = """
        Earn 60,000 bonus points when you spend $4,000 in the first 3 months.

        Apply now for the Premium Rewards Card.
        Offer expires March 31, 2025.
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.PROMOTIONAL

    def test_retail_coupon(self):
        """Test case 9: Retail coupon."""
        text = """
        SAVE 20% ON YOUR NEXT PURCHASE

        Use code: SAVE20
        Valid through December 31, 2025
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.PROMOTIONAL

    def test_subscription_trial(self):
        """Test case 10: Subscription trial offer."""
        text = """
        Try Spotify Premium Free for 3 Months

        Sign up today and you'll get unlimited music with no ads.
        Cancel anytime. Offer ends soon.
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.PROMOTIONAL

    def test_promotional_letter(self):
        """Test case 37: Promotional letter (intent over format)."""
        text = """
        Dear Customer,

        Join our rewards program and earn bonus points!
        Sign up today and receive 1000 points.

        Sincerely,
        Marketing Team
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        # Should be promotional (intent over format)
        assert doc_type == DocumentType.PROMOTIONAL


class TestBillClassification:
    """Test bill statement classification - lines 142-167."""

    def test_electric_utility_bill(self):
        """Test case 12: Electric utility bill."""
        text = """
        Electric Company
        Billing Statement
        Account Number: 123456789
        Billing Period: Nov 1 - Nov 30, 2025
        Usage: 850 kWh
        Amount Due: $102.87
        Due Date: December 15, 2025
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.BILL_STATEMENT

    def test_medical_bill(self):
        """Test case 13: Medical bill."""
        text = """
        Swedish Medical Center
        Statement Date: 11/20/2025
        Insurance Paid: $285.00
        Patient Responsibility: $35.00
        Amount Due: $35.00
        Due Date: 12/20/2025
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.BILL_STATEMENT

    def test_credit_card_statement(self):
        """Test case 14: Credit card statement."""
        text = """
        Credit Card Statement
        Account Number: ****5678
        Statement Date: 11/25/2025
        Previous Balance: $500.00
        New Charges: $250.00
        Total Balance: $750.00
        Minimum Payment Due: $35.00
        Payment Due Date: 12/20/2025
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.BILL_STATEMENT


class TestInsuranceCardClassification:
    """Test insurance card classification - lines 169-196."""

    def test_health_insurance_card(self):
        """Test case 19: Health insurance card."""
        text = """
        Premera Blue Cross
        Member ID: ABC123456789
        Group: 12345
        RX BIN: 004336
        RX PCN: ADV
        RX GRP: BLUE
        Copay: $20 PCP / $40 Specialist
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.INSURANCE_CARD
        assert confidence >= 0.85

    def test_dental_insurance_card(self):
        """Test case 20: Dental insurance card."""
        text = """
        Delta Dental
        Subscriber ID: XYZ987654321
        Plan Type: PPO
        Coverage: 100% Preventive / 80% Basic / 50% Major
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.INSURANCE_CARD

    def test_insurance_summary_not_card(self):
        """Test case 22: Insurance summary (NOT a card)."""
        text = """
        YOUR HEALTH COVERAGE SUMMARY
        This is not an insurance card.
        Member ID: ABC123
        Summary of benefits for 2025.
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        # Should NOT be insurance card
        assert doc_type != DocumentType.INSURANCE_CARD


class TestCreditCardClassification:
    """Test credit card classification - lines 198-223."""

    def test_visa_credit_card(self):
        """Test case 25: Visa credit card."""
        text = """
        VISA
        4532 1234 5678 9012
        VALID THRU: 12/27
        JOHN DOE
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.CREDIT_CARD

    def test_gift_card_not_credit_card(self):
        """Test case 28: Gift card (NOT credit card)."""
        text = """
        STARBUCKS GIFT CARD
        6001 2345 6789 0123
        Balance: $50.00
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        # Should NOT be credit card
        assert doc_type != DocumentType.CREDIT_CARD


class TestLetterClassification:
    """Test letter classification - lines 225-245."""

    def test_formal_business_letter(self):
        """Test case 32: Formal business letter."""
        text = """
        Dear Mr. Smith,

        We are writing to inform you about the upcoming changes
        to your account. Please review the enclosed documents.

        Sincerely,
        Jane Johnson
        Account Manager
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.LETTER

    def test_personal_letter(self):
        """Test case 33: Personal letter."""
        text = """
        Dear Sarah,

        It was wonderful to see you last week. I hope we can
        meet again soon for coffee.

        Warm regards,
        Emily
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.LETTER


class TestFalsePositives:
    """Test false positive prevention - lines 247-262."""

    def test_price_quote_not_receipt(self):
        """Test case 38: Price quote (NOT receipt)."""
        text = """
        AUTO REPAIR ESTIMATE
        Oil change: $49.99
        Air filter: $25.00
        Estimated Total: $74.99
        Valid for 30 days
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        # Should NOT be receipt
        assert doc_type != DocumentType.RECEIPT
        assert doc_type == DocumentType.GENERIC

    def test_shopping_list_not_receipt(self):
        """Test case 39: Shopping list (NOT receipt)."""
        text = """
        Shopping List
        Milk - $4.99
        Bread - $3.49
        Eggs - $5.99
        Approximate total: $14.47
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        # Should NOT be receipt
        assert doc_type != DocumentType.RECEIPT


class TestEdgeCases:
    """Test edge cases - lines 264-273."""

    def test_minimalist_digital_receipt(self):
        """Test case 43: Minimalist digital receipt."""
        text = """
        Apple Store
        Order #W123456789
        iPhone Case: $29.99
        Total: $29.99
        VISA ****1234
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.RECEIPT

    def test_cash_receipt(self):
        """Test case: Cash receipt without card info."""
        text = """
        Corner Store
        Receipt #123
        Coffee: $2.50
        Total: $2.50
        Cash
        Change: $7.50
        """
        doc_type, confidence, _ = ClassificationService.classify(text)
        assert doc_type == DocumentType.RECEIPT
