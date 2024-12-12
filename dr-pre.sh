#!/bin/bash

# Stop script on error
set -e

# Logging
LOG_DIR="$HOME/logs"
mkdir -p $LOG_DIR
LOG_FILE="$LOG_DIR/datarobot_installation.log"
touch $LOG_FILE

log_message() {
    echo "$(date): $1" | tee -a $LOG_FILE
}

# Global Variables
CONTAINER_TOOL="docker"  # Default container tool, will be updated by select_container_runtime.

# Check dependencies
check_dependencies() {
    log_message "Checking dependencies..."
    for cmd in wget tar zstd jq; do
        if ! command -v $cmd &> /dev/null; then
            log_message "Error: $cmd is not installed. Please install it before running this script."
        fi
    done
    #log_message "All required dependencies are installed."
}


# Function to check and install required utilities
install_utilities() {
    log_message "Checking and installing required utilities..."
    REQUIRED_UTILS=(kubectl helm git zstd docker podman jq)

    for util in "${REQUIRED_UTILS[@]}"; do
        if ! command -v $util &> /dev/null; then
            log_message "$util not found. Attempting to install..."
            case $util in
                kubectl)
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    sudo chmod +x kubectl && sudo mv kubectl /usr/local/bin/
                    ;;
                helm)
                    curl -LO https://get.helm.sh/helm-v3.13.0-linux-amd64.tar.gz
                    tar -zxvf helm-v3.13.0-linux-amd64.tar.gz
                    sudo mv linux-amd64/helm /usr/local/bin/
                    ;;
                git | zstd | jq)
                    sudo apt-get install -y $util || sudo yum install -y $util
                    ;;
                docker | podman)
                    #curl -fsSL https://get.docker.com | bash
                    sudo yum install docker -y
                    sudo systemctl start docker
                    ;;
                *)
                    log_message "Utility $util is not supported for auto-installation."
                    ;;
            esac
        fi
    done
    log_message "All utilities are installed."
}


# Input Variables
read -p "Enter DataRobot version (e.g., 10.1.0): " DR_VERSION

# Prompt for parent directory
read -p "Enter the parent directory for installation [default: /opt/datarobot]: " PARENT_DIR
PARENT_DIR="${PARENT_DIR:-/opt/datarobot}"  # Default to /opt/datarobot if no input is provided

# Construct the full installation directory path
INSTALL_DIR="${PARENT_DIR}/DataRobot-${DR_VERSION}"

# Log the installation directory
log_message "Installation directory set to: $INSTALL_DIR"

# Ensure the directory exists
mkdir -p "$INSTALL_DIR" || {
    log_message "Error: Failed to create installation directory: $INSTALL_DIR"
    exit 1
}




# Prompt for Container Runtime Selection
select_container_runtime() {
    log_message "Prompting for container runtime selection..."
    echo "Choose the container runtime:"
    echo "1. Docker"
    echo "2. Podman"
    echo "3. Sudo Docker"
    read -p "Enter your choice (1, 2, or 3): " runtime_choice
    case $runtime_choice in
        1)
            CONTAINER_TOOL="docker"
            log_message "Selected container runtime: Docker"
            # Adjust permissions for Docker
            log_message "Adjusting permissions for Docker socket..."
            sudo chown "$USER:" /var/run/docker.sock || {
                log_message "Error: Failed to adjust permissions for Docker socket."
                exit 1
            }
            ;;
        2)
            CONTAINER_TOOL="podman"
            log_message "Selected container runtime: Podman"
            ;;
        3)
            CONTAINER_TOOL="sudo docker"
            log_message "Selected container runtime: Sudo Docker"
            # Ensure Docker service is running
            sudo systemctl start docker || {
                log_message "Error: Failed to start Docker service."
                exit 1
            }
            ;;
        *)
            log_message "Invalid choice. Defaulting to Docker."
            CONTAINER_TOOL="docker"
            # Adjust permissions for Docker
            log_message "Adjusting permissions for Docker socket..."
            sudo chown "$USER:" /var/run/docker.sock || {
                log_message "Error: Failed to adjust permissions for Docker socket."
                exit 1
            }
            ;;
    esac
    log_message "Using container tool: $CONTAINER_TOOL"
}


# Ensure proper file extensions
ensure_file_extension() {
    local file_path="$1"
    local expected_extension=".tar"
    if [[ ! "$file_path" == *"$expected_extension" ]]; then
        mv "$file_path" "${file_path}${expected_extension}" || exit 1
        log_message "Renamed $file_path to ${file_path}${expected_extension}"
    fi
}

# Setup directories
setup_directories() {
    log_message "Setting up directories..."
    for dir in "datarobot" "datarobot_pcs" "installer_tools"; do
        dir_path="${INSTALL_DIR}/${dir}"
        if [[ -d "$dir_path" ]]; then
            log_message "Directory $dir_path already exists. Skipping creation."
        else
            mkdir -p "$dir_path"
            chmod -R 755 "$dir_path"
            log_message "Created directory $dir_path."
        fi
    done
}

# Prompt user for binary URLs
BINARY_URLS=() #Initializinf empty array just in case

initialize_binaries() {
    log_message "Prompting user to enter binary URLs for installation..."
    
    binary_names=("datarobot" "datarobot_pcs" "installer_tools")
    for binary in "${binary_names[@]}"; do
        read -p "Enter the download URL for $binary binary: " binary_url
        if [[ -z "$binary_url" ]]; then
            log_message "Error: URL for $binary is required. Exiting."
            exit 1
        fi
        BINARY_URLS+=("$binary_url")
    done

    log_message "Binary URLs initialized successfully."
}

# Download binaries
download_binaries() {
    log_message "Downloading binaries using hardcoded URLs..."
    binary_names=("datarobot" "datarobot_pcs" "installer_tools")
    for i in "${!BINARY_URLS[@]}"; do
        local download_path="${INSTALL_DIR}/${binary_names[$i]}/$(basename "${BINARY_URLS[$i]}")"
        if [[ -f "$download_path.tar" || -f "$download_path" ]]; then
            log_message "Binary ${download_path}.tar already exists. Skipping download."
        else
            wget -O "$download_path" "${BINARY_URLS[$i]}" || exit 1
            ensure_file_extension "$download_path"
        fi
    done
    log_message "Binaries downloaded and validated."
}

# Extract binaries
extract_binaries() {
    log_message "Extracting binaries..."
    for dir in "datarobot" "datarobot_pcs" "installer_tools"; do
        local tar_file=$(find "${INSTALL_DIR}/${dir}" -type f -name "*.tar")
        if [[ -f "$tar_file" ]]; then
            local extraction_dir="${INSTALL_DIR}/${dir}"
            if [[ -d "$extraction_dir" ]]; then
                log_message "Directory $extraction_dir already exists."
                tar -xvf "$tar_file" -C "$extraction_dir"
            else
                mkdir -p "$extraction_dir"
                tar -xvf "$tar_file" -C "$extraction_dir" >> $LOG_FILE || exit 1
                log_message "Extracted $tar_file to $extraction_dir."
            fi
        else
            log_message "No tar file found in ${INSTALL_DIR}/${dir}. Skipping."
        fi
    done
}

# Extract .zstd files
extract_zstd_files() {
    log_message "Finding and extracting .zstd files in datarobot and datarobot_pcs images directories..."
    for subdir in "datarobot" "datarobot_pcs"; do
        local images_dir="${INSTALL_DIR}/${subdir}/images"
        if [[ -d "$images_dir" ]]; then
            find "$images_dir" -type f -name "*.zst" -exec zstd -d --long=30 {} \; || exit 1
        else
            log_message "Images directory $images_dir does not exist. Skipping .zstd extraction."
        fi
    done
    log_message ".zstd files extraction completed for datarobot and datarobot_pcs images directories."
}

# Load .tar files into Docker/Podman
load_tar_to_container_runtime() {
    log_message "Loading .tar files into container runtime..."
    for subdir in "datarobot" "datarobot_pcs"; do
        local images_dir="${INSTALL_DIR}/${subdir}/images"
        if [[ -d "$images_dir" ]]; then
            find "$images_dir" -type f -name "*.tar" -exec $CONTAINER_TOOL load -i {} \; || exit 1
            log_message "Loaded .tar files from $images_dir into $CONTAINER_TOOL."
        else
            log_message "Images directory $images_dir does not exist. Skipping container runtime loading."
        fi
    done
}

# Global variable to store environment
ENV_NAME=""

# Retag and Push Images to Container Registry
push_images_to_registry() {
    log_message "Starting the process to retag and push images to the container registry."

    echo "Select your container registry type:"
    echo "1. Generic Docker Registry"
    echo "2. AWS ECR"
    echo "3. Azure ACR"
    echo "4. Google Artifact Registry (GAR)"
    read -p "Enter the number corresponding to your registry type: " REGISTRY_CHOICE

    # Registry-specific logic
    case $REGISTRY_CHOICE in
        1)
            # Generic Docker Registry
            ENV_NAME="generic"
            read -p "Enter the Docker Registry URL (without https://): " DOCKER_REGISTRY_URL
            read -p "Enter the Docker Registry Username: " DOCKER_REGISTRY_USERNAME
            read -sp "Enter the Docker Registry Password: " DOCKER_REGISTRY_PASSWORD
            echo ""
            $CONTAINER_TOOL login -u "$DOCKER_REGISTRY_USERNAME" -p "$DOCKER_REGISTRY_PASSWORD" "$DOCKER_REGISTRY_URL" || {
                log_message "Error: Failed to log into Docker registry. Please check your credentials."
                exit 1
            }

            read -p "Enter the DataRobot Repository name (e.g., datarobot-dev): " REPO_NAME
            FULL_REPO_URL="$DOCKER_REGISTRY_URL/$REPO_NAME"

            log_message "Retagging and pushing images to Docker Registry: $DOCKER_REGISTRY_URL..."
            for i in $($CONTAINER_TOOL images --format '{{.Repository}}:{{.Tag}}' | grep -v 'registry' | grep -v "$DOCKER_REGISTRY_URL"); do
                NEW_REPO="$DOCKER_REGISTRY_URL/$(echo $i | cut -d/ -f2-)"
                log_message "Retagging $i as $NEW_REPO"
                $CONTAINER_TOOL tag "$i" "$NEW_REPO" || {
                    log_message "Error: Failed to retag $i. Skipping."
                    continue
                }
                log_message "Pushing $NEW_REPO..."
                $CONTAINER_TOOL push "$NEW_REPO" || {
                    log_message "Error: Failed to push $NEW_REPO. Skipping."
                    continue
                }
            done
            log_message "Retag and push process to Docker Registry completed successfully."
            ;;
        2)
            # AWS ECR
            ENV_NAME="aws"
            read -p "Enter AWS Region: " AWS_REGION
            read -p "Enter AWS ECR URL (e.g., <AWS_ACCOUNT_ID>.dkr.ecr.$AWS_REGION.amazonaws.com): " AWS_ECR_URL
            aws ecr get-login-password --region "$AWS_REGION" | $CONTAINER_TOOL login --username AWS --password-stdin "$AWS_ECR_URL" || exit 1

            read -p "Enter the DataRobot Repository name (e.g., datarobot-dev): " AWS_ECR_REPO
            FULL_REPO_URL="${AWS_ECR_URL}/${AWS_ECR_REPO}"

            log_message "Checking and creating repositories in ECR if necessary..."
            # Create repositories dynamically if they do not exist
            for i in $($CONTAINER_TOOL images --format '{{.Repository}}' | grep -v 'registry' | grep -v '.dkr.ecr.');
                do
                    NEW_REPO=${AWS_ECR_REPO}/$(echo $i)
                    echo $NEW_REPO
                    aws ecr describe-repositories --repository-names ${NEW_REPO} || aws ecr create-repository --repository-name ${NEW_REPO}
                done

            log_message "Processing additional repositories required by the build-service..."
            # Create custom build-service repositories
            for custom in base-image services/custom-model-conversion managed-image ephemeral-image custom-apps/managed-image custom-jobs/managed-image;
                do
                    NEW_REPO=${AWS_ECR_REPO}/${custom}
                    echo $NEW_REPO
                    aws ecr describe-repositories --repository-names ${NEW_REPO} || aws ecr create-repository --repository-name ${NEW_REPO}
                done

            log_message "Retagging and pushing images to ECR..."
            for i in $($CONTAINER_TOOL images --format '{{.Repository}}:{{.Tag}}' | grep -v 'registry' | grep -v '.dkr.ecr.');
              do
                NEW_REPO=${FULL_REPO_URL}/$(echo $i);
                echo $NEW_REPO
                $CONTAINER_TOOL tag $i $NEW_REPO
                $CONTAINER_TOOL push $NEW_REPO
            done

            log_message "Retag and push process to AWS ECR completed successfully."
            ;;
        3)
            # Azure ACR
            ENV_NAME="azure"
                log_message "Starting the process to retag and push images to Azure ACR."

                # Login to Azure
                log_message "Logging into Azure CLI..."
                az login || {
                    log_message "Error: Failed to log in to Azure CLI. Ensure you have Azure CLI installed and configured."
                    exit 1
                }

                # Login to Azure ACR
                read -p "Enter Azure ACR Name: " AZ_ACR_NAME
                log_message "Logging into Azure ACR: $AZ_ACR_NAME..."
                ACR_JSON=$(az acr login --expose-token -n "$AZ_ACR_NAME" 2>/dev/null) || {
                    log_message "Error: Failed to retrieve ACR login token. Check your ACR name."
                    exit 1
                }

                # Extract token and URL from JSON
                AZ_ACR_URL=$(echo "$ACR_JSON" | jq -r '.loginServer')
                AZ_ACR_LOGIN_TOKEN=$(echo "$ACR_JSON" | jq -r '.accessToken')

                if [[ -z "$AZ_ACR_URL" || -z "$AZ_ACR_LOGIN_TOKEN" ]]; then
                    log_message "Error: Failed to extract ACR login server or token."
                    exit 1
                fi

                # Docker login to ACR
                log_message "Logging into ACR using Docker..."
                $CONTAINER_TOOL login "$AZ_ACR_URL" -u "00000000-0000-0000-0000-000000000000" -p "$AZ_ACR_LOGIN_TOKEN" || {
                    log_message "Error: Failed to log into Azure ACR with Docker."
                    exit 1
                }

                # Set repository and full URL
                read -p "Enter the DataRobot Repository name (e.g., datarobot-dev): " AZ_ACR_REPO
                export FULL_ACR_URL="${AZ_ACR_URL}/${AZ_ACR_REPO}"

                # Retag and push images
                log_message "Retagging and pushing images to Azure ACR..."
                for i in $($CONTAINER_TOOL images --format '{{.Repository}}:{{.Tag}}' | grep -v 'registry'); do
                    NEW_REPO="${FULL_ACR_URL}/$(echo $i)"
                    log_message "Retagging $i as $NEW_REPO"
                    $CONTAINER_TOOL tag "$i" "$NEW_REPO" || {
                        log_message "Error: Failed to retag $i. Skipping."
                        continue
                    }

                    log_message "Pushing $NEW_REPO"
                    $CONTAINER_TOOL push "$NEW_REPO" || {
                        log_message "Error: Failed to push $NEW_REPO. Skipping."
                        continue
                    }
                done
                log_message "Retag and push process to Azure ACR completed successfully."

            ;;
        4)
            # Google Artifact Registry (GAR)
            ENV_NAME="google"
            read -p "Enter GCP Region: " GCP_REGION
            read -p "Enter GCP Project Name: " GCP_PROJECT_NAME
            read -p "Enter GAR Repository Name (e.g., datarobot-dev): " REPO_NAME
            echo "$GCP_BASE64_SERVICE_ACCOUNT_KEY" | $CONTAINER_TOOL login -u _json_key_base64 --password-stdin "https://${GCP_REGION}-docker.pkg.dev" || exit 1
            FULL_REPO_URL="https://${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_NAME}/${REPO_NAME}"
            ;;
        *)
            log_message "Invalid choice. Exiting."
            return 1
            ;;
    esac
    log_message "Retag and push process completed successfully."
}

create_helm_values() {
    log_message "Starting the creation of Helm chart values files..."

    log_message "Using environment: $ENV_NAME"

    # Prompt for HA/Non-HA deployment
    read -p "Is this a High Availability (HA) deployment? (y/n): " HA_CHOICE
    case $HA_CHOICE in
        [Yy]*)
            HA_MODE="ha"
            ;;
        [Nn]*)
            HA_MODE="non-ha"
            ;;
        *)
            log_message "Invalid HA/Non-HA choice. Defaulting to Non-HA."
            HA_MODE="non-ha"
            ;;
    esac
    log_message "Deployment mode selected: $HA_MODE"

    # Locate example values files directory
    EXAMPLES_DIR="${INSTALL_DIR}/installer_tools/example_umbrella_chart_values"
    if [[ ! -d "$EXAMPLES_DIR" ]]; then
        log_message "Error: Example values directory not found: $EXAMPLES_DIR"
        return 1
    fi

    # 1. Copy environment-based values file
    MATCHING_FILES=($(ls "$EXAMPLES_DIR" | grep "$ENV_NAME"))
    if [[ ${#MATCHING_FILES[@]} -eq 0 ]]; then
        log_message "Error: No values files found for environment: $ENV_NAME"
        return 1
    fi

    echo "Select the values file for the environment:"
    for i in "${!MATCHING_FILES[@]}"; do
        echo "$((i+1)). ${MATCHING_FILES[$i]}"
    done

    read -p "Enter the number corresponding to your choice: " FILE_CHOICE
    if [[ $FILE_CHOICE -lt 1 || $FILE_CHOICE -gt ${#MATCHING_FILES[@]} ]]; then
        log_message "Invalid choice. Exiting module."
        return 1
    fi

    SELECTED_FILE="${MATCHING_FILES[$((FILE_CHOICE-1))]}"
    log_message "Selected environment-based file: $SELECTED_FILE"
    cp "$EXAMPLES_DIR/$SELECTED_FILE" "${INSTALL_DIR}/values.yaml" || {
        log_message "Error: Failed to copy the environment-based file."
        return 1
    }
    log_message "Environment-based Helm values file created successfully: ${INSTALL_DIR}/values.yaml"

    # 2. Copy PCS-specific values file
    PCS_MATCHING_FILES=($(ls "$EXAMPLES_DIR" | grep "pcs"))
    if [[ ${#PCS_MATCHING_FILES[@]} -eq 0 ]]; then
        log_message "Error: No PCS values files found."
        return 1
    fi

    echo "Select the PCS-specific values file to use:"
    for i in "${!PCS_MATCHING_FILES[@]}"; do
        echo "$((i+1)). ${PCS_MATCHING_FILES[$i]}"
    done

    read -p "Enter the number corresponding to your choice: " PCS_FILE_CHOICE
    if [[ $PCS_FILE_CHOICE -lt 1 || $PCS_FILE_CHOICE -gt ${#PCS_MATCHING_FILES[@]} ]]; then
        log_message "Invalid choice. Exiting module."
        return 1
    fi

    SELECTED_PCS_FILE="${PCS_MATCHING_FILES[$((PCS_FILE_CHOICE-1))]}"
    log_message "Selected PCS-specific file: $SELECTED_PCS_FILE"
    cp "$EXAMPLES_DIR/$SELECTED_PCS_FILE" "${INSTALL_DIR}/pcs-values.yaml" || {
        log_message "Error: Failed to copy the PCS-specific file."
        return 1
    }
    log_message "PCS-specific Helm values file created successfully: ${INSTALL_DIR}/pcs-values.yaml"

    # 3. Copy small_pcs.yaml if Non-HA
    if [[ "$HA_MODE" == "non-ha" ]]; then
        SMALL_PCS_FILE="${INSTALL_DIR}/installer_tools/example_tshirt_size_values/small_pcs.yaml"
        if [[ -f "$SMALL_PCS_FILE" ]]; then
            cp "$SMALL_PCS_FILE" "${INSTALL_DIR}/small_pcs.yaml" || {
                log_message "Error: Failed to copy small_pcs.yaml."
                return 1
            }
            log_message "Non-HA deployment: small_pcs.yaml copied to ${INSTALL_DIR}/small_pcs.yaml"
        else
            log_message "Error: small_pcs.yaml file not found in example_tshirt_size_values."
            return 1
        fi
    else
        log_message "HA deployment: Skipping small_pcs.yaml copy."
    fi
}



MODULES=(
    "check_dependencies"
    "install_utilities"
    "select_container_runtime"
    "setup_directories"
    "initialize_binaries"
    "download_binaries"
    "extract_binaries"
    "extract_zstd_files"
    "load_tar_to_container_runtime"
    "push_images_to_registry"
    "create_helm_values"
)

# Helper functions
list_modules() {
    echo "Available modules:"
    for module in "${MODULES[@]}"; do
        echo "- $module"
    done
    exit 0
}

module_exists() {
    for module in "${MODULES[@]}"; do
        if [[ "$module" == "$1" ]]; then
            return 0
        fi
    done
    return 1
}

# Updated main function
main() {
    # Check for flags
    PROMPT_MODE=false
    if [[ "$1" == "--prompt" ]]; then
        PROMPT_MODE=true
        shift # Remove the flag from the arguments
    fi

    if [[ "$1" == "--only" ]]; then
        if [[ -z "$2" ]]; then
            list_modules
        elif module_exists "$2"; then
            log_message "Running module: $2"
            $2
            exit 0
        else
            log_message "Error: Invalid module name '$2'."
            list_modules
        fi
    fi

    # Default full execution
    log_message "Starting DataRobot pre-install setup for version ${DR_VERSION}..."

    for module in "${MODULES[@]}"; do
        if [[ "$PROMPT_MODE" == true ]]; then
            # Prompt the user before running each module
            read -p "Would you like to run $module? (y/n): " user_input
            case $user_input in
                [Yy]*)
                    log_message "Running module: $module"
                    $module || {
                        log_message "Error: $module failed. Exiting."
                        exit 1
                    }
                    ;;
                [Nn]*)
                    log_message "Skipping module: $module"
                    continue
                    ;;
                *)
                    log_message "Invalid input. Skipping module: $module"
                    continue
                    ;;
            esac
        else
            log_message "Running module: $module"
            $module || {
                log_message "Error: $module failed. Exiting."
                exit 1
            }
        fi
    done

    log_message "DataRobot Pre-installation setup completed."
}

# Execute main function with arguments
main "$@"
