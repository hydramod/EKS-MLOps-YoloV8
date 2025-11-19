// Configuration
const API_URL = window.location.hostname === 'localhost'
    ? 'http://localhost:5000'
    : window.location.protocol + '//' + window.location.hostname;

// DOM Elements
const uploadBox = document.getElementById('uploadBox');
const imageInput = document.getElementById('imageInput');
const resultsSection = document.getElementById('resultsSection');
const loading = document.getElementById('loading');
const preview = document.getElementById('preview');
const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');
const detectionsList = document.getElementById('detectionsList');
const resetBtn = document.getElementById('resetBtn');
const backendStatus = document.getElementById('backendStatus');

// Mode toggle elements
const uploadModeBtn = document.getElementById('uploadModeBtn');
const webcamModeBtn = document.getElementById('webcamModeBtn');
const uploadSection = document.getElementById('uploadSection');
const webcamSection = document.getElementById('webcamSection');

// Webcam elements
const webcam = document.getElementById('webcam');
const webcamCanvas = document.getElementById('webcamCanvas');
const webcamCtx = webcamCanvas.getContext('2d');
const startWebcamBtn = document.getElementById('startWebcamBtn');
const stopWebcamBtn = document.getElementById('stopWebcamBtn');
const webcamDetectionsList = document.getElementById('webcamDetectionsList');
const webcamStats = document.getElementById('webcamStats');
const fpsCounter = document.getElementById('fpsCounter');
const detectionCounter = document.getElementById('detectionCounter');
const webcamStatus = document.getElementById('webcamStatus');

// Webcam state
let webcamStream = null;
let webcamActive = false;
let detectionInterval = null;
let frameCount = 0;
let lastFpsUpdate = Date.now();
let currentFps = 0;

// Check backend health on load
checkBackendHealth();

// Mode toggle handlers
uploadModeBtn.addEventListener('click', () => switchMode('upload'));
webcamModeBtn.addEventListener('click', () => switchMode('webcam'));

// Upload box click
uploadBox.addEventListener('click', () => {
    imageInput.click();
});

// File input change
imageInput.addEventListener('change', (e) => {
    const file = e.target.files[0];
    if (file) {
        handleImageUpload(file);
    }
});

// Drag and drop
uploadBox.addEventListener('dragover', (e) => {
    e.preventDefault();
    uploadBox.classList.add('dragover');
});

uploadBox.addEventListener('dragleave', () => {
    uploadBox.classList.remove('dragover');
});

uploadBox.addEventListener('drop', (e) => {
    e.preventDefault();
    uploadBox.classList.remove('dragover');
    const file = e.dataTransfer.files[0];
    if (file && file.type.startsWith('image/')) {
        handleImageUpload(file);
    }
});

// Reset button
resetBtn.addEventListener('click', () => {
    resultsSection.style.display = 'none';
    uploadSection.style.display = 'block';
    imageInput.value = '';
});

// Webcam controls
startWebcamBtn.addEventListener('click', startWebcam);
stopWebcamBtn.addEventListener('click', stopWebcam);

// Switch between upload and webcam mode
function switchMode(mode) {
    if (mode === 'upload') {
        // Stop webcam if active
        if (webcamActive) {
            stopWebcam();
        }
        
        uploadModeBtn.classList.add('active');
        webcamModeBtn.classList.remove('active');
        uploadSection.style.display = 'block';
        webcamSection.style.display = 'none';
        resultsSection.style.display = 'none';
    } else if (mode === 'webcam') {
        uploadModeBtn.classList.remove('active');
        webcamModeBtn.classList.add('active');
        uploadSection.style.display = 'none';
        webcamSection.style.display = 'block';
        resultsSection.style.display = 'none';
    }
}

// Start webcam
async function startWebcam() {
    try {
        webcamStatus.textContent = 'Requesting camera access...';
        
        // Request camera access
        webcamStream = await navigator.mediaDevices.getUserMedia({
            video: {
                width: { ideal: 1280 },
                height: { ideal: 720 },
                facingMode: 'user'
            }
        });

        webcam.srcObject = webcamStream;
        webcamActive = true;

        // Wait for video to be ready
        await new Promise((resolve) => {
            webcam.onloadedmetadata = () => {
                resolve();
            };
        });

        // Set canvas size to match video
        webcamCanvas.width = webcam.videoWidth;
        webcamCanvas.height = webcam.videoHeight;

        // Update UI
        startWebcamBtn.style.display = 'none';
        stopWebcamBtn.style.display = 'inline-flex';
        webcamStats.style.display = 'flex';
        webcamStatus.textContent = 'Running';

        // Start detection loop
        frameCount = 0;
        lastFpsUpdate = Date.now();
        detectWebcamFrame();

    } catch (error) {
        console.error('Error accessing webcam:', error);
        webcamStatus.textContent = 'Error';
        alert('Failed to access webcam. Please ensure you have granted camera permissions.');
    }
}

// Stop webcam
function stopWebcam() {
    if (webcamStream) {
        webcamStream.getTracks().forEach(track => track.stop());
        webcamStream = null;
    }

    if (detectionInterval) {
        clearTimeout(detectionInterval);
        detectionInterval = null;
    }

    webcamActive = false;
    webcam.srcObject = null;
    webcamCtx.clearRect(0, 0, webcamCanvas.width, webcamCanvas.height);

    // Update UI
    startWebcamBtn.style.display = 'inline-flex';
    stopWebcamBtn.style.display = 'none';
    webcamStats.style.display = 'none';
    webcamDetectionsList.innerHTML = '';
}

// Detect objects in webcam frame
async function detectWebcamFrame() {
    if (!webcamActive) return;

    try {
        // Draw current frame to canvas
        webcamCtx.drawImage(webcam, 0, 0, webcamCanvas.width, webcamCanvas.height);

        // Convert canvas to blob
        const blob = await new Promise(resolve => webcamCanvas.toBlob(resolve, 'image/jpeg', 0.8));

        // Send to backend
        const formData = new FormData();
        formData.append('image', blob, 'frame.jpg');

        const response = await fetch(`${API_URL}/predict`, {
            method: 'POST',
            body: formData
        });

        if (response.ok) {
            const data = await response.json();
            drawWebcamDetections(data);
            updateWebcamDetectionsList(data.detections);

            // Update FPS counter
            frameCount++;
            const now = Date.now();
            if (now - lastFpsUpdate >= 1000) {
                currentFps = frameCount;
                fpsCounter.textContent = currentFps;
                frameCount = 0;
                lastFpsUpdate = now;
            }
        }

    } catch (error) {
        console.error('Detection error:', error);
    }

    // Schedule next frame (aim for ~10 FPS to avoid overloading)
    detectionInterval = setTimeout(detectWebcamFrame, 100);
}

// Draw detections on webcam canvas
function drawWebcamDetections(data) {
    // Redraw video frame
    webcamCtx.drawImage(webcam, 0, 0, webcamCanvas.width, webcamCanvas.height);

    if (!data.detections || data.detections.length === 0) {
        detectionCounter.textContent = '0';
        return;
    }

    detectionCounter.textContent = data.detections.length;

    // Draw bounding boxes
    webcamCtx.strokeStyle = '#667eea';
    webcamCtx.lineWidth = 3;
    webcamCtx.font = '16px Arial';

    data.detections.forEach(detection => {
        const x1 = detection.bbox.x1;
        const y1 = detection.bbox.y1;
        const x2 = detection.bbox.x2;
        const y2 = detection.bbox.y2;

        // Draw rectangle
        webcamCtx.strokeRect(x1, y1, x2 - x1, y2 - y1);

        // Draw label background
        const label = `${detection.class} ${(detection.confidence * 100).toFixed(1)}%`;
        const textWidth = webcamCtx.measureText(label).width;
        webcamCtx.fillStyle = '#667eea';
        webcamCtx.fillRect(x1, y1 - 25, textWidth + 10, 25);

        // Draw label text
        webcamCtx.fillStyle = 'white';
        webcamCtx.fillText(label, x1 + 5, y1 - 7);
    });
}

// Update webcam detections list
function updateWebcamDetectionsList(detections) {
    webcamDetectionsList.innerHTML = '';

    if (!detections || detections.length === 0) {
        webcamDetectionsList.innerHTML = '<p style="color: #718096;">No objects detected</p>';
        return;
    }

    // Group detections by class
    const grouped = {};
    detections.forEach(detection => {
        if (!grouped[detection.class]) {
            grouped[detection.class] = [];
        }
        grouped[detection.class].push(detection);
    });

    // Display grouped detections
    Object.keys(grouped).sort().forEach(className => {
        const items = grouped[className];
        const avgConfidence = items.reduce((sum, item) => sum + item.confidence, 0) / items.length;

        const item = document.createElement('div');
        item.className = 'detection-item';
        item.innerHTML = `
            <div class="detection-class">${className}</div>
            <div class="detection-confidence">
                Count: ${items.length} | Avg Confidence: ${(avgConfidence * 100).toFixed(2)}%
            </div>
        `;
        webcamDetectionsList.appendChild(item);
    });
}

// Check backend health
async function checkBackendHealth() {
    try {
        const response = await fetch(`${API_URL}/health`);
        const data = await response.json();
        if (data.status === 'ok') {
            backendStatus.textContent = 'Online ✓';
            backendStatus.classList.add('online');
        } else {
            backendStatus.textContent = 'Error';
            backendStatus.classList.add('offline');
        }
    } catch (error) {
        backendStatus.textContent = 'Offline ✗';
        backendStatus.classList.add('offline');
        console.error('Backend health check failed:', error);
    }
}

// Handle image upload
async function handleImageUpload(file) {
    // Validate file size (10MB max)
    if (file.size > 10 * 1024 * 1024) {
        alert('File size exceeds 10MB. Please choose a smaller image.');
        return;
    }

    // Show loading
    uploadSection.style.display = 'none';
    loading.style.display = 'block';

    // Create form data
    const formData = new FormData();
    formData.append('image', file);

    try {
        // Send to backend
        const response = await fetch(`${API_URL}/predict`, {
            method: 'POST',
            body: formData
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();

        // Display results
        displayResults(file, data);

    } catch (error) {
        console.error('Error:', error);
        alert('Failed to process image. Please check if the backend is running.');
        loading.style.display = 'none';
        uploadSection.style.display = 'block';
    }
}

// Display results
function displayResults(file, data) {
    loading.style.display = 'none';
    resultsSection.style.display = 'grid';

    // Load and display image
    const reader = new FileReader();
    reader.onload = (e) => {
        preview.src = e.target.result;
        preview.onload = () => {
            // Set canvas size to match image
            canvas.width = preview.width;
            canvas.height = preview.height;

            // Calculate scale factors
            const scaleX = preview.width / data.image_size.width;
            const scaleY = preview.height / data.image_size.height;

            // Draw bounding boxes
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            ctx.strokeStyle = '#667eea';
            ctx.lineWidth = 3;
            ctx.font = '16px Arial';
            ctx.fillStyle = '#667eea';

            data.detections.forEach(detection => {
                const x1 = detection.bbox.x1 * scaleX;
                const y1 = detection.bbox.y1 * scaleY;
                const x2 = detection.bbox.x2 * scaleX;
                const y2 = detection.bbox.y2 * scaleY;

                // Draw rectangle
                ctx.strokeRect(x1, y1, x2 - x1, y2 - y1);

                // Draw label background
                const label = `${detection.class} ${(detection.confidence * 100).toFixed(1)}%`;
                const textWidth = ctx.measureText(label).width;
                ctx.fillStyle = '#667eea';
                ctx.fillRect(x1, y1 - 25, textWidth + 10, 25);

                // Draw label text
                ctx.fillStyle = 'white';
                ctx.fillText(label, x1 + 5, y1 - 7);
            });
        };
    };
    reader.readAsDataURL(file);

    // Display detection list
    detectionsList.innerHTML = '';
    if (data.detections.length === 0) {
        detectionsList.innerHTML = '<p style="color: #718096;">No objects detected</p>';
    } else {
        data.detections.forEach((detection, index) => {
            const item = document.createElement('div');
            item.className = 'detection-item';
            item.innerHTML = `
                <div class="detection-class">${detection.class}</div>
                <div class="detection-confidence">Confidence: ${(detection.confidence * 100).toFixed(2)}%</div>
                <div class="detection-bbox">
                    Box: (${Math.round(detection.bbox.x1)}, ${Math.round(detection.bbox.y1)}) -
                    (${Math.round(detection.bbox.x2)}, ${Math.round(detection.bbox.y2)})
                </div>
            `;
            detectionsList.appendChild(item);
        });
    }
}

// Refresh health check every 30 seconds
setInterval(checkBackendHealth, 30000);