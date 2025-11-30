"""Upload sample photo and audio files to exercise media upload endpoints.

This script is intentionally lightweight and does not assume a specific upload
response. Point it at your running API and it will send a tiny PNG and a short
WAV tone to the provided endpoints.

Examples:
    python examples/upload_media_test.py \\
        --base-url http://localhost:8000 \\
        --photo-endpoint /api/v1/upload/image \\
        --audio-endpoint /api/v1/upload/audio

Environment overrides:
    FOLIOMIND_API_BASE_URL
    FOLIOMIND_PHOTO_ENDPOINT
    FOLIOMIND_AUDIO_ENDPOINT
    FOLIOMIND_UPLOAD_FIELD
    FOLIOMIND_API_KEY
    FOLIOMIND_API_TIMEOUT
"""

import argparse
import asyncio
import base64
import math
import os
import tempfile
import wave
from array import array
from pathlib import Path
from typing import Dict, Iterable

import httpx
from PIL import Image, ImageDraw, ImageFont


def build_url(base_url: str, endpoint: str) -> str:
    """Join base URL and endpoint without dropping path segments."""
    return base_url.rstrip("/") + "/" + endpoint.lstrip("/")


def parse_metadata(pairs: Iterable[str]) -> Dict[str, str]:
    """Parse key=value pairs from CLI flags."""
    metadata: Dict[str, str] = {}
    for pair in pairs:
        if "=" not in pair:
            print(f"Skipping metadata entry '{pair}' (expected key=value)")
            continue
        key, value = pair.split("=", 1)
        if key:
            metadata[key] = value
    return metadata


def write_sample_image(path: Path) -> Path:
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
    image.save(path, 'PNG')
    return path


def write_sample_audio(path: Path, duration: float = 1.0) -> Path:
    """Generate a short mono WAV tone for upload testing."""
    sample_rate = 16_000
    frequency = 440  # A4 tone
    amplitude = int(0.2 * (2**15 - 1))
    total_frames = int(duration * sample_rate)

    frames = array("h")
    for i in range(total_frames):
        sample = int(amplitude * math.sin(2 * math.pi * frequency * i / sample_rate))
        frames.append(sample)

    with wave.open(str(path), "w") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)  # 16-bit audio
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(frames.tobytes())

    return path


async def upload_media(
    client: httpx.AsyncClient,
    url: str,
    file_path: Path,
    mime_type: str,
    file_field: str,
    headers: Dict[str, str],
    form_fields: Dict[str, str],
) -> httpx.Response:
    """Upload a single file with optional metadata."""
    payload = {key: str(value) for key, value in form_fields.items()}
    print(f"-> Uploading {file_path.name} ({mime_type}) to {url}")
    with file_path.open("rb") as file_handle:
        files = {file_field: (file_path.name, file_handle, mime_type)}
        response = await client.post(url, headers=headers, data=payload, files=files)
    return response


def print_response(label: str, response: httpx.Response) -> None:
    """Pretty-print the response body."""
    print(f"<- {label} response {response.status_code}")
    content_type = response.headers.get("content-type", "")
    if "application/json" in content_type:
        try:
            print(response.json())
            return
        except Exception:
            pass
    print(response.text)


async def main() -> None:
    parser = argparse.ArgumentParser(
        description="Upload sample photo/audio files to FolioMind API endpoints."
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("FOLIOMIND_API_BASE_URL", "http://localhost:8000"),
        help="API base URL (default: http://localhost:8000 or FOLIOMIND_API_BASE_URL)",
    )
    parser.add_argument(
        "--photo-endpoint",
        default=os.environ.get("FOLIOMIND_PHOTO_ENDPOINT", "/api/v1/upload/image"),
        help="Endpoint that accepts image uploads",
    )
    parser.add_argument(
        "--audio-endpoint",
        default=os.environ.get("FOLIOMIND_AUDIO_ENDPOINT", "/api/v1/upload/audio"),
        help="Endpoint that accepts audio uploads",
    )
    parser.add_argument(
        "--photo-path",
        type=Path,
        help="Optional path to an image to upload (defaults to generated sample)",
    )
    parser.add_argument(
        "--audio-path",
        type=Path,
        help="Optional path to an audio file to upload (defaults to generated sample)",
    )
    parser.add_argument(
        "--file-field",
        default=os.environ.get("FOLIOMIND_UPLOAD_FIELD", "file"),
        help="Multipart form field name for the file",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("FOLIOMIND_API_KEY"),
        help="Bearer token for Authorization header, if required",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=float(os.environ.get("FOLIOMIND_API_TIMEOUT", 30)),
        help="Request timeout in seconds",
    )
    parser.add_argument(
        "--metadata",
        action="append",
        default=[],
        metavar="key=value",
        help="Extra form fields to include with uploads",
    )
    parser.add_argument(
        "--skip-photo",
        action="store_true",
        help="Skip uploading the photo sample",
    )
    parser.add_argument(
        "--skip-audio",
        action="store_true",
        help="Skip uploading the audio sample",
    )

    args = parser.parse_args()
    headers: Dict[str, str] = {}
    if args.api_key:
        headers["Authorization"] = f"Bearer {args.api_key}"

    metadata = parse_metadata(args.metadata)
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        async with httpx.AsyncClient(timeout=args.timeout) as client:
            if not args.skip_photo:
                photo_path = args.photo_path or write_sample_image(
                    temp_path / "sample-upload.png"
                )
                response = await upload_media(
                    client=client,
                    url=build_url(args.base_url, args.photo_endpoint),
                    file_path=photo_path,
                    mime_type="image/png",
                    file_field=args.file_field,
                    headers=headers,
                    form_fields={**metadata, "kind": "photo"},
                )
                print_response("Photo upload", response)

            if not args.skip_audio:
                audio_path = args.audio_path or write_sample_audio(
                    temp_path / "sample-tone.wav"
                )
                response = await upload_media(
                    client=client,
                    url=build_url(args.base_url, args.audio_endpoint),
                    file_path=audio_path,
                    mime_type="audio/wav",
                    file_field=args.file_field,
                    headers=headers,
                    form_fields={**metadata, "kind": "audio"},
                )
                print_response("Audio upload", response)


if __name__ == "__main__":
    asyncio.run(main())
