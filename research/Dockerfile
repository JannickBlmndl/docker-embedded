FROM python:3.12-slim

RUN apt-get update && apt-get install -y curl && apt-get clean

# Install uv
# RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# ENV PATH="/root/.local/bin:${PATH}"

WORKDIR /app

# Create uv venv and install numpy
# RUN uv venv .venv
# RUN uv pip install numpy

RUN pip install --no-cache-dir numpy

ENTRYPOINT ["python3"]

# Entry point runs uv
# ENTRYPOINT ["uv", "run"]