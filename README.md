# OpenStack Instance Migration Script

This script facilitates the migration of an OpenStack instance from one cluster to another, including migrating volumes and network configurations. **Please ensure you have administrative privileges** for the OpenStack configurations being used.

## Prerequisites

1. **Admin Privileges**: Ensure that the OpenStack configuration files (`ORIG_OPENSTACK` and `DEST_OPENSTACK`) used by the script have administrative privileges.
2. **Dependencies**: The following command-line tools must be installed:
    - `openstack` CLI
    - `cinder` CLI
    - `grepcidr` (installation depends on your OS)
3. **Ceph files**: Ensure you have the ceph config file, keyring and fsid of both ceph cluster.



## Important Warnings

Network and Subnet Names: The names of networks and subnets must be identical across both clusters. Any discrepancies will cause the migration to fail or partially fail.

Instance Status: Ensure that the instance status is correctly identified. The script will manage the state of the instance (e.g., stop it if it's running).


## Usage

```bash
./migration.sh <ORIG_CONF_FILE> <DEST_CONF_FILE> <CINDER_TYPE> <CINDER_POOL_DESTINATION> <VM_NAME>
```

**`<ORIG_CONF_FILE>:`** Path to the OpenStack configuration file for the original cluster.

**`<DEST_CONF_FILE>`:** Path to the OpenStack configuration file for the destination cluster.

**`<CINDER_TYPE>:`** The type of Cinder storage used.

**`<CINDER_POOL_DESTINATION>:`** The destination Cinder pool.

**`<VM_NAME>:`** The name of the virtual machine (VM) to be migrated.

Note: All parameters are required. If any parameter is missing, the script will fail.



## Volume Migration Process

The `migration.sh` script will provide instructions for running the `volume-migration.sh` script. This additional script is crucial for copying the volumes from the original Ceph cluster to the destination Ceph cluster.

### Running the Volume Migration Script

To migrate a volume, use the following command:

```bash
./volume-migration.sh <VOLUME_UUID> <VOLUME_TYPE> <CEPH_POOL_NAME>
```

**`<VOLUME_UUID>:`** The unique identifier of the volume to be migrated.

**`<VOLUME_TYPE>:`** The type of the volume (e.g., SSD, HDD).

**`<CEPH_POOL_NAME>:`** The name of the Ceph pool where the volume will be migrated.



Finalizing the Volume Migration

After the volume-migration.sh script completes, it will provide a command to make the newly migrated volume available for the Cinder service. Execute the following command to register the volume with Cinder:

```bash
cinder manage --id-type source-name --volume-type <VOL_TYPE> --name <VOLUME_UUID> cinder-volume-worker@<VOL_TYPE> <VOLUME_UUID> --bootable
```

**`<VOL_TYPE>:`** The volume type, consistent with the destination environment.

**`<VOLUME_UUID>:`** The unique identifier of the volume you just migrated.

Note: For non bootable disk, remove the `--bootable` flag.


Sample of variables in volume-migration.sh
```bash
# Configuration
SRC_POOL="volumes-ssd"
DST_POOL="cinder.ssd"
SRC_NAME="client.admin"
DST_NAME="client.admin"
SRC_CLUSTER_CONF="ceph_old/ceph.conf"
DST_CLUSTER_CONF="ceph_new/ceph.conf"
SRC_KEYRING="ceph_old/ceph.client.admin.keyring"
DST_KEYRING="ceph_new/ceph.client.admin.keyring"
SRC_ID="daf1b014-24cc-47a3-b8a6-c23ea1549e9e"
DST_ID="3a8f66e6-1528-4b63-b36b-et0y0ew0r0tf"
SRC_VOLUME_PREFIX="volume-"
DST_VOLUME_PREFIX=""
VOLUMES_TO_COPY="$1"
CINDER_TYPE="$2"
CINDER_POOL="$3"
```

## Script Workflow

The script follows a structured workflow to ensure a smooth and complete migration of your OpenStack instance. Below is a detailed breakdown of each step:

1. **Cluster Connection**
   - The script first establishes a connection to the original cluster using the provided `ORIG_CONF_FILE`.
   - It then connects to the destination cluster using the `DEST_CONF_FILE`.

2. **Instance and Volume Details Mining**
   - Metadata, network configurations, and volume details of the instance are extracted from the original cluster.
   - This step ensures that all necessary details are captured for accurate migration.

3. **Volume Management**
   - The script detaches the volumes from the original instance to prepare them for migration.
   - These volumes are then migrated to the destination cluster, ensuring data consistency and availability.

4. **Network Port Recreation**
   - The script recreates network ports on the destination cluster to mirror the original instance's network configuration.
   - This step is crucial for maintaining network integrity and connectivity after migration.

5. **Instance Creation Script**
   - A new bash script (`<VM_NAME>-create.sh`) is generated. This script can be used to create the instance on the destination cluster.
   - It includes the necessary commands to attach the migrated volumes and configure the network ports.

6. **Migration Completion**
   - The script provides detailed instructions to finalize the migration process.
   - This includes commands for volume migration and any additional manual steps required to complete the setup on the destination cluster.



## Additional Steps

After the primary migration process, there are a few critical steps you may need to take to ensure the instance functions correctly on the destination cluster:

- **Volume Migration:**
  - The script provides specific commands and guidance to facilitate the migration of volumes to the destination cluster.
  - It is essential to follow these commands precisely to ensure that all volumes are correctly migrated and attached to the new instance.

- **Adjust Availability Zone (AZ) and Flavor:**
  - Depending on the configuration of the destination cluster, you may need to manually adjust the Availability Zone (AZ) and flavor settings for the newly created instance.
  - This step is crucial to align the instance with the appropriate resources and ensure optimal performance.



## Troubleshooting

During the execution of the script, you may encounter some common issues. Below are troubleshooting tips to help resolve them:

- **Missing Binaries:**
  - If the script fails due to missing binaries such as `openstack`, `cinder`, or `grepcidr`, it will exit with an error message.
  - To resolve this, ensure that these dependencies are installed on your system using the appropriate package manager (e.g., `apt`, `yum`, `brew`).

- **Environment Variables:**
  - The script heavily relies on environment variables, which are set by sourcing the OpenStack configuration files.
  - If any required environment variables are not set or are empty, the script will terminate and display an error.
  - Ensure that both the original and destination OpenStack configuration files are correctly sourced before running the script.
