FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the entire app folder structure
COPY . .

# Install gunicorn
RUN pip install gunicorn

# Expose the port (Cloud Run defaults to 8080)
EXPOSE 8080

# --- THE FIX ---
# 1. PYTHONPATH: Ensures Python can find the 'app' module
# 2. CMD: Points to 'run.py' (the file) and 'app' (the object inside it)
ENV PYTHONPATH=/app
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "run:app"]