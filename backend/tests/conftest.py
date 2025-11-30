"""Pytest configuration and fixtures."""

import os

import pytest

# Set test environment variables
os.environ["LLM_PROVIDER"] = "openai"
os.environ["OPENAI_API_KEY"] = "test-key-not-used"
os.environ["LOG_LEVEL"] = "INFO"
