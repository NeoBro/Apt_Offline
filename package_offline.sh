#!/bin/bash

# Check if a package name was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <package_name> [architecture] [distro]"
  echo "Example: $0 git"
  echo "Example: $0 git arm64"
  echo "Example: $0 git arm64 20.04"
  exit 1
fi

PACKAGE_NAME=$1
ARCHITECTURE=${2:-amd64} # Default to amd64 if no architecture is provided
DISTRO=${3:-22.04}       # Default to 22.04 if no distro is provided
OUTPUT_DIR="${PACKAGE_NAME}-offline"
BASE_PACKAGE_DIR="${OUTPUT_DIR}/base_package"
DEPENDENCIES_DIR="${OUTPUT_DIR}/dependencies"
TEMP_DIR=$(mktemp -d)
MANIFEST_FILE="${OUTPUT_DIR}/ubuntu-${DISTRO}-${ARCHITECTURE}-manifest.txt"

echo "Debug Info:"
echo "PACKAGE_NAME: $PACKAGE_NAME"
echo "ARCHITECTURE: $ARCHITECTURE"
echo "DISTRO: $DISTRO"
echo "OUTPUT_DIR: $OUTPUT_DIR"
echo "BASE_PACKAGE_DIR: $BASE_PACKAGE_DIR"
echo "DEPENDENCIES_DIR: $DEPENDENCIES_DIR"
echo "TEMP_DIR: $TEMP_DIR"
echo "MANIFEST_FILE: $MANIFEST_FILE"

# Ensure apt-rdepends is installed
if ! dpkg -s apt-rdepends >/dev/null 2>&1; then
  echo "apt-rdepends is not installed. Please install it first using 'sudo apt install apt-rdepends'."
  exit 1
fi

# Function to download the manifest file if it doesn't exist
download_manifest() {
  if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Downloading package manifest for Ubuntu ${DISTRO} (${ARCHITECTURE})..."
    curl -O "http://archive.ubuntu.com/ubuntu/dists/jammy/main/binary-${ARCHITECTURE}/Packages.gz"
    if [ -f Packages.gz ]; then
      gunzip -c Packages.gz > "$MANIFEST_FILE"
      rm Packages.gz
    else
      echo "Failed to download the manifest file."
      exit 1
    fi
  else
    echo "Manifest file already exists: $MANIFEST_FILE"
  fi
}

# Check and download manifest file
download_manifest

# Create directories if they don't already exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$BASE_PACKAGE_DIR"
mkdir -p "$DEPENDENCIES_DIR"
echo "Created directories: $OUTPUT_DIR, $BASE_PACKAGE_DIR, and $DEPENDENCIES_DIR"

# Download the target package
echo "Downloading target package: $PACKAGE_NAME"
apt-get download "${PACKAGE_NAME}:${ARCHITECTURE}"

# Find and move the downloaded package to the base package directory
TARGET_PACKAGE=$(find . -maxdepth 1 -name "${PACKAGE_NAME}_*.deb" -print -quit)
if [ -n "$TARGET_PACKAGE" ]; then
  mv "$TARGET_PACKAGE" "$BASE_PACKAGE_DIR"
  echo "Target package found and moved: $TARGET_PACKAGE"
else
  echo "Error: Target package ${PACKAGE_NAME} not found."
  rm -rf "$TEMP_DIR"
  exit 1
fi

# Extract the dependencies from the target package
echo "Extracting dependencies for: $PACKAGE_NAME"
dpkg-deb -I "$BASE_PACKAGE_DIR/$(basename $TARGET_PACKAGE)" > "$TEMP_DIR/control.txt"
DEPENDENCIES=$(grep -oP '(?<=Depends: ).*' "$TEMP_DIR/control.txt" | sed 's/, /\n/g' | cut -d' ' -f1 | sed '/^$/d')

# Function to filter out packages in the base installation
filter_base_packages() {
  grep -F -x -v -f <(awk '/^Package: / {print $2}' "$MANIFEST_FILE") "$1"
}

# Compare the dependencies with the base manifest
echo "Comparing dependencies with the base manifest..."
echo "$DEPENDENCIES" > "$TEMP_DIR/dependencies.txt"
MISSING_DEPENDENCIES=$(filter_base_packages "$TEMP_DIR/dependencies.txt")

# Download the missing dependencies
echo "Downloading missing dependencies..."
for dep in $MISSING_DEPENDENCIES; do
  if apt-get download "$dep:${ARCHITECTURE}"; then
    # Find and move each downloaded dependency package to the dependencies directory
    DEP_PACKAGE=$(find . -maxdepth 1 -name "${dep}_*.deb" -print -quit)
    if [ -n "$DEP_PACKAGE" ]; then
      mv "$DEP_PACKAGE" "$DEPENDENCIES_DIR"
      echo "Downloaded and moved: $dep"
    else
      echo "Failed to find downloaded package for: $dep"
    fi
  else
    echo "Failed to download: $dep"
  fi
done

# Create the installation script
INSTALL_SCRIPT="${OUTPUT_DIR}/install_${PACKAGE_NAME}_offline.sh"
echo "Creating installation script: $INSTALL_SCRIPT"

cat <<EOF > "$INSTALL_SCRIPT"
#!/bin/bash

# Check if the script is run as root
if [ "\$(id -u)" -ne 0; then
  echo "This script must be run as root"
  exit 1
fi

# Directory containing the .deb files
BASE_PACKAGE_DIR="\$(dirname "\$0")/base_package"
DEPENDENCIES_DIR="\$(dirname "\$0")/dependencies"

# Install the base package
dpkg -i \$BASE_PACKAGE_DIR/*.deb

# Install all dependency packages
dpkg -i \$DEPENDENCIES_DIR/*.deb

# Fix any missing dependencies
apt-get install -f -y

echo "Installation of ${PACKAGE_NAME} and its dependencies is complete."
EOF

# Make the installation script executable
chmod +x "$INSTALL_SCRIPT"

# Create the tarball
echo "Creating tarball: ${OUTPUT_DIR}.tar.gz"
tar -czvf "${OUTPUT_DIR}.tar.gz" -C "$OUTPUT_DIR" .

# Clean up
rm -rf "$TEMP_DIR"
# Uncomment the next line if you want to remove the OUTPUT_DIR after creating the tarball
# rm -rf "$OUTPUT_DIR"

echo "Package ${PACKAGE_NAME} offline installation archive is ready: ${OUTPUT_DIR}.tar.gz"