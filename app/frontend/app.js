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

// Check backend health on load
checkBackendHealth();

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
    uploadBox.parentElement.style.display = 'block';
    imageInput.value = '';
});

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
    uploadBox.parentElement.style.display = 'none';
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
        uploadBox.parentElement.style.display = 'block';
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
