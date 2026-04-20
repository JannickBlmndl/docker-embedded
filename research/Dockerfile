FROM python:3.12-slim

RUN apt-get update && apt-get install -y curl && apt-get clean

WORKDIR /app

RUN pip install --no-cache-dir numpy

ENTRYPOINT ["python3"]
