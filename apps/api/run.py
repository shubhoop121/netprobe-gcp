import os
from app import create_app
from dotenv import load_dotenv

# Load environment variables (for local dev)
load_dotenv()

# Create the Flask application instance
app = create_app()

if __name__ == "__main__":
    # This block is only run when executing 'python run.py' locally
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=True)