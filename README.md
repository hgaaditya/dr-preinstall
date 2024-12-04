# DataRobot Pre-Installation Script

This script automates the setup and deployment process for **DataRobot** in a Kubernetes-based environment. It performs various preparatory tasks, including checking dependencies, setting up directories, downloading and extracting binaries, managing container images, and generating Helm chart values files.

---

## Features

1. **Dependency Check**: Verifies that required utilities (e.g., `wget`, `zstd`, `jq`) are installed, installing missing utilities as needed.
2. **Directory Setup**: Creates and configures installation directories.
3. **Customizable Binary URLs**: Prompts the user for binary download URLs and uses them dynamically during the installation process.
4. **Binary Management**: Downloads, validates, and extracts installation binaries.
5. **Container Image Management**:
   - Loads `.tar` files into Docker/Podman.
   - Retags and pushes images to container registries such as AWS ECR, Azure ACR, Google Artifact Registry, or a generic Docker registry.
6. **Helm Chart Configuration**:
   - Automatically selects Helm values based on the target environment (AWS, Azure, GCP, or Baremetal/Generic).
   - Supports High Availability (HA) and Non-HA deployments.
7. **Interactive Workflow**: Prompts the user to selectively run modules or proceed automatically.

---

## How to Use

### Prerequisites
- Supported Kubernetes environments: AWS EKS, GCP (Google Kubernetes Engine), Azure AKS, or OpenShift/Baremetal.
- Ensure `bash` is installed and available on your system.

### Script Execution
Clone this repository and execute the script as follows:

1. **Full Installation**
   ```bash
   ./datarobot_pre_install.sh

2. **Selective Execution with Prompts To prompt before running each module**
   ```bash
   ./datarobot_pre_install.sh --prompt
   
3. **Run a Specific Module To run a specific module, use the --only flag**
```bash
./datarobot_pre_install.sh --only <module_name>
```
Example:
```bash
./datarobot_pre_install.sh --only check_dependencies
```

###Available modules:
check_dependencies
install_utilities
select_container_runtime
setup_directories
initialize_binaries
download_binaries
extract_binaries
extract_zstd_files
load_tar_to_container_runtime
push_images_to_registry
create_helm_values






