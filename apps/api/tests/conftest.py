import sys
import os
import pytest
from dotenv import load_dotenv

# 1. Add the parent directory (apps/api) to sys.path
# This allows us to do "from app import create_app"
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

load_dotenv()

from app import create_app

@pytest.fixture
def app():
    app = create_app()
    app.config.update({
        "TESTING": True,
    })
    yield app

@pytest.fixture
def client(app):
    return app.test_client()