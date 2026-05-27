FROM debian:bookworm-slim

# Install system dependencies required by Godot headless
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    unzip \
    libfontconfig1 \
    libasound2 \
    libdbus-1-3 \
    libfribidi0 \
    libharfbuzz0b \
    libxrender1 \
    libxext6 \
    libx11-6 \
    libxcursor1 \
    libxinerama1 \
    libxi6 \
    libxrandr1 \
    libxfixes3 \
    libgl1-mesa-dri \
    libgl1-mesa-glx \
    libgles2-mesa \
    libegl1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Set up Godot version (matching the desktop client version: 4.6.3 stable)
ENV GODOT_VERSION=4.6.3
ENV GODOT_FILENAME=Godot_v${GODOT_VERSION}-stable_linux.x86_64

# Download and extract Godot editor binary
RUN wget -q https://downloads.tuxfamily.org/godotengine/${GODOT_VERSION}/${GODOT_FILENAME}.zip \
    && unzip ${GODOT_FILENAME}.zip \
    && mv ${GODOT_FILENAME} /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm ${GODOT_FILENAME}.zip

# Create and set the working directory
WORKDIR /app

# Copy the game source code
COPY . .

# Convert Windows line endings to Unix and make the script executable
RUN chmod +x run_headless_server.sh \
    && sed -i 's/\r$//' run_headless_server.sh

# Expose the server UDP port (Godot's ENet uses UDP)
EXPOSE 8080/udp

# Run the headless server script
CMD ["./run_headless_server.sh"]
