# Python image to use. Pin to a specific minor for reproducibility; for stronger
# supply-chain guarantees, pin by digest (FROM python:3.12-slim@sha256:...).
FROM python:3.12-slim

# Set the working directory to /app
WORKDIR /app

# Do not write .pyc files (keeps the container filesystem clean at runtime)
ENV PYTHONDONTWRITEBYTECODE=1

# copy the requirements file used for dependencies
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the working directory contents into the container at /app
COPY . .

# Create and switch to a non-root user
RUN useradd --create-home --uid 1000 appuser
USER appuser

# Run app.py when the container launches
ENTRYPOINT ["python", "-u", "main.py"]