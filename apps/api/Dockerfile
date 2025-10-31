# apps/api/Dockerfile (Corrected)

# Use an official Python runtime as a parent image
FROM python:3.11-slim

# Set the working directory in the container
WORKDIR /app

# Copy the requirements file and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code
COPY . .

# Install Gunicorn for production
RUN pip install gunicorn

# Cloud Run expects the container to listen on $PORT
# We default to 8080 if $PORT isn't set
EXPOSE ${PORT:-8080}

# --- THIS IS THE FIX ---
# Use the $PORT environment variable in the command.
# Use 'sh -c' to allow shell evaluation of the $PORT variable.
CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT:-8080} --workers 2 app:app"]