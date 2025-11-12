"""
Flask API for YOLOv8 Object Detection
Provides /health and /predict endpoints
"""
import os
import io
import logging
from flask import Flask, request, jsonify
from flask_cors import CORS
from PIL import Image
import cv2
import numpy as np
from ultralytics import YOLO

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)  # Enable CORS for frontend requests

# Configuration from environment variables
MODEL_PATH = os.getenv('MODEL_PATH', 'models/yolov8n.pt')
CONFIDENCE_THRESHOLD = float(os.getenv('CONFIDENCE_THRESHOLD', '0.25'))
PORT = int(os.getenv('PORT', '5000'))

# Load YOLOv8 model
logger.info(f"Loading YOLOv8 model from {MODEL_PATH}")
try:
    model = YOLO(MODEL_PATH)
    logger.info("Model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load model: {e}")
    raise


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({"status": "ok", "model": MODEL_PATH}), 200


@app.route('/predict', methods=['POST'])
def predict():
    """
    Object detection endpoint
    Accepts image file and returns detections
    """
    try:
        # Check if image file is present
        if 'image' not in request.files:
            return jsonify({"error": "No image file provided"}), 400

        file = request.files['image']
        if file.filename == '':
            return jsonify({"error": "No image selected"}), 400

        # Read image
        image_bytes = file.read()
        image = Image.open(io.BytesIO(image_bytes))

        # Convert PIL Image to numpy array for YOLOv8
        image_np = np.array(image)

        # Run inference
        logger.info(f"Running inference on image: {file.filename}")
        results = model(image_np, conf=CONFIDENCE_THRESHOLD)

        # Parse results
        detections = []
        for result in results:
            boxes = result.boxes
            for box in boxes:
                detection = {
                    "class": result.names[int(box.cls[0])],
                    "confidence": float(box.conf[0]),
                    "bbox": {
                        "x1": float(box.xyxy[0][0]),
                        "y1": float(box.xyxy[0][1]),
                        "x2": float(box.xyxy[0][2]),
                        "y2": float(box.xyxy[0][3])
                    }
                }
                detections.append(detection)

        logger.info(f"Found {len(detections)} detections")

        return jsonify({
            "success": True,
            "detections": detections,
            "image_size": {
                "width": image.width,
                "height": image.height
            }
        }), 200

    except Exception as e:
        logger.error(f"Prediction error: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        "service": "YOLOv8 Object Detection API",
        "version": "1.0.0",
        "endpoints": {
            "/health": "Health check",
            "/predict": "Object detection (POST with image file)"
        }
    }), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT, debug=False)
