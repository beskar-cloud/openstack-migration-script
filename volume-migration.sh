#!/bin/bash

# Configuration
SRC_POOL=""
DST_POOL=""
SRC_NAME=""
DST_NAME=""
SRC_CLUSTER_CONF=""
DST_CLUSTER_CONF=""
SRC_KEYRING=""
DST_KEYRING=""
SRC_ID=""
DST_ID=""
SRC_VOLUME_PREFIX="volume-"
DST_VOLUME_PREFIX=""
VOLUMES_TO_COPY="$1"
CINDER_TYPE="$2"
CINDER_POOL="$3"

# Function to copy a single volume
copy_volume() {
  local src_volume="$1"
  local dst_volume="$2"
  local src_conf="$3"
  local dst_conf="$4"
  local src_keyring="$5"
  local dst_keyring="$6"
  local src_id="$7"
  local dst_id="$8"
  local src_name="$9"
  local dst_name="${10}"
  local src_pool="${11}"
  local dst_pool="${12}"
  local src_volume_prefix="${13}"
  local dst_volume_prefix="${14}"
  local cinder_type="${15}"
  local cinder_pool="${16}"

  echo "Copying volume ${src_volume_prefix}${src_volume} to ${dst_volume_prefix}${dst_volume}..."

  # Get source RBD image

  local volume_size=$(($(rbd --id "${src_id}" --name ${src_name} --keyring "${src_keyring}" --conf "${src_conf}" info "${SRC_POOL}/${src_volume_prefix}${src_volume}"| grep size | awk '{print $2}')*1024))
  #local volume_size=$(($(rbd --id "${src_id}" --name ${src_name} --keyring "${src_keyring}" --conf "${src_conf}" info "${SRC_POOL}/${src_volume_prefix}${src_volume}"| grep size | awk '{print int($2)}')*1024))

  # Map source and destination RBD images
  sudo rbd --id "${src_id}" --name ${src_name} --keyring "${src_keyring}" --conf "${src_conf}" device map "${SRC_POOL}/${src_volume_prefix}${src_volume}"
  sudo rbd --id "${dst_id}" --name ${dst_name} --keyring "${dst_keyring}" --conf "${dst_conf}" create --size "${volume_size}" "${DST_POOL}/${dst_volume_prefix}${dst_volume}"
  sudo rbd --id "${dst_id}" --name ${dst_name} --keyring "${dst_keyring}" --conf "${dst_conf}" device map "${DST_POOL}/${dst_volume_prefix}${dst_volume}"

  # Get the device paths
  local src_device_path=$(rbd --conf "${src_conf}" device list | grep "${src_volume_prefix}${src_volume}" | grep "${src_pool}" | awk '{print $5}')
  local dst_device_path=$(rbd --conf "${dst_conf}" device list | grep "${dst_volume_prefix}${dst_volume}" | grep "${dst_pool}" | awk '{print $5}')

  # Copy data using dd
  sudo dd if="${src_device_path}" of="${dst_device_path}" bs=4M conv=sparse status=progress

  # Unmap the RBD images
  sudo rbd --id "${src_id}" --name ${src_name} --keyring "${src_keyring}" --conf "${src_conf}" device unmap "${src_device_path}"
  sudo rbd --id "${dst_id}" --name ${dst_name} --keyring "${dst_keyring}" --conf "${dst_conf}" device unmap "${dst_device_path}"

  echo "Finished copying ${src_volume_prefix}${src_volume} to ${dst_volume_prefix}${dst_volume}"
  echo "You shoud run:"
  echo "cinder manage --id-type source-name --volume-type ${cinder_type} --name ${dst_volume_prefix}${dst_volume} ${cinder_pool} ${dst_volume_prefix}${dst_volume}"
  echo "Maybe set volume to bootable with adding --bootable"

}

# Main script
for volume in "${VOLUMES_TO_COPY[@]}"; do
  copy_volume "${volume}" "${volume}" "${SRC_CLUSTER_CONF}" "${DST_CLUSTER_CONF}" "${SRC_KEYRING}" "${DST_KEYRING}" "${SRC_ID}" "${DST_ID}" "${SRC_NAME}" "${DST_NAME}" "${SRC_POOL}" "${DST_POOL}" "${SRC_VOLUME_PREFIX}" "${DST_VOLUME_PREFIX}" "${CINDER_TYPE}" "${CINDER_POOL}"
done