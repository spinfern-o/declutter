FROM python:3.12-slim

# opencv (pulled in by ultralytics) needs these shared libs
RUN apt-get update && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# CPU-only torch first, so ultralytics doesn't pull the multi-GB CUDA build
RUN pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY detect.py .
COPY server/ server/
COPY train/classes.csv train/classes.csv
COPY models/best.pt models/best.pt
COPY models3d/ models3d/

EXPOSE 8080
CMD ["uvicorn", "server.app:app", "--host", "0.0.0.0", "--port", "8080"]
