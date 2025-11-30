#!/usr/bin/env python3
"""Generate a sample receipt image for testing."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


def generate_receipt_image(output_path: Path) -> Path:
    """Generate a sample receipt image with text."""
    # Create a white background image (receipt size)
    width, height = 400, 600
    image = Image.new('RGB', (width, height), color='white')
    draw = ImageDraw.Draw(image)

    # Try to use a default font, fall back to basic if unavailable
    try:
        # Try to load a monospace font for receipt-like appearance
        font_large = ImageFont.truetype("/System/Library/Fonts/Courier.dfont", 24)
        font_medium = ImageFont.truetype("/System/Library/Fonts/Courier.dfont", 18)
        font_small = ImageFont.truetype("/System/Library/Fonts/Courier.dfont", 14)
    except:
        # Fallback to default font
        font_large = ImageFont.load_default()
        font_medium = ImageFont.load_default()
        font_small = ImageFont.load_default()

    # Receipt text content
    y_position = 30
    line_height = 25

    def draw_text(text, font=font_medium, center=False):
        nonlocal y_position
        if center:
            bbox = draw.textbbox((0, 0), text, font=font)
            text_width = bbox[2] - bbox[0]
            x = (width - text_width) // 2
        else:
            x = 40
        draw.text((x, y_position), text, fill='black', font=font)
        y_position += line_height

    # Draw receipt content
    draw_text("CVS PHARMACY", font_large, center=True)
    draw_text("Store #1234", font_small, center=True)
    y_position += 10

    draw_text("Receipt #456789")
    draw_text("Date: 11/30/2025 14:32")
    y_position += 10

    draw_text("ADVIL TABLETS      $12.99")
    draw_text("VITAMIN C GUMMIES   $8.49")
    draw_text("HAND SANITIZER      $4.99")
    y_position += 10

    # Draw a line
    draw.line([(40, y_position), (width-40, y_position)], fill='black', width=2)
    y_position += 15

    draw_text("Subtotal:          $26.47")
    draw_text("Sales Tax:          $2.38")
    y_position += 5
    draw_text("Total:             $28.85", font_large)
    y_position += 15

    # Draw another line
    draw.line([(40, y_position), (width-40, y_position)], fill='black', width=2)
    y_position += 15

    draw_text("VISA ****1234")
    draw_text("Auth Code: 123456")
    y_position += 10

    draw_text("Thank you!", font_small, center=True)
    draw_text("for shopping at CVS!", font_small, center=True)

    # Save the image
    image.save(output_path, 'PNG')
    print(f"✓ Generated receipt image: {output_path}")
    print(f"  Size: {output_path.stat().st_size} bytes")
    print(f"  Dimensions: {width}x{height}")
    return output_path


if __name__ == "__main__":
    import sys

    output = Path("sample_receipt.png")
    if len(sys.argv) > 1:
        output = Path(sys.argv[1])

    generate_receipt_image(output)
    print(f"\nYou can now upload this file:")
    print(f"  curl -X POST http://localhost:8000/api/v1/upload/image -F 'file=@{output}'")
