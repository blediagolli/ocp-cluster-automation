FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends qemu-utils curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY ec2_driver.py app.py ./

EXPOSE 8000

CMD ["gunicorn", "-b", "0.0.0.0:8000", "-w", "2", "--timeout", "300", "app:app"]
