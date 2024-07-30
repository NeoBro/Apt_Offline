#!/bin/bash

# Check if a package name was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <package_name>"
  exit 1
fi

PACKAGE_NAME=$1
OUTPUT_DIR="${PACKAGE_NAME}-offline"
DOWNLOAD_DIR="${OUTPUT_DIR}/packages"

# Create directories
mkdir -p "$DOWNLOAD_DIR"

# Download the target package
echo "Downloading target package: $PACKAGE_NAME"
apt-get download "$PACKAGE_NAME"

# Move the downloaded package to the download directory
mv "${PACKAGE_NAME}_*.deb" "$DOWNLOAD_DIR"

# Generate a list of dependencies and download them
echo "Downloading dependencies for: $PACKAGE_NAME"
apt-rdepends "$PACKAGE_NAME" | grep -v "^ " | grep -v "^${PACKAGE_NAME}$" | grep -v "^debconf-2.0$" | xargs apt-get download -y -d -o=dir::cache="${DOWNLOAD_DIR}"

# Create the installation script
INSTALL_SCRIPT="${OUTPUT_DIR}/install_${PACKAGE_NAME}_offline.sh"
echo "Creating installation script: $INSTALL_SCRIPT"

cat <<EOF > "$INSTALL_SCRIPT"
#!/bin/bash

# Check if the script is run as root
if [ "\$(id -u)" -ne 0 ]; then
  echo "This script must be run as root"
  exit 1
fi

# Directory containing the .deb files
DEB_DIR="\$(dirname "\$0")/packages"

# Install all .deb packages in the directory
sudo dpkg -i \$DEB_DIR/*.deb

# Fix any missing dependencies
sudo apt-get -f install

# Install the target package
sudo dpkg -i \$DEB_DIR/${PACKAGE_NAME}_*.deb

echo "Installation of ${PACKAGE_NAME} and its dependencies is complete."
EOF

# Make the installation script executable
chmod +x "$INSTALL_SCRIPT"

# Create the tarball
echo "Creating tarball: ${OUTPUT_DIR}.tar.gz"
tar -czvf "${OUTPUT_DIR}.tar.gz" -C "$OUTPUT_DIR" .

# Clean up
rm -rf "$OUTPUT_DIR"

echo "Package ${PACKAGE_NAME} offline installation archive is ready: ${OUTPUT_DIR}.tar.gz"
